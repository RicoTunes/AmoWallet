import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/theme/app_theme.dart';

// Provider for selected currency
final selectedCurrencyProvider = StateNotifierProvider<SelectedCurrencyNotifier, String>((ref) {
  return SelectedCurrencyNotifier();
});

class SelectedCurrencyNotifier extends StateNotifier<String> {
  SelectedCurrencyNotifier() : super('USD') {
    _loadCurrency();
  }

  Future<void> _loadCurrency() async {
    final prefs = await SharedPreferences.getInstance();
    state = prefs.getString('selected_currency') ?? 'USD';
  }

  Future<void> setCurrency(String currency) async {
    state = currency;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('selected_currency', currency);
  }
}

class CurrencySettingsPage extends ConsumerWidget {
  const CurrencySettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selectedCurrency = ref.watch(selectedCurrencyProvider);

    final currencies = [
      {'code': 'USD', 'name': 'US Dollar', 'symbol': '\$'},
      {'code': 'EUR', 'name': 'Euro', 'symbol': '€'},
      {'code': 'GBP', 'name': 'British Pound', 'symbol': '£'},
      {'code': 'JPY', 'name': 'Japanese Yen', 'symbol': '¥'},
      {'code': 'CNY', 'name': 'Chinese Yuan', 'symbol': '¥'},
      {'code': 'AUD', 'name': 'Australian Dollar', 'symbol': 'A\$'},
      {'code': 'CAD', 'name': 'Canadian Dollar', 'symbol': 'C\$'},
      {'code': 'CHF', 'name': 'Swiss Franc', 'symbol': 'Fr'},
      {'code': 'INR', 'name': 'Indian Rupee', 'symbol': '₹'},
      {'code': 'KRW', 'name': 'South Korean Won', 'symbol': '₩'},
      {'code': 'BRL', 'name': 'Brazilian Real', 'symbol': 'R\$'},
      {'code': 'RUB', 'name': 'Russian Ruble', 'symbol': '₽'},
      {'code': 'SGD', 'name': 'Singapore Dollar', 'symbol': 'S\$'},
      {'code': 'HKD', 'name': 'Hong Kong Dollar', 'symbol': 'HK\$'},
      {'code': 'AED', 'name': 'UAE Dirham', 'symbol': 'د.إ'},
    ];

    return Scaffold(
      appBar: AppBar(
        title: const Text('Currency'),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppConstants.defaultPadding),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Select Currency',
                style: AppTheme.titleLarge.copyWith(
                  color: Theme.of(context).colorScheme.onSurface,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Choose your preferred display currency',
                style: AppTheme.bodyMedium.copyWith(
                  color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
                ),
              ),
              const SizedBox(height: 24),
              Expanded(
                child: ListView.builder(
                  itemCount: currencies.length,
                  itemBuilder: (context, index) {
                    final currency = currencies[index];
                    final isSelected = selectedCurrency == currency['code'];

                    return Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      child: ListTile(
                        leading: Container(
                          width: 48,
                          height: 48,
                          decoration: BoxDecoration(
                            color: isSelected
                                ? Theme.of(context).colorScheme.primary.withOpacity(0.1)
                                : Theme.of(context).colorScheme.surfaceContainerHighest,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Center(
                            child: Text(
                              currency['symbol']!,
                              style: TextStyle(
                                fontSize: 24,
                                fontWeight: FontWeight.bold,
                                color: isSelected
                                    ? Theme.of(context).colorScheme.primary
                                    : Theme.of(context).colorScheme.onSurface.withOpacity(0.5),
                              ),
                            ),
                          ),
                        ),
                        title: Text(
                          currency['name']!,
                          style: AppTheme.titleMedium.copyWith(
                            color: Theme.of(context).colorScheme.onSurface,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        subtitle: Text(
                          currency['code']!,
                          style: AppTheme.bodySmall.copyWith(
                            color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
                          ),
                        ),
                        trailing: isSelected
                            ? Icon(
                                Icons.check_circle,
                                color: Theme.of(context).colorScheme.primary,
                              )
                            : null,
                        onTap: () {
                          ref.read(selectedCurrencyProvider.notifier).setCurrency(currency['code']!);
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('Currency changed to ${currency['code']}'),
                              duration: const Duration(seconds: 2),
                            ),
                          );
                        },
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
