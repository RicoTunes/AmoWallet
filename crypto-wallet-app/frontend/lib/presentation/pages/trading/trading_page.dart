import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/theme/app_theme.dart';

class TradingPage extends ConsumerWidget {
  const TradingPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return BackButtonListener(
      onBackButtonPressed: () async {
        context.go('/dashboard');
        return true;
      },
      child: PopScope(
      canPop: false,
      onPopInvoked: (didPop) {
        if (!didPop) {
          context.go('/dashboard');
        }
      },
      child: Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go('/dashboard'),
        ),
        title: const Text('Trading'),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppConstants.defaultPadding),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 16),
              Text(
                'Professional spot trading and instant swaps',
                style: AppTheme.bodyLarge.copyWith(
                  color: Theme.of(context).colorScheme.onSurface,
                ),
              ),
              const SizedBox(height: 32),
              
              // Trading Features Grid
              GridView.count(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                crossAxisCount: 2,
                crossAxisSpacing: 16,
                mainAxisSpacing: 16,
                childAspectRatio: 1.2,
                children: [
                  _buildTradingCard(
                    context,
                    icon: Icons.swap_horiz,
                    title: 'Instant Swap',
                    subtitle: 'Fast token exchange',
                    comingSoon: true,
                  ),
                  _buildTradingCard(
                    context,
                    icon: Icons.trending_up,
                    title: 'Spot Trading',
                    subtitle: 'Order book trading',
                    comingSoon: true,
                  ),
                  _buildTradingCard(
                    context,
                    icon: Icons.auto_graph,
                    title: 'Charts',
                    subtitle: 'Advanced analytics',
                    comingSoon: true,
                  ),
                  _buildTradingCard(
                    context,
                    icon: Icons.history,
                    title: 'Trade History',
                    subtitle: 'Past transactions',
                    comingSoon: true,
                  ),
                ],
              ),
              
              const Spacer(),
              
              // Coming Soon Notice
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surface,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: Theme.of(context).colorScheme.outline,
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.info_outline,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Trading features are coming soon. Stay tuned for updates!',
                        style: AppTheme.bodyMedium.copyWith(
                          color: Theme.of(context).colorScheme.onSurface,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    ),
    ),
    );
  }

  Widget _buildTradingCard(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String subtitle,
    bool comingSoon = false,
  }) {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primary.withAlpha((0.1 * 255).round()),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    icon,
                    color: Theme.of(context).colorScheme.primary,
                    size: 20,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  title,
                  style: AppTheme.titleSmall.copyWith(
                    color: Theme.of(context).colorScheme.onSurface,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: AppTheme.bodySmall.copyWith(
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                ),
              ],
            ),
            if (comingSoon)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.secondary.withAlpha((0.1 * 255).round()),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  'Coming Soon',
                  style: AppTheme.labelSmall.copyWith(
                    color: Theme.of(context).colorScheme.secondary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}