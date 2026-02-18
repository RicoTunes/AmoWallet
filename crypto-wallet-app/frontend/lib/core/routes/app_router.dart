import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../presentation/pages/onboarding/onboarding_page.dart';
import '../../presentation/pages/wallet/wallet_create_page.dart';
import '../../presentation/pages/wallet/wallet_import_page.dart';
import '../../presentation/pages/dashboard/dashboard_page.dart';
import '../../presentation/pages/dashboard/dashboard_page_enhanced.dart';
import '../../presentation/pages/dashboard/fake_dashboard_page.dart';
import '../../presentation/pages/portfolio/portfolio_page.dart';
import '../../presentation/pages/portfolio/coin_list_page.dart';
// import '../../presentation/pages/trading/spot_trading_page.dart';
import '../../presentation/pages/settings/settings_page.dart';
import '../../presentation/pages/settings/advanced_security_page.dart';
import '../../presentation/pages/wallet/receive_page.dart';
import '../../presentation/pages/wallet/receive_page_v2.dart';
import '../../presentation/pages/wallet/receive_page_enhanced.dart';
import '../../presentation/pages/wallet/send_page.dart';
import '../../presentation/pages/wallet/send_page_enhanced.dart';
import '../../presentation/pages/wallet/send_page_v2.dart';
import '../../presentation/pages/wallet/fake_send_page.dart';
import '../../presentation/pages/transactions/transactions_page.dart';
import '../../presentation/pages/transactions/transactions_page_enhanced.dart';
import '../../presentation/pages/swap/swap_page.dart';
import '../../presentation/pages/swap/swap_page_v2.dart';
import '../../presentation/pages/swap/swap_page_fast.dart';
import '../../presentation/pages/swap/swap_page_real.dart';
import '../../presentation/pages/multisig/create_multisig_page.dart';
import '../../presentation/pages/multisig/multisig_management_page.dart';
import '../../presentation/pages/multisig/multisig_wallet_page.dart';
import '../../presentation/pages/splash/splash_screen.dart';
import '../../presentation/pages/security/pin_setup_page.dart';
import '../../presentation/pages/security/pin_entry_page.dart';
import '../../presentation/pages/settings/address_book_page.dart';
import '../../presentation/pages/settings/notification_settings_page.dart';
import '../../presentation/widgets/animated_bottom_nav.dart';
import '../../presentation/widgets/modern_bottom_nav.dart';
import '../../presentation/widgets/price_chart_widget.dart';
import '../../presentation/pages/price_chart_page.dart';
import '../../services/auth_service.dart';
import '../../services/qr_scanner_service.dart';

