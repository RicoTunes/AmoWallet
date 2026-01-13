"""
Simple Python Crypto Service
Pure Python implementation without Rust dependency
"""
import sys
import os
sys.path.append(os.path.dirname(__file__))

import uvicorn
from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel
from pure_python_crypto import PurePythonCrypto
import logging

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s %(levelname)s %(message)s',
    stream=sys.stdout
)

app = FastAPI(title="Crypto Wallet Python Service")
crypto = PurePythonCrypto()

# CORS
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

class SignRequest(BaseModel):
    privateKey: str
    message: str

class VerifyRequest(BaseModel):
    publicKey: str
    message: str
    signature: str

@app.get("/health")
async def health():
    """Health check endpoint"""
    return {"status": "healthy", "service": "python-crypto", "version": "1.0.0"}

@app.post("/generate")
async def generate_keypair():
    """Generate a new keypair"""
    try:
        result = crypto.generate_keypair()
        logging.info("Generated new keypair")
        return result
    except Exception as e:
        logging.error(f"Keypair generation failed: {e}")
        raise HTTPException(status_code=500, detail=str(e))

@app.post("/sign")
async def sign_message(request: SignRequest):
    """Sign a message with a private key"""
    try:
        signature = crypto.sign_message(request.privateKey, request.message)
        logging.info("Message signed successfully")
        return {"signature": signature}
    except Exception as e:
        logging.error(f"Signing failed: {e}")
        raise HTTPException(status_code=400, detail=str(e))

@app.post("/verify")
async def verify_signature(request: VerifyRequest):
    """Verify a signature"""
    try:
        valid = crypto.verify_signature(
            request.publicKey,
            request.message,
            request.signature
        )
        logging.info(f"Signature verification: {valid}")
        return {"valid": valid}
    except Exception as e:
        logging.error(f"Verification failed: {e}")
        raise HTTPException(status_code=400, detail=str(e))

if __name__ == "__main__":
    port = int(os.environ.get("PORT", 8001))
    logging.info(f"🚀 Starting Python Crypto Service on port {port}")
    logging.info("📦 Using pure Python implementation (no Rust required)")
    uvicorn.run(app, host="0.0.0.0", port=port, log_level="info")
