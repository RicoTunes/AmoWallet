import 'package:flutter_test/flutter_test.dart';
import 'package:crypto_wallet_pro/services/bip39_wallet.dart';

void main() {
  test('Bip39Wallet generates ETH and BTC addresses', () async {
    final eth = await Bip39Wallet.generate(chain: 'ETH');
    expect(eth.containsKey('address'), true);
    expect(eth.containsKey('privateKey'), true);
    expect(eth.containsKey('mnemonic'), true);
    expect((eth['address'] as String).startsWith('0x'), true);

    final btc = await Bip39Wallet.generate(chain: 'BTC');
    expect(btc.containsKey('address'), true);
    expect(btc.containsKey('privateKey'), true);
    expect(btc.containsKey('mnemonic'), true);
    // BTC legacy addresses usually start with '1' for mainnet
    expect((btc['address'] as String).startsWith('1') || (btc['address'] as String).startsWith('3'), true);
  });
}
