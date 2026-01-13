import 'package:flutter_test/flutter_test.dart';
import 'package:crypto_wallet_pro/services/wallet_service.dart';

class _InMemoryStorage {
  final Map<String, String> _m = {};
  Future<void> write({required String key, required String? value}) async {
    if (value == null) {
      _m.remove(key);
    } else {
      _m[key] = value;
    }
  }

  Future<String?> read({required String key}) async => _m[key];
  Future<void> delete({required String key}) async => _m.remove(key);
  Future<Map<String, String>> readAll() async => Map.from(_m);
}

void main() {
  test('WalletService PIN set/verify and audit', () async {
  final storage = _InMemoryStorage();
  final svc = WalletService(storage: storage);

    await svc.deletePin();
    expect(await svc.hasPin(), false);

    await svc.setPin('123456');
    expect(await svc.hasPin(), true);
    expect(await svc.verifyPin('123456'), true);
    expect(await svc.verifyPin('000000'), false);

    await svc.recordRevealEvent('ETH', '0xabc', true);
    await svc.recordRevealEvent('BTC', '1xyz', false);
    final audit = await svc.getRevealAudit();
    expect(audit.length, 2);
    expect(audit[0]['chain'], 'ETH');
    expect(audit[1]['chain'], 'BTC');
  });
}
