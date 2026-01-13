import subprocess
import threading
import json
import uuid
import os
from queue import Queue, Empty


class RustWorker:
    def __init__(self, bin_path):
        self.bin_path = bin_path
        self.proc = subprocess.Popen([self.bin_path, 'worker'], stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        self.lock = threading.Lock()
        self.responses = {}
        self.stdout_thread = threading.Thread(target=self._read_stdout, daemon=True)
        self.stdout_thread.start()

    def _read_stdout(self):
        for line in self.proc.stdout:
            line = line.strip()
            if not line:
                continue
            try:
                obj = json.loads(line)
                rid = obj.get('id')
                if rid and rid in self.responses:
                    self.responses[rid].put(obj)
            except Exception as e:
                # ignore malformed
                continue

    def send(self, cmd_obj, timeout=10):
        rid = cmd_obj.get('id') or str(uuid.uuid4())
        cmd_obj['id'] = rid
        q = Queue()
        self.responses[rid] = q
        with self.lock:
            self.proc.stdin.write(json.dumps(cmd_obj) + '\n')
            self.proc.stdin.flush()
        try:
            resp = q.get(timeout=timeout)
            return resp
        finally:
            del self.responses[rid]

    def terminate(self):
        try:
            self.proc.terminate()
        except Exception:
            pass


class RustWorkerPool:
    def __init__(self, bin_path=None, size=2):
        if bin_path is None:
            base = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', 'rust', 'target', 'release'))
            exe = 'crypto_wallet_cli.exe' if os.name == 'nt' else 'crypto_wallet_cli'
            bin_path = os.path.join(base, exe)
        self.bin_path = bin_path
        self.workers = [RustWorker(self.bin_path) for _ in range(size)]
        self._idx = 0

    def _get_worker(self):
        w = self.workers[self._idx % len(self.workers)]
        self._idx += 1
        return w

    def generate_keypair(self):
        w = self._get_worker()
        resp = w.send({'cmd': 'generate'})
        return resp

    def generate_keypair_for(self, chain: str | None = None):
        w = self._get_worker()
        cmd = {'cmd': 'generate'}
        if chain:
            # pass chain symbol to worker; worker may ignore if not supported
            cmd['chain'] = chain
        resp = w.send(cmd)
        return resp

    def sign_message(self, private_hex, message):
        w = self._get_worker()
        resp = w.send({'cmd': 'sign', 'private': private_hex, 'message': message})
        return resp

    def verify_signature(self, public_hex, message, signature_hex):
        w = self._get_worker()
        resp = w.send({'cmd': 'verify', 'public': public_hex, 'message': message, 'signature': signature_hex})
        return resp

    def shutdown(self):
        for w in self.workers:
            w.terminate()
