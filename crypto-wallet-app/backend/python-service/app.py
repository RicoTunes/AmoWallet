import os
import sys
import uvicorn
from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel
from worker_pool import RustWorkerPool

# Configure logging to stdout instead of file
import logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s %(levelname)s %(message)s',
    stream=sys.stdout
)

app = FastAPI()

# Add CORS middleware
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],  # In production, restrict to your Flutter app origin
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

# Create a global pool (2 workers by default)
POOL_SIZE = int(os.getenv('RUST_POOL_SIZE', '2'))
BIN_PATH = os.getenv('RUST_BIN_PATH')
pool = RustWorkerPool(bin_path=BIN_PATH, size=POOL_SIZE)


@app.get('/health')
async def health():
    return {'status': 'ok'}


from bip_utils import (
    Bip39MnemonicGenerator, 
    Bip39SeedGenerator,
    Bip44,
    Bip44Coins,
    Bip44Changes
)
# Utilities for address conversions
import hashlib

# Try to get a keccak256 implementation
try:
    # pycryptodome
    from Crypto.Hash import keccak as _keccak_module
    def keccak_256(data: bytes) -> bytes:
        return _keccak_module.new(digest_bits=256, data=data).digest()
except Exception:
    try:
        import sha3 as _sha3
        def keccak_256(data: bytes) -> bytes:
            return _sha3.keccak_256(data).digest()
    except Exception:
        def keccak_256(data: bytes) -> bytes:
            raise RuntimeError('keccak256 not available in this environment')

# optional helpers (base58, nacl) — imported lazily later where needed
try:
    import base58 as _base58
except Exception:
    _base58 = None

try:
    from nacl.signing import SigningKey as _SigningKey
except Exception:
    _SigningKey = None

# Base58 / Base58Check implementation (Bitcoin-style)
_B58_ALPHABET = b'123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz'
def base58_encode(data: bytes) -> str:
    # Convert bytes to integer
    num = int.from_bytes(data, 'big')
    encode = bytearray()
    while num > 0:
        num, rem = divmod(num, 58)
        encode.append(_B58_ALPHABET[rem])
    # leading zeros
    n_pad = 0
    for b in data:
        if b == 0:
            n_pad += 1
        else:
            break
    return ((_B58_ALPHABET[0:1] * n_pad) + bytes(reversed(encode))).decode('ascii')

def base58check_encode(payload: bytes) -> str:
    chk = hashlib.sha256(hashlib.sha256(payload).digest()).digest()[:4]
    return base58_encode(payload + chk)
# Use bip_utils to derive keys/addresses for multiple chains (avoids heavyweight eth-account dependency)
# Log which Bip44 coin enums are available at startup (helps diagnose which native derivations will be used)
try:
    available_coins = [c.name for c in Bip44Coins]
    logging.info('bip_utils: available Bip44Coins: %s', ','.join(available_coins))
    # Helpful quick-check for commonly requested coins
    common = ['BITCOIN', 'ETHEREUM', 'LITECOIN', 'SOLANA', 'TRON', 'RIPPLE', 'DOGECOIN', 'CARDANO', 'BINANCECOIN']
    for name in common:
        logging.info('bip_utils: supports %s: %s', name, str(name in available_coins))
except Exception as e:
    logging.exception('Failed to enumerate Bip44Coins: %s', e)

