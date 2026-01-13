use secp256k1::{Secp256k1, SecretKey, PublicKey};
use sha2::{Sha256, Digest};
use rand::rngs::OsRng;
use rand::RngCore;

/// Generate a secp256k1 keypair and return JSON string with private/public hex
pub fn generate_keypair() -> String {
    let secp = Secp256k1::new();
    let mut rng = OsRng;
    let mut buf = [0u8; 32];
    rng.fill_bytes(&mut buf);
    let secret_key = SecretKey::from_slice(&buf).expect("failed to create secret key");
    let public_key = PublicKey::from_secret_key(&secp, &secret_key);

    let secret_hex = hex::encode(secret_key.secret_bytes());
    let public_hex = hex::encode(public_key.serialize());

    format!("{{\"privateKey\":\"{}\",\"publicKey\":\"{}\"}}", secret_hex, public_hex)
}

/// Sign a message using the given private key hex. Returns signature hex.
pub fn sign_message(private_key_hex: &str, message: &str) -> String {
    let secp = Secp256k1::new();

    let private_key_bytes = hex::decode(private_key_hex).expect("invalid private key hex");
    let secret_key = SecretKey::from_slice(&private_key_bytes).expect("invalid private key");

    let mut hasher = Sha256::new();
    hasher.update(message.as_bytes());
    let message_hash = hasher.finalize();

    let message = secp256k1::Message::from_slice(&message_hash).expect("invalid message hash length");
    let signature = secp.sign_ecdsa(&message, &secret_key);

    hex::encode(signature.serialize_compact())
}

/// Verify a signature. Returns true if valid.
pub fn verify_signature(public_key_hex: &str, message: &str, signature_hex: &str) -> bool {
    let secp = Secp256k1::new();

    let public_key_bytes = hex::decode(public_key_hex).expect("invalid public key hex");
    let public_key = PublicKey::from_slice(&public_key_bytes).expect("invalid public key");

    let signature_bytes = hex::decode(signature_hex).expect("invalid signature hex");
    let signature = secp256k1::ecdsa::Signature::from_compact(&signature_bytes).expect("invalid signature");

    let mut hasher = Sha256::new();
    hasher.update(message.as_bytes());
    let message_hash = hasher.finalize();
    let message = secp256k1::Message::from_slice(&message_hash).expect("invalid message hash length");

    secp.verify_ecdsa(&message, &signature, &public_key).is_ok()
}
