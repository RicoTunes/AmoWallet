use rustls::ServerConfig;
use rustls_pemfile::{certs, pkcs8_private_keys};
use std::fs::File;
use std::io::BufReader;
use std::path::Path;
use std::sync::Arc;
use tokio::net::TcpListener;
use tokio_rustls::TlsAcceptor;
use hyper::service::{make_service_fn, service_fn};
use hyper::{Body, Request, Response, Server, StatusCode};
use std::convert::Infallible;
use tracing::{info, error};

/// Load TLS certificates and private key
pub fn load_tls_config(cert_path: &Path, key_path: &Path) -> Result<ServerConfig, Box<dyn std::error::Error>> {
    // Load certificates
    let cert_file = File::open(cert_path)?;
    let mut cert_reader = BufReader::new(cert_file);
    let certs: Vec<_> = certs(&mut cert_reader)
        .collect::<Result<Vec<_>, _>>()?;

    // Load private key
    let key_file = File::open(key_path)?;
    let mut key_reader = BufReader::new(key_file);
    let mut keys = pkcs8_private_keys(&mut key_reader)
        .collect::<Result<Vec<_>, _>>()?;

    if keys.is_empty() {
        return Err("No private keys found".into());
    }

    // Build TLS configuration with strong cipher suites
    let config = ServerConfig::builder()
        .with_no_client_auth()
        .with_single_cert(
            certs.into_iter().map(rustls::pki_types::CertificateDer::from).collect(),
            rustls::pki_types::PrivateKeyDer::from(keys.remove(0))
        )?;

    Ok(config)
}

/// Generate self-signed certificate for development
pub fn generate_self_signed_cert(output_dir: &Path) -> Result<(), Box<dyn std::error::Error>> {
    use std::process::Command;

    info!("Generating self-signed certificate for development...");

    let cert_path = output_dir.join("cert.pem");
    let key_path = output_dir.join("key.pem");

    // Check if certificates already exist
    if cert_path.exists() && key_path.exists() {
        info!("Self-signed certificates already exist");
        return Ok(());
    }

    // Create output directory
    std::fs::create_dir_all(output_dir)?;

    // Generate self-signed certificate using OpenSSL
    let output = Command::new("openssl")
        .args([
            "req", "-x509", "-newkey", "rsa:4096",
            "-keyout", key_path.to_str().unwrap(),
            "-out", cert_path.to_str().unwrap(),
            "-days", "365", "-nodes",
            "-subj", "/C=US/ST=State/L=City/O=Development/CN=localhost"
        ])
        .output()?;

    if !output.status.success() {
        error!("Failed to generate self-signed certificate: {}", String::from_utf8_lossy(&output.stderr));
        return Err("Certificate generation failed".into());
    }

    info!("Self-signed certificate generated successfully");
    Ok(())
}

/// Request handler
async fn handle_request(req: Request<Body>) -> Result<Response<Body>, Infallible> {
    let path = req.uri().path();
    
    match path {
        "/health" => {
            Ok(Response::new(Body::from(r#"{"status":"ok","secure":true}"#)))
        }
        _ => {
            let mut not_found = Response::default();
            *not_found.status_mut() = StatusCode::NOT_FOUND;
            Ok(not_found)
        }
    }
}

/// Start HTTPS server with Rust TLS
pub async fn start_https_server(
    addr: &str,
    cert_path: &Path,
    key_path: &Path,
) -> Result<(), Box<dyn std::error::Error>> {
    // Load TLS configuration
    let tls_config = load_tls_config(cert_path, key_path)?;
    let tls_acceptor = TlsAcceptor::from(Arc::new(tls_config));

    // Bind to address
    let listener = TcpListener::bind(addr).await?;
    info!("🔒 Rust HTTPS server listening on {}", addr);

    loop {
        let (stream, peer_addr) = listener.accept().await?;
        let acceptor = tls_acceptor.clone();

        tokio::spawn(async move {
            match acceptor.accept(stream).await {
                Ok(tls_stream) => {
                    info!("✅ TLS connection established from {}", peer_addr);
                    
                    // Handle HTTPS request
                    let service = service_fn(handle_request);
                    if let Err(e) = hyper::server::conn::Http::new()
                        .serve_connection(tls_stream, service)
                        .await
                    {
                        error!("Error serving connection: {}", e);
                    }
                }
                Err(e) => {
                    error!("❌ TLS handshake failed: {}", e);
                }
            }
        });
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::path::PathBuf;

    #[test]
    fn test_generate_self_signed() {
        let temp_dir = PathBuf::from("./test_certs");
        let result = generate_self_signed_cert(&temp_dir);
        assert!(result.is_ok() || temp_dir.join("cert.pem").exists());
        
        // Cleanup
        let _ = std::fs::remove_dir_all(temp_dir);
    }
}
