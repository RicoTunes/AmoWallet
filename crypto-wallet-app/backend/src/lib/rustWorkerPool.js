const { spawn } = require('child_process');
const { v4: uuidv4 } = require('uuid');
const os = require('os');

class RustWorker {
  constructor(binPath) {
    this.binPath = binPath;
    this.proc = spawn(this.binPath, ['worker'], { stdio: ['pipe', 'pipe', 'pipe'] });
    this.stdout = this.proc.stdout;
    this.stderr = this.proc.stderr;
    this.pending = new Map(); // id -> {resolve,reject}

    let leftover = '';
    this.stdout.on('data', (chunk) => {
      const s = leftover + chunk.toString('utf8');
      const lines = s.split('\n');
      leftover = lines.pop();
      for (const line of lines) {
        if (!line.trim()) continue;
        try {
          const obj = JSON.parse(line);
          const id = obj.id;
          const p = this.pending.get(id);
          if (p) {
            this.pending.delete(id);
            if (obj.ok) p.resolve(obj.result);
            else p.reject(new Error(obj.error || 'worker error'));
          }
        } catch (err) {
          // ignore malformed
        }
      }
    });

    this.stderr.on('data', (chunk) => {
      console.error('[rust-worker stderr]', chunk.toString('utf8'));
    });

    this.proc.on('exit', (code, signal) => {
      // reject all pending
      for (const [id, p] of this.pending.entries()) {
        p.reject(new Error(`worker exited: ${code || signal}`));
      }
      this.pending.clear();
    });
  }

  sendCommand(cmdObj) {
    return new Promise((resolve, reject) => {
      const id = cmdObj.id || uuidv4();
      cmdObj.id = id;
      this.pending.set(id, { resolve, reject });
      try {
        this.proc.stdin.write(JSON.stringify(cmdObj) + '\n');
      } catch (err) {
        this.pending.delete(id);
        reject(err);
      }
    });
  }

  kill() {
    try { this.proc.kill(); } catch (e) {}
  }
}

class RustWorkerPool {
  constructor(options = {}) {
    this.binPath = options.binPath || require('path').resolve(__dirname, '../../rust/target/release/crypto_wallet_cli');
    if (process.platform === 'win32' && !this.binPath.endsWith('.exe')) {
      this.binPath = this.binPath + '.exe';
    }
    this.size = options.size || Math.max(1, os.cpus().length - 1);
    this.workers = [];
    for (let i = 0; i < this.size; i++) {
      this.workers.push(new RustWorker(this.binPath));
    }
    this.next = 0;
  }

  _getWorker() {
    const w = this.workers[this.next % this.workers.length];
    this.next += 1;
    return w;
  }

  async generateKeypair() {
    const w = this._getWorker();
    const res = await w.sendCommand({ cmd: 'generate' });
    return res; // parsed object {privateKey, publicKey}
  }

  async signMessage(privateHex, message) {
    const w = this._getWorker();
    const res = await w.sendCommand({ cmd: 'sign', private: privateHex, message });
    return res; // signature hex
  }

  async verifySignature(publicHex, message, signatureHex) {
    const w = this._getWorker();
    const res = await w.sendCommand({ cmd: 'verify', public: publicHex, message, signature: signatureHex });
    return res; // boolean
  }

  shutdown() {
    for (const w of this.workers) w.kill();
  }
}

module.exports = RustWorkerPool;