final routerProvider = Provider<GoRouter>((ref) {
  final authService = AuthService();
  
  return GoRouter(
    initialLocation: '/splash',
    redirect: (context, state) async {
      final isLoggedIn = await authService.isLoggedIn();
      final isOnboarding = state.matchedLocation == '/onboarding';
      final isCreating = state.matchedLocation.startsWith('/wallet/create');
      final isImporting = state.matchedLocation.startsWith('/wallet/import');
      
      // If logged in and trying to access onboarding/wallet creation, redirect to dashboard
      if (isLoggedIn && (isOnboarding || isCreating || isImporting)) {
        return '/dashboard';
      }
      
      // If not logged in and trying to access protected routes, redirect to onboarding
      if (!isLoggedIn && !isOnboarding && !isCreating && !isImporting) {
        return '/onboarding';
      }
      
      return null; // No redirect needed
    },
    routes: [
      // Splash Screen
      GoRoute(
        path: '/splash',
        name: 'splash',
        builder: (context, state) => const SplashScreen(),
      ),
      
      // PIN Authentication
      GoRoute(
        path: '/pin-entry',
        name: 'pin_entry',
        builder: (context, state) => const PinEntryPage(),
      ),
      
      GoRoute(
        path: '/pin-setup',
        name: 'pin_setup',
        builder: (context, state) => const PinSetupPage(),
      ),

      // Root route redirects to splash
      GoRoute(
        path: '/',
        name: 'root',
        redirect: (context, state) => '/splash',
      ),

      // Onboarding Flow
      GoRoute(
        path: '/onboarding',
        name: 'onboarding',
        builder: (context, state) => const OnboardingPage(),
      ),

      // Wallet Creation
      GoRoute(
        path: '/wallet/create',
        name: 'wallet_create',
        builder: (context, state) => const WalletCreatePage(),
      ),

      // Wallet Import
      GoRoute(
        path: '/wallet/import',
        name: 'wallet_import',
        builder: (context, state) => const WalletImportPage(),
      ),

      // Main App Navigation
      ShellRoute(
        builder: (context, state, child) {
          return MainNavigationWrapper(child: child);
        },
        routes: [
          // Dashboard - Using Enhanced Version
          GoRoute(
            path: '/dashboard',
            name: 'dashboard',
            builder: (context, state) => const DashboardPageEnhanced(),
          ),

          // Portfolio
          GoRoute(
            path: '/portfolio',
            name: 'portfolio',
            builder: (context, state) => const PortfolioPage(),
          ),

          // Coin List
          GoRoute(
            path: '/coins',
            name: 'coins',
            builder: (context, state) => const CoinListPage(),
          ),

          // Trading - DISABLED
          // GoRoute(
          //   path: '/trading',
          //   name: 'trading',
          //   builder: (context, state) => const SpotTradingPage(),
          // ),

          // Settings
          GoRoute(
            path: '/settings',
            name: 'settings',
            builder: (context, state) => const SettingsPage(),
          ),
        ],
      ),
      
      // Standalone pages with proper back navigation
      GoRoute(
        path: '/receive',
        name: 'receive',
        builder: (context, state) {
          final extra = state.extra as Map<String, dynamic>?;
          return ReceivePageEnhanced(initialCoin: extra?['coin']);
        },
      ),
      GoRoute(
        path: '/send',
        name: 'send',
        builder: (context, state) {
          final extra = state.extra as Map<String, dynamic>?;
          return SendPageEnhanced(
            initialCoin: extra?['coin'],
            initialAddress: extra?['address'],
          );
        },
      ),
      GoRoute(
        path: '/transactions',
        name: 'transactions',
        builder: (context, state) => const TransactionsPageEnhanced(),
      ),
      GoRoute(
        path: '/swap',
        name: 'swap',
        builder: (context, state) {
          final extra = state.extra as Map<String, dynamic>?;
          return SwapPageReal(initialFromCoin: extra?['fromCoin']);
        },
      ),
      GoRoute(
        path: '/create-multisig',
        name: 'create_multisig',
        builder: (context, state) => const CreateMultiSigPage(),
      ),
      GoRoute(
        path: '/multisig-management',
        name: 'multisig_management',
        builder: (context, state) => const MultiSigManagementPage(),
      ),
      GoRoute(
        path: '/multisig',
        name: 'multisig',
        builder: (context, state) => const MultiSigWalletPage(),
      ),
      GoRoute(
        path: '/scanner',
        name: 'scanner',
        builder: (context, state) {
          final extra = state.extra as Map<String, dynamic>?;
          return QrScannerPage(expectedCoin: extra?['coin']);
        },
      ),
      GoRoute(
        path: '/address-book',
        name: 'address_book',
        builder: (context, state) {
          final extra = state.extra as Map<String, dynamic>?;
          return AddressBookPage(
            selectForCoin: extra?['selectForCoin'],
          );
        },
      ),
      GoRoute(
        path: '/notification-settings',
        name: 'notification_settings',
        builder: (context, state) => const NotificationSettingsPage(),
      ),
      GoRoute(
        path: '/advanced-security',
        name: 'advanced_security',
        builder: (context, state) => const AdvancedSecurityPage(),
      ),
      GoRoute(
        path: '/price-chart',
        name: 'price_chart',
        builder: (context, state) {
          final extra = state.extra as Map<String, dynamic>?;
          return PriceChartPage(
            coinSymbol: extra?['coin'] ?? 'BTC',
            coinName: extra?['name'] ?? 'Bitcoin',
            currentPrice: extra?['price'] ?? 0.0,
            priceChange24h: extra?['change'] ?? 0.0,
          );
        },
      ),
      
      // Fake Wallet Pages (Decoy for Duress PIN)
      GoRoute(
        path: '/fake-dashboard',
        name: 'fake_dashboard',
        builder: (context, state) => FakeDashboardPage(),
      ),
    ],

    // Error handling
    errorBuilder: (context, state) {
      return Scaffold(
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                '404',
                style: Theme.of(context).textTheme.headlineLarge,
              ),
              const SizedBox(height: 16),
              Text(
                'Page not found',
                style: Theme.of(context).textTheme.bodyLarge,
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: () => context.go('/dashboard'),
                child: const Text('Go to Dashboard'),
              ),
            ],
          ),
        ),
      );
    },
  );
});