@app.post('/generate')
async def generate(chain: str | None = None, reveal: bool = False):
    """Generate a real cryptocurrency address and keys for the specified chain."""
    
    # Generate a random mnemonic
    mnemonic = Bip39MnemonicGenerator().FromWordsNumber(12)
    seed_bytes = Bip39SeedGenerator(mnemonic).Generate()
    # Normalize chain symbol
    symbol = (chain or 'ETH').upper()

    # Helper to derive using Bip44 and return consistent shape
    def _derive(coin_enum, note: str | None = None):
        bip44_mst_ctx = Bip44.FromSeed(seed_bytes, coin_enum)
        bip44_acc_ctx = bip44_mst_ctx.Purpose().Coin().Account(0)
        bip44_chg_ctx = bip44_acc_ctx.Change(Bip44Changes.CHAIN_EXT)
        bip44_addr_ctx = bip44_chg_ctx.AddressIndex(0)

        # Special handling for Solana: return base58-encoded private seed and public key
        try:
            is_solana = (coin_enum == Bip44Coins.SOLANA)
        except Exception:
            is_solana = False

        if is_solana and _SigningKey is not None and _base58 is not None:
            # bip_utils returns ed25519 private key bytes for Solana; produce Solana-compatible outputs
            try:
                priv_bytes = bip44_addr_ctx.PrivateKey().Raw().ToBytes()
                # Ensure 32-byte seed
                if len(priv_bytes) >= 32:
                    seed32 = priv_bytes[:32]
                else:
                    seed32 = priv_bytes.rjust(32, b"\x00")

                sk = _SigningKey(seed32)
                vk = sk.verify_key
                pub_bytes = bytes(vk)
                address_b58 = _base58.b58encode(pub_bytes).decode()
                priv_b58 = _base58.b58encode(seed32).decode()
                res = {
                    'address': address_b58,
                    'privateKey': priv_b58,
                    'mnemonic': mnemonic.ToStr(),
                }
                if note:
                    res['note'] = note
                return res
            except Exception:
                # fallthrough to default behavior
                pass

        # Default behavior for most coins
        res = {
            'address': bip44_addr_ctx.PublicKey().ToAddress(),
            'privateKey': bip44_addr_ctx.PrivateKey().Raw().ToHex(),
            'mnemonic': mnemonic.ToStr(),
        }
        if note:
            res['note'] = note
        return res

    # Routing by symbol
    result = None
    if symbol == 'BTC':
        result = _derive(Bip44Coins.BITCOIN)
    elif symbol in ('ETH',):
        result = _derive(Bip44Coins.ETHEREUM)
    elif symbol in ('USDT', 'TETHER'):
        result = _derive(Bip44Coins.ETHEREUM, 'USDT (ERC-20) address derived from Ethereum mnemonic')
    if symbol in ('LTC', 'LITECOIN'):
        # Litecoin (BIP44)
        result = _derive(Bip44Coins.LITECOIN)
    if symbol in ('SOL', 'SOLANA'):
        # Solana uses ed25519 and has its own coin enum in bip_utils
        try:
            return _derive(Bip44Coins.SOLANA)
        except Exception:
            # fallback to ETH derivation if SOL not available
            return _derive(Bip44Coins.ETHEREUM, 'Fallback: derived using ETH path (Solana unsupported here)')
    if symbol in ('TRX', 'TRON'):
        # Tron derivation via BIP44 (many libraries derive same key as ETH but format address differently)
        try:
            return _derive(Bip44Coins.TRON)
        except Exception:
            # Attempt manual Tron address conversion using the Ethereum-style public key
            try:
                # derive ETH context (we can use the same secp256k1 key material)
                bip44_mst_ctx = Bip44.FromSeed(seed_bytes, Bip44Coins.ETHEREUM)
                bip44_acc_ctx = bip44_mst_ctx.Purpose().Coin().Account(0)
                bip44_chg_ctx = bip44_acc_ctx.Change(Bip44Changes.CHAIN_EXT)
                bip44_addr_ctx = bip44_chg_ctx.AddressIndex(0)

                # Get uncompressed public key bytes (remove 0x04 prefix if present)
                raw_pub = bip44_addr_ctx.PublicKey().RawUncompressed().ToBytes()
                if raw_pub and raw_pub[0] == 0x04:
                    raw_pub = raw_pub[1:]

                # keccak256 of public key, take last 20 bytes, prefix with 0x41 and base58check encode
                k = keccak_256(raw_pub)
                eth_addr_bytes = k[-20:]
                tron_payload = b"\x41" + eth_addr_bytes
                tron_addr = base58check_encode(tron_payload)

                return {
                    'address': tron_addr,
                    'privateKey': bip44_addr_ctx.PrivateKey().Raw().ToHex(),
                    'mnemonic': mnemonic.ToStr(),
                    'note': 'Tron address derived from Ethereum key (converted)'
                }
            except Exception:
                # fallback to ETH derivation if manual conversion fails
                return _derive(Bip44Coins.ETHEREUM, 'Fallback: derived using ETH path (TRON support unavailable)')
    if symbol in ('XRP', 'RIPPLE'):
        try:
            return _derive(Bip44Coins.RIPPLE)
        except Exception:
            return _derive(Bip44Coins.ETHEREUM, 'Fallback: derived using ETH path (XRP support unavailable)')

    # Default: ETH if nothing matched
    if result is None:
        result = _derive(Bip44Coins.ETHEREUM)

    # If reveal flag is false, only return the address (plus optional note)
    if not reveal:
        minimal = {'address': result.get('address')}
        if 'note' in result:
            minimal['note'] = result['note']
        return minimal

    return result


