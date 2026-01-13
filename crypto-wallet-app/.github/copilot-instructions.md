# Crypto Wallet App - AI Agent Instructions

## Architecture Overview
This is a multi-tier crypto wallet application with:
- Frontend: Flutter app for Windows
- Backend Services:
  - Node.js API (port 3000) - Primary backend service
  - Python FastAPI service (port 8000) - Handles crypto operations
  - Rust binary - Core cryptographic functions accessed via worker pools

### Key Data Flows
1. Flutter frontend → Python FastAPI service for direct crypto operations
2. Node.js backend → Python service → Rust worker pool for legacy support
3. All crypto operations use the Rust binary in worker mode for optimal performance

## Critical Workflows

### Development Setup
1. Start Python crypto service:
```powershell
cd backend/python-service
.\.venv\Scripts\python.exe -m uvicorn app:app --host 0.0.0.0 --port 8000
```

2. Run Flutter frontend:
```powershell
cd frontend
flutter run -d windows
```

### Testing
- Backend unit tests use Mocha + Supertest
- Python service has its own test suite
- Integration tests verify the full stack flow

## Project Conventions

### Rust Worker Pattern
The Rust crypto implementation uses a long-running worker mode:
- Reads JSON commands from stdin
- Writes JSON responses to stdout
- Managed by worker pools in both Python and Node.js

Example from `backend/python-service/worker_pool.py`:
```python
class RustWorkerPool:
    def __init__(self, pool_size=2):
        self.pool_size = pool_size
        self.workers = []  # Maintains worker processes
```

### API Patterns
- All crypto endpoints follow consistent structure:
  - /api/wallet/generate
  - /api/wallet/sign
  - /api/wallet/verify
- Standard response format includes status and data fields

## Integration Points

### Frontend-Backend Integration
- Flutter app uses HTTP client to call Python service directly
- Endpoints require proper CORS headers for Flutter web/desktop

### Python-Rust Integration
- Python service manages Rust worker processes
- Workers communicate via stdin/stdout JSON protocol
- Worker pool handles process lifecycle and load balancing

### Key Files
- `backend/rust/src/lib.rs` - Core crypto implementation
- `backend/python-service/app.py` - FastAPI service endpoints
- `frontend/lib/services/wallet_service.dart` - Flutter backend client

## Common Tasks
1. Adding new crypto operations:
   - Implement in Rust first
   - Add to Python service worker pool
   - Create corresponding API endpoint
   - Update Flutter client

2. Debugging:
   - Python service logs to stdout
   - Rust workers log to separate files
   - Flutter app includes DevTools support