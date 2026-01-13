import os
import hashlib
import secrets
from typing import Dict, Tuple
import ecdsa
from ecdsa import SECP256k1, SigningKey, VerifyingKey

class PurePythonCrypto:
    """Pure Python cryptographic implementation using ecdsa library"""
    
    def generate_keypair(self) -> Dict[str, str]:
        """Generate a secp256k1 keypair"""
        # Generate private key
        private_key = SigningKey.generate(curve=SECP256k1)
        private_key_hex = private_key.to_string().hex()
        
        # Get public key
        public_key = private_key.get_verifying_key()
        public_key_hex = public_key.to_string("compressed").hex()
        
        return {
            "privateKey": private_key_hex,
            "publicKey": public_key_hex
        }
    
    def sign_message(self, private_key_hex: str, message: str) -> str:
        """Sign a message using private key"""
        try:
            private_key_bytes = bytes.fromhex(private_key_hex)
            private_key = SigningKey.from_string(private_key_bytes, curve=SECP256k1)
            
            # Hash the message
            message_hash = hashlib.sha256(message.encode()).digest()
            
            # Sign the hash
            signature = private_key.sign_digest(message_hash)
            
            return signature.hex()
        except Exception as e:
            raise ValueError(f"Signing failed: {str(e)}")
    
    def verify_signature(self, public_key_hex: str, message: str, signature_hex: str) -> bool:
        """Verify a signature"""
        try:
            public_key_bytes = bytes.fromhex(public_key_hex)
            public_key = VerifyingKey.from_string(public_key_bytes, curve=SECP256k1)
            
            # Hash the message
            message_hash = hashlib.sha256(message.encode()).digest()
            
            # Verify the signature
            signature_bytes = bytes.fromhex(signature_hex)
            return public_key.verify_digest(signature_bytes, message_hash)
        except Exception:
            return False

# Create global instance
crypto = PurePythonCrypto()