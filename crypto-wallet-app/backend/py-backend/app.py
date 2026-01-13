import os
from fastapi import FastAPI
from routes.wallet import router as wallet_router

app = FastAPI()

app.include_router(wallet_router, prefix='/api/wallet')


@app.get('/health')
async def health():
    return {'status': 'ok'}


if __name__ == '__main__':
    import uvicorn
    uvicorn.run('app:app', host='0.0.0.0', port=int(os.getenv('PORT', '3000')))
