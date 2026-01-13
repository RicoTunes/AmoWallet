from fastapi import APIRouter, HTTPException
from pydantic import BaseModel
from worker_pool import RustWorkerPool
import os

router = APIRouter()

class SignRequest(BaseModel):
    privateKey: str
    message: str

class VerifyRequest(BaseModel):
    publicKey: str
    message: str
    signature: str

POOL = RustWorkerPool(size=int(os.getenv('RUST_POOL_SIZE', '2')))


@router.post('/generate')
async def generate():
    try:
        res = POOL.generate_keypair()
        return res.get('result') if isinstance(res, dict) else res
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@router.post('/sign')
async def sign(req: SignRequest):
    try:
        res = POOL.sign_message(req.privateKey, req.message)
        return {'signature': res.get('result') if isinstance(res, dict) else res}
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@router.post('/verify')
async def verify(req: VerifyRequest):
    try:
        res = POOL.verify_signature(req.publicKey, req.message, req.signature)
        return {'valid': bool(res.get('result') if isinstance(res, dict) else res)}
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))
