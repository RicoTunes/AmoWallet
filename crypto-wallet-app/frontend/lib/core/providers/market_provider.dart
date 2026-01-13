import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../services/market_service.dart';

final marketServiceProvider = Provider((ref) => MarketService());

final marketPricesProvider = FutureProvider<Map<String, dynamic>>((ref) async {
  final svc = ref.read(marketServiceProvider);
  return await svc.fetchPrices();
});