class MainNavigationWrapper extends StatefulWidget {
  final Widget child;

  const MainNavigationWrapper({super.key, required this.child});

  @override
  State<MainNavigationWrapper> createState() => _MainNavigationWrapperState();
}

class _MainNavigationWrapperState extends State<MainNavigationWrapper> {
  DateTime? _lastBackPress;

  Future<bool> _onWillPop() async {
    final location = GoRouterState.of(context).uri.toString();
    
    // If not on dashboard, go to dashboard
    if (!location.startsWith('/dashboard')) {
      context.go('/dashboard');
      return false;
    }
    
    // On dashboard, double tap to exit
    final now = DateTime.now();
    if (_lastBackPress == null || now.difference(_lastBackPress!) > const Duration(seconds: 2)) {
      _lastBackPress = now;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Press back again to exit'),
          duration: Duration(seconds: 2),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return false;
    }
    
    // Exit the app
    SystemNavigator.pop();
    return true;
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        await _onWillPop();
      },
      child: Scaffold(
        backgroundColor: Colors.transparent,
        extendBody: true,
        extendBodyBehindAppBar: true,
        body: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Color(0xFF0D1421),
                Color(0xFF151C28),
              ],
            ),
          ),
          child: widget.child,
        ),
        bottomNavigationBar: ModernBottomNav(
          currentIndex: _getCurrentIndex(context),
          onTap: (index) => _onItemTapped(context, index),
          onCenterTap: () => _showQuickActions(context),
        ),
      ),
    );
  }

  int _getCurrentIndex(BuildContext context) {
    final location = GoRouterState.of(context).uri.toString();
    if (location.startsWith('/dashboard')) return 0;
    if (location.startsWith('/portfolio')) return 1;
    if (location.startsWith('/settings')) return 1;
    return 0;
  }

  void _onItemTapped(BuildContext context, int index) {
    switch (index) {
      case 0:
        context.go('/dashboard');
        break;
      case 1:
        context.go('/portfolio');
        break;
    }
  }

  void _showQuickActions(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        padding: const EdgeInsets.all(24),
        decoration: const BoxDecoration(
          color: Color(0xFF1A1F2E),
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(bottom: 24),
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const Text(
              'Quick Actions',
              style: TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _buildQuickAction(
                  context: context,
                  icon: Icons.download_rounded,
                  label: 'Receive',
                  color: const Color(0xFF10B981),
                  onTap: () {
                    Navigator.pop(ctx);
                    context.go('/receive');
                  },
                ),
                _buildQuickAction(
                  context: context,
                  icon: Icons.upload_rounded,
                  label: 'Send',
                  color: const Color(0xFFEF4444),
                  onTap: () {
                    Navigator.pop(ctx);
                    context.go('/send');
                  },
                ),
                _buildQuickAction(
                  context: context,
                  icon: Icons.swap_horiz_rounded,
                  label: 'Swap',
                  color: const Color(0xFF8B5CF6),
                  onTap: () {
                    Navigator.pop(ctx);
                    context.go('/swap');
                  },
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _buildQuickAction(
                  context: context,
                  icon: Icons.history_rounded,
                  label: 'History',
                  color: const Color(0xFF3B82F6),
                  onTap: () {
                    Navigator.pop(ctx);
                    context.go('/transactions');
                  },
                ),
                _buildQuickAction(
                  context: context,
                  icon: Icons.qr_code_scanner_rounded,
                  label: 'Scan',
                  color: const Color(0xFFF59E0B),
                  onTap: () async {
                    Navigator.pop(ctx);
                    // Open scanner and navigate to send with scanned address
                    final result = await Navigator.push<QrScanResult>(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const QrScannerPage(),
                      ),
                    );
                    if (result != null) {
                      context.go('/send', extra: {
                        'address': result.address,
                        'coin': result.coin,
                      });
                    }
                  },
                ),
                _buildQuickAction(
                  context: context,
                  icon: Icons.settings_rounded,
                  label: 'Settings',
                  color: const Color(0xFF6B7280),
                  onTap: () {
                    Navigator.pop(ctx);
                    context.go('/settings');
                  },
                ),
              ],
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  Widget _buildQuickAction({
    required BuildContext context,
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 60,
            height: 60,
            decoration: BoxDecoration(
              color: color.withOpacity(0.15),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: color.withOpacity(0.3),
                width: 1,
              ),
            ),
            child: Icon(icon, color: color, size: 28),
          ),
          const SizedBox(height: 8),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}
