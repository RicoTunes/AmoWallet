import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/theme/app_theme.dart';

// Provider for selected network
final selectedNetworkProvider = StateNotifierProvider<SelectedNetworkNotifier, String>((ref) {
  return SelectedNetworkNotifier();
});

class SelectedNetworkNotifier extends StateNotifier<String> {
  SelectedNetworkNotifier() : super('Mainnet') {
    _loadNetwork();
  }

  Future<void> _loadNetwork() async {
    final prefs = await SharedPreferences.getInstance();
    state = prefs.getString('selected_network') ?? 'Mainnet';
  }

  Future<void> setNetwork(String network) async {
    state = network;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('selected_network', network);
  }
}

class NetworkSettingsPage extends ConsumerWidget {
  const NetworkSettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selectedNetwork = ref.watch(selectedNetworkProvider);

    final networks = [
      {
        'name': 'Mainnet',
        'description': 'Ethereum, Bitcoin, Solana mainnets',
        'icon': Icons.public,
      },
      {
        'name': 'Testnet',
        'description': 'Sepolia, Goerli, Devnet for testing',
        'icon': Icons.developer_mode,
      },
    ];

    return Scaffold(
      appBar: AppBar(
        title: const Text('Networks'),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppConstants.defaultPadding),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Select Network',
                style: AppTheme.titleLarge.copyWith(
                  color: Theme.of(context).colorScheme.onSurface,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Choose which blockchain network to connect to',
                style: AppTheme.bodyMedium.copyWith(
                  color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
                ),
              ),
              const SizedBox(height: 24),
              Expanded(
                child: ListView.builder(
                  itemCount: networks.length,
                  itemBuilder: (context, index) {
                    final network = networks[index];
                    final isSelected = selectedNetwork == network['name'];

                    return Card(
                      margin: const EdgeInsets.only(bottom: 12),
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
                          child: Icon(
                            network['icon'] as IconData,
                            color: isSelected
                                ? Theme.of(context).colorScheme.primary
                                : Theme.of(context).colorScheme.onSurface.withOpacity(0.5),
                          ),
                        ),
                        title: Text(
                          network['name'] as String,
                          style: AppTheme.titleMedium.copyWith(
                            color: Theme.of(context).colorScheme.onSurface,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        subtitle: Text(
                          network['description'] as String,
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
                          ref.read(selectedNetworkProvider.notifier).setNetwork(network['name'] as String);
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('Switched to ${network['name']}'),
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