@app.post('/sign')
async def sign(req: SignRequest):
    try:
        res = pool.sign_message(req.privateKey, req.message)
        return {'signature': res.get('result') if isinstance(res, dict) else res}
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@app.post('/verify')
async def verify(req: VerifyRequest):
    try:
        res = pool.verify_signature(req.publicKey, req.message, req.signature)
        return {'valid': bool(res.get('result') if isinstance(res, dict) else res)}
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@app.get('/market/prices')
async def market_prices():
    """Fetch current USD prices for a small set of coins from CoinGecko.

    Returns JSON in the shape: { 'data': { 'BTC': {'symbol':'BTC','price_usd': 60000.0}, ... } }
    If the external API fails, returns a best-effort fallback (previously mocked values).
    """
    import requests

    symbol_to_id = {
        'BTC': 'bitcoin',
        'USDT': 'tether',
        'ETH': 'ethereum',
        'TRX': 'tron',
        'XRP': 'ripple',
        'BNB': 'binancecoin',
    }

    ids = ','.join(symbol_to_id.values())
    url = 'https://api.coingecko.com/api/v3/simple/price'
    params = {'ids': ids, 'vs_currencies': 'usd'}

    try:
        # Use CoinGecko /coins/markets endpoint which returns an array with current_price
        markets_url = 'https://api.coingecko.com/api/v3/coins/markets'
        headers = {'Accept': 'application/json', 'User-Agent': 'crypto-wallet-app/1.0'}
        params_markets = {'vs_currency': 'usd', 'ids': ids, 'order': 'market_cap_desc', 'per_page': 250, 'page': 1, 'sparkline': 'false'}
        resp = requests.get(markets_url, params=params_markets, headers=headers, timeout=8)
        resp.raise_for_status()
        list_data = resp.json()

        prices = {}
        # initialize with None
        for sym in symbol_to_id.keys():
            prices[sym] = {'symbol': sym, 'price_usd': None}

        # populate from coins/markets response
        for item in list_data:
            cid = item.get('id')
            current_price = item.get('current_price')
            for sym, mapped in symbol_to_id.items():
                if mapped == cid:
                    try:
                        prices[sym]['price_usd'] = float(current_price) if current_price is not None else None
                    except Exception:
                        prices[sym]['price_usd'] = None

        # If some prices still missing, attempt simple/price for those
        missing = [s for s, v in prices.items() if v['price_usd'] is None]
        if missing:
            try:
                logging.info('Some symbols missing from markets endpoint, trying simple/price for: %s', missing)
                resp2 = requests.get(url, params=params, headers=headers, timeout=6)
                resp2.raise_for_status()
                data2 = resp2.json()
                for sym in missing:
                    cg_id = symbol_to_id[sym]
                    price = data2.get(cg_id, {}).get('usd')
                    if price is not None:
                        prices[sym]['price_usd'] = float(price)
            except Exception:
                logging.exception('simple/price fallback failed')

        return {'data': prices}
    except Exception as e:
        # Log the original CoinGecko failure and attempt CoinCap as an alternative
        logging.exception('Failed to fetch market prices from CoinGecko: %s', e)
        try:
            logging.info('Attempting CoinCap as primary source after CoinGecko failure')
            cc_ids = ','.join(symbol_to_id.values())
            cc_url = 'https://api.coincap.io/v2/assets'
            cc_resp = requests.get(cc_url, params={'ids': cc_ids}, timeout=8)
            cc_resp.raise_for_status()
            cc_data = cc_resp.json()

            prices = {}
            for sym, cg_id in symbol_to_id.items():
                prices[sym] = {'symbol': sym, 'price_usd': None}

            for item in cc_data.get('data', []):
                cid = item.get('id')
                for sym, cg_id in symbol_to_id.items():
                    if cg_id == cid:
                        try:
                            prices[sym]['price_usd'] = float(item.get('priceUsd'))
                        except Exception:
                            prices[sym]['price_usd'] = None

            return {'data': prices}
        except Exception:
            logging.exception('CoinCap also failed, returning static fallback')
            prices = {
                'BTC': {'symbol': 'BTC', 'price_usd': 60000.0},
                'USDT': {'symbol': 'USDT', 'price_usd': 1.0},
                'ETH': {'symbol': 'ETH', 'price_usd': 3500.0},
                'TRX': {'symbol': 'TRX', 'price_usd': 0.08},
                'XRP': {'symbol': 'XRP', 'price_usd': 0.6},
                'BNB': {'symbol': 'BNB', 'price_usd': 400.0},
            }
            return {'data': prices, 'warning': 'fallback'}


if __name__ == '__main__':
    uvicorn.run('app:app', host='0.0.0.0', port=int(os.getenv('PORT', '8000')))
