const request = require('supertest');
const app = require('../../src/app');
const { expect } = require('chai');

describe('Wallet API', function() {
  this.timeout(10000);

  it('should generate a keypair, sign and verify', async () => {
    const genRes = await request(app)
      .post('/api/wallet/generate')
      .set('User-Agent', 'Mocha-Test-Agent/1.0')
      .send();
    expect(genRes.status).to.equal(200);
    expect(genRes.body).to.have.property('success').that.is.true;
    expect(genRes.body).to.have.property('wallet');
    expect(genRes.body.wallet).to.have.property('privateKey');
    expect(genRes.body.wallet).to.have.property('publicKey');

    const privateKey = genRes.body.wallet.privateKey;
    const publicKey = genRes.body.wallet.publicKey;

    const message = 'hello unit test';
    const signRes = await request(app)
      .post('/api/wallet/sign')
      .set('User-Agent', 'Mocha-Test-Agent/1.0')
      .send({ privateKey, message });
    expect(signRes.status).to.equal(200);
    expect(signRes.body).to.have.property('success').that.is.true;
    expect(signRes.body).to.have.property('signature');

    const verifyRes = await request(app)
      .post('/api/wallet/verify')
      .set('User-Agent', 'Mocha-Test-Agent/1.0')
      .send({ publicKey, message, signature: signRes.body.signature });
    expect(verifyRes.status).to.equal(200);
    expect(verifyRes.body).to.have.property('success').that.is.true;
    expect(verifyRes.body).to.have.property('isValid');
    expect(verifyRes.body.isValid).to.be.true;
  });
});
