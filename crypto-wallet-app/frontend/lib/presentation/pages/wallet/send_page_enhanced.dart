import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:confetti/confetti.dart';
import 'dart:math';

import '../../../core/providers/fake_wallet_provider.dart';
import '../../../services/wallet_service.dart';
import '../../../services/transaction_service.dart';
import '../../../services/blockchain_service.dart';
import '../../../services/pin_auth_service.dart';
import '../../../services/notification_service.dart';
import '../../../services/confirmation_tracker_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import '../../../services/qr_scanner_service.dart';
import '../../../services/price_service.dart';
import '../wallet/fake_send_page.dart';

class SendPageEnhanced extends ConsumerStatefulWidget {
  const SendPageEnhanced({super.key, this.initialCoin, this.initialAddress});

  final String? initialCoin;
  final String? initialAddress;

  @override
  ConsumerState<SendPageEnhanced> createState() => _SendPageEnhancedState();
}

class _SendPageEnhancedState extends ConsumerState<SendPageEnhanced>
    with TickerProviderStateMixin {
  final WalletService _walletService = WalletService();
  final TransactionService _transactionService = TransactionService();
  final BlockchainService _blockchainService = BlockchainService();
  final PinAuthService _pinAuthService = PinAuthService();
  final NotificationService _notificationService = NotificationService();
  final ConfirmationTrackerService _confirmationTracker =
      ConfirmationTrackerService();

  final TextEditingController _amountController = TextEditingController();
  final TextEditingController _addressController = TextEditingController();
  final TextEditingController _memoController = TextEditingController();

  // Confetti controller
  late ConfettiController _confettiController;

  // Animation controllers
  late AnimationController _colorAnimationController;
  late Animation<Color?> _headerColorAnimation;
  late AnimationController _slideAnimationController;

  // PIN Entry state
  String _enteredPin = '';
  bool _showPinEntry = false;
  bool _showSlideToSend = false;

  // Slide to send
  double _slidePosition = 0.0;
  bool _isSliding = false;

  String _selectedCoin = 'BTC';
  String? _myAddress;
  bool _loading = false;
  bool _balanceLoaded = false;
  double _availableBalance = 0.0;
  double _fee = 0.0;
  Map<String, double> _cachedBalances = {};
  Map<String, double> _cachedFees = {};
  double _currentCryptoPrice = 0.0;
  Map<String, double> _cachedPrices = {};
  bool _useUsdInput = false;
  double? _selectedPercent;

  Color _currentHeaderColor = const Color(0xFFF7931A); // BTC Orange

  // Coin data with colors
  final List<CoinData> _coins = [
    CoinData('BTC', 'Bitcoin', const Color(0xFFF7931A), Icons.currency_bitcoin),
    CoinData('ETH', 'Ethereum', const Color(0xFF627EEA), Icons.diamond),
    CoinData('BNB', 'BNB Chain', const Color(0xFFF0B90B), Icons.hexagon),
    CoinData('USDT-BEP20', 'USDT BEP20', const Color(0xFF26A17B),
        Icons.attach_money),
    CoinData('USDT-ERC20', 'USDT ERC20', const Color(0xFF26A17B),
        Icons.attach_money),
    CoinData('SOL', 'Solana', const Color(0xFF9945FF), Icons.flash_on),
    CoinData('XRP', 'Ripple', const Color(0xFF23292F), Icons.water_drop),
    CoinData('TRX', 'Tron', const Color(0xFFEB0029), Icons.bolt),
    CoinData(
        'LTC', 'Litecoin', const Color(0xFFBFBBBB), Icons.currency_exchange),
    CoinData('DOGE', 'Dogecoin', const Color(0xFFC2A633), Icons.pets),
  ];

  @override
  void initState() {
    super.initState();
    _selectedCoin = widget.initialCoin ?? 'BTC';
    _addressController.text = widget.initialAddress ?? '';
    _currentHeaderColor = _getCoinColor(_selectedCoin);

    _confettiController =
        ConfettiController(duration: const Duration(seconds: 3));

    _colorAnimationController = AnimationController(
      duration: const Duration(milliseconds: 500),
      vsync: this,
    );

    _slideAnimationController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );

    _headerColorAnimation = ColorTween(
      begin: _currentHeaderColor,
      end: _currentHeaderColor,
    ).animate(CurvedAnimation(
      parent: _colorAnimationController,
      curve: Curves.easeInOut,
    ));

    // Load current coin balance - single getBalances() call caches ALL coins at once
    _loadAllBalancesOnce();
  }

  /// Load ALL coin balances — first show cached values instantly, then
  /// refresh from the network in background. Uses the same SharedPreferences
  /// cache that the dashboard writes to.
  Future<void> _loadAllBalancesOnce() async {
    // ── Step 1: Show cached balances immediately ──────────────────────────
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString('dashboard_cached_balances');
      if (raw != null && raw.isNotEmpty) {
        final Map<String, dynamic> decoded = jsonDecode(raw);
        final cached = decoded.map((k, v) => MapEntry(k, (v as num).toDouble()));
        if (cached.isNotEmpty) {
          for (final coin in _coins) {
            final b = cached[coin.symbol];
            if (b != null) _cachedBalances[coin.symbol] = b;
          }
          if (mounted) {
            setState(() {
              _availableBalance = _cachedBalances[_selectedCoin] ?? 0.0;
              _balanceLoaded = true;
            });
          }
          debugPrint('⚡ Send page: showing ${cached.length} cached balances instantly');
        }
      }
    } catch (e) {
      debugPrint('⚠️ Send page cache read error: $e');
    }

    // ── Step 2: Refresh from network in background ─────────────────────────
    try {
      final allBalances = await _walletService.getBalances().timeout(
        const Duration(seconds: 20),
        onTimeout: () {
          debugPrint('⏱️ Send page balance fetch timeout - keeping cached values');
          return <String, double>{};
        },
      );
      if (allBalances.isNotEmpty) {
        debugPrint('📊 Send page live balances: $allBalances');
        for (final coin in _coins) {
          final balance = allBalances[coin.symbol];
          if (balance != null) _cachedBalances[coin.symbol] = balance;
        }
        // Persist updated balances for next open
        try {
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString('dashboard_cached_balances', jsonEncode(_cachedBalances));
        } catch (_) {}
      }
      // Also populate fees for all coins
      for (final coin in _coins) {
        if (!_cachedFees.containsKey(coin.symbol)) {
          _cachedFees[coin.symbol] = _getDefaultFee(coin.symbol);
        }
      }
      // Load my sending address for the current coin
      try {
        final addresses = await _walletService.getStoredAddresses(_selectedCoin);
        if (addresses.isNotEmpty && mounted) {
          setState(() => _myAddress = addresses.first);
        }
      } catch (e) {
        debugPrint('⚠️ Could not load address: $e');
      }
      // Update displayed balance with fresh value
      if (mounted) {
        setState(() {
          _availableBalance = _cachedBalances[_selectedCoin] ?? 0.0;
          _balanceLoaded = true;
        });
      }
    } catch (e) {
      debugPrint('❌ Error loading live balances: $e');
      if (mounted && !_balanceLoaded) {
        setState(() {
          _availableBalance = _cachedBalances[_selectedCoin] ?? 0.0;
          _balanceLoaded = true;
        });
      }
    }
    // Fees and price in background
    _loadCryptoPrice();
    _calculateAndCacheRealFee();
  }

  Future<void> _calculateAndCacheRealFee() async {
    try {
      final fee = await _calculateRealFee();
      if (mounted) {
        setState(() {
          _fee = fee;
          _cachedFees[_selectedCoin] = fee;
        });
      }
    } catch (_) {}
  }

  /// Get default fee for a coin
  double _getDefaultFee(String coin) {
    switch (coin) {
      case 'BTC':
        return 0.00005;
      case 'ETH':
        return 0.00042; // ~21000 gas × 20 gwei
      case 'BNB':
        return 0.00021;
      case 'USDT-ERC20':
        return 0.001;
      case 'USDT-BEP20':
        return 0.0002;
      default:
        return 0.0005;
    }
  }

  @override
  void dispose() {
    _confettiController.dispose();
    _colorAnimationController.dispose();
    _slideAnimationController.dispose();
    _amountController.dispose();
    _addressController.dispose();
    _memoController.dispose();
    super.dispose();
  }

  Color _getCoinColor(String coin) {
    return _coins
        .firstWhere(
          (c) => c.symbol == coin,
          orElse: () => _coins.first,
        )
        .color;
  }

  void _animateToColor(Color newColor) {
    _headerColorAnimation = ColorTween(
      begin: _currentHeaderColor,
      end: newColor,
    ).animate(CurvedAnimation(
      parent: _colorAnimationController,
      curve: Curves.easeInOut,
    ));
    _colorAnimationController.forward(from: 0).then((_) {
      setState(() {
        _currentHeaderColor = newColor;
      });
    });
  }

  void _onCoinSelected(String coin) {
    if (coin != _selectedCoin) {
      setState(() {
        _selectedCoin = coin;
        _balanceLoaded = false;
        _myAddress = null; // reset — will be reloaded for new coin
      });
      _animateToColor(_getCoinColor(coin));
      _loadBalance();
      _loadCryptoPrice();
      // Refresh sending address for the newly selected coin
      _walletService.getStoredAddresses(coin).then((addresses) {
        if (addresses.isNotEmpty && mounted) {
          setState(() => _myAddress = addresses.first);
        }
      });
    }
  }

  Future<void> _loadBalance({bool forceRefresh = false}) async {
    if (!forceRefresh && _cachedBalances.containsKey(_selectedCoin)) {
      setState(() {
        _availableBalance = _cachedBalances[_selectedCoin]!;
        _fee = _cachedFees[_selectedCoin]!;
        _balanceLoaded = true;
      });
      return;
    }

    try {
      // Use wallet service to get all balances consistently with dashboard
      final allBalances = await _walletService.getBalances();
      final balance = allBalances[_selectedCoin] ?? 0.0;
      final fee = await _calculateRealFee();

      setState(() {
        _availableBalance = balance;
        _fee = fee;
        _cachedBalances[_selectedCoin] = balance;
        _cachedFees[_selectedCoin] = fee;
        _balanceLoaded = true;
      });
      
      debugPrint('📊 Send page loaded balance for $_selectedCoin: $balance');
    } catch (e) {
      debugPrint('❌ Error loading balance: $e');
      final fee = await _calculateRealFee();
      setState(() {
        _availableBalance = 0.0;
        _fee = fee;
        _cachedBalances[_selectedCoin] = 0.0;
        _cachedFees[_selectedCoin] = fee;
        _balanceLoaded = true;
      });
    }
  }

  Future<double> _calculateRealFee() async {
    try {
      return await _blockchainService.getFeeEstimate(_selectedCoin);
    } catch (e) {
      return _getDefaultFee(_selectedCoin);
    }
  }

  void _loadCryptoPrice() {
    if (_cachedPrices.containsKey(_selectedCoin)) {
      setState(() {
        _currentCryptoPrice = _cachedPrices[_selectedCoin]!;
      });
      return;
    }

    // Fallback prices (used until live price arrives)
    final fallback = {
      'BTC': 96000.0,
      'ETH': 3600.0,
      'BNB': 625.0,
      'TRX': 0.25,
      'XRP': 2.45,
      'SOL': 235.0,
      'LTC': 102.0,
      'DOGE': 0.40,
      'USDT-ERC20': 1.0,
      'USDT-BEP20': 1.0,
    };

    // Set fallback immediately so UI isn't blank
    setState(() {
      _currentCryptoPrice = fallback[_selectedCoin] ?? 0.0;
      _cachedPrices[_selectedCoin] = _currentCryptoPrice;
    });

    // Fetch live price and update
    final coinSymbol = _selectedCoin.contains('-') ? _selectedCoin.split('-')[0] : _selectedCoin;
    PriceService().getPrices([coinSymbol]).then((prices) {
      final livePrice = (prices[coinSymbol]?['price'] as num?)?.toDouble();
      if (livePrice != null && livePrice > 0 && mounted) {
        setState(() {
          _currentCryptoPrice = livePrice;
          _cachedPrices[_selectedCoin] = livePrice;
        });
      }
    }).catchError((_) {
      // Keep fallback on error
    });
  }

  double _getActualCryptoAmount() {
    final inputAmount = double.tryParse(_amountController.text) ?? 0.0;
    if (_useUsdInput && _currentCryptoPrice > 0) {
      return inputAmount / _currentCryptoPrice;
    }
    return inputAmount;
  }

  bool get _isFormValid {
    final inputAmount = double.tryParse(_amountController.text) ?? 0;
    final cryptoAmount = _getActualCryptoAmount();
    final address = _addressController.text.trim();
    return inputAmount > 0 &&
        cryptoAmount > 0 &&
        (cryptoAmount + _fee) <= _availableBalance &&
        address.isNotEmpty &&
        _validateAddressFormat(address);
  }

  bool _validateAddressFormat(String address) {
    switch (_selectedCoin) {
      case 'BTC':
        return address.startsWith('1') ||
            address.startsWith('3') ||
            address.startsWith('bc1');
      case 'ETH':
      case 'BNB':
      case 'USDT-ERC20':
      case 'USDT-BEP20':
        return address.startsWith('0x') && address.length == 42;
      case 'TRX':
        return address.startsWith('T') && address.length == 34;
      case 'XRP':
        return address.startsWith('r') &&
            address.length >= 25 &&
            address.length <= 35;
      case 'SOL':
        return address.length >= 32 && address.length <= 44;
      case 'LTC':
        return address.startsWith('L') ||
            address.startsWith('M') ||
            address.startsWith('ltc1');
      case 'DOGE':
        return address.startsWith('D') || address.startsWith('A');
      default:
        return address.length >= 26 && address.length <= 64;
    }
  }

  Future<void> _onContinuePressed() async {
    if (!_isFormValid) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please fill in all fields correctly'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    // Check if PIN is set - REQUIRED for transactions
    final pinIsSet = await _pinAuthService.isPinSet();
    
    if (!pinIsSet) {
      // PIN not set - show dialog to set PIN first
      if (mounted) {
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (context) => AlertDialog(
            title: const Text('Security Required'),
            content: const Text(
              'You must set up a PIN to send transactions. This adds an extra layer of security to your wallet.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: () {
                  Navigator.pop(context);
                  // Navigate to settings to set PIN
                  if (mounted) {
                    Navigator.pushNamed(context, '/settings/security');
                  }
                },
                child: const Text('Set PIN Now'),
              ),
            ],
          ),
        );
      }
      return;
    }

    // PIN is set - show PIN entry
    setState(() {
      _showPinEntry = true;
      _enteredPin = '';
      _showSlideToSend = false;
    });
  }

  void _onPinDigitPressed(String digit) {
    if (_enteredPin.length < 6) {
      setState(() {
        _enteredPin += digit;
      });

      if (_enteredPin.length == 6) {
        _verifyPin();
      }
    }
  }

  void _onPinBackspace() {
    if (_enteredPin.isNotEmpty) {
      setState(() {
        _enteredPin = _enteredPin.substring(0, _enteredPin.length - 1);
      });
    }
  }

  Future<void> _verifyPin() async {
    final isValid = await _pinAuthService.verifyPin(_enteredPin, ref: ref);

    if (isValid) {
      HapticFeedback.mediumImpact();
      setState(() {
        _showSlideToSend = true;
      });
    } else {
      // Check if fake wallet was activated (duress PIN)
      final fakeWalletState = ref.read(fakeWalletProvider);
      if (fakeWalletState.isActive && fakeWalletState.isDuressMode) {
        debugPrint('🎭 Fake wallet activated - showing decoy send page');
        HapticFeedback.mediumImpact();
        
        // Navigate to fake send page
        if (mounted) {
          Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const FakeSendPage()),
          );
        }
      } else {
        // Regular invalid PIN
        HapticFeedback.heavyImpact();
        setState(() {
          _enteredPin = '';
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Invalid PIN. Please try again.'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _onSlideUpdate(double position) {
    setState(() {
      _slidePosition = position.clamp(0.0, 1.0);
    });
  }

  void _onSlideComplete() {
    if (_slidePosition >= 0.85) {
      HapticFeedback.heavyImpact();
      _executeSend();
    } else {
      setState(() {
        _slidePosition = 0.0;
      });
    }
  }

  Future<void> _executeSend() async {
    setState(() => _loading = true);

    try {
      final cryptoAmount = _getActualCryptoAmount();
      final address = _addressController.text.trim();
      final memo = _memoController.text.trim();

      // Validate address
      final isAddressValid =
          await _blockchainService.validateAddress(_selectedCoin, address);
      if (!isAddressValid) {
        throw Exception('Invalid address for $_selectedCoin');
      }

      // Send transaction
      // If address still not loaded, attempt one more fetch
      if (_myAddress == null) {
        final addresses = await _walletService.getStoredAddresses(_selectedCoin);
        if (addresses.isNotEmpty) {
          _myAddress = addresses.first;
        } else {
          throw Exception('Could not determine your $_selectedCoin address. Please restart the app.');
        }
      }

      final txHash = await _blockchainService.sendTransaction(
        coin: _selectedCoin,
        fromAddress: _myAddress!,
        toAddress: address,
        amount: cryptoAmount,
        fee: _fee,
        memo: memo.isNotEmpty ? memo : null,
      );

      // Update balance optimistically
      final optimisticDeduction = cryptoAmount + _fee;
      setState(() {
        _availableBalance = (_availableBalance - optimisticDeduction);
        _cachedBalances[_selectedCoin] = _availableBalance;
      });

      // Record transaction
      await _transactionService.recordSentTransaction(
        coin: _selectedCoin,
        amount: cryptoAmount,
        toAddress: address,
        fromAddress: _myAddress,
        fee: _fee,
        memo: memo.isNotEmpty ? memo : null,
        txHash: txHash,
      );

      // Track confirmations
      await _confirmationTracker.trackTransaction(
        txHash: txHash,
        chain: _selectedCoin,
        coin: _selectedCoin,
        amount: cryptoAmount,
        type: 'send',
      );

      // Show outgoing notification in notification centre (pending → confirmed as tracking updates)
      await _notificationService.showOutgoingTransaction(
        amount: cryptoAmount.toStringAsFixed(8).replaceAll(RegExp(r'0+$'), '').replaceAll(RegExp(r'\.$'), ''),
        currency: _selectedCoin,
        to: address,
        txHash: txHash,
      );

      // Show success with confetti!
      _confettiController.play();

      if (mounted) {
        setState(() {
          _loading = false;
        });

        // Show success dialog
        await showDialog(
          context: context,
          barrierDismissible: false,
          builder: (context) => _buildSuccessDialog(txHash, cryptoAmount),
        );

        // Navigate back
        if (mounted) {
          context.go('/dashboard');
        }
      }
    } catch (e) {
      await _notificationService.showNotification(
        title: 'Transaction Failed',
        message: 'Failed to send $_selectedCoin: ${e.toString()}',
        type: NotificationType.failed,
        data: {'type': 'failed', 'coin': _selectedCoin, 'error': e.toString()},
      );

      if (mounted) {
        setState(() {
          _loading = false;
          _slidePosition = 0.0;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Widget _buildSuccessDialog(String txHash, double amount) {
    return Dialog(
      backgroundColor: Colors.transparent,
      child: Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: Colors.green.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.check_circle,
                color: Colors.green,
                size: 50,
              ),
            ),
            const SizedBox(height: 24),
            const Text(
              'Transaction Sent!',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '${amount.toStringAsFixed(8)} $_selectedCoin',
              style: TextStyle(
                fontSize: 18,
                color: _currentHeaderColor,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.grey[100],
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                children: [
                  const Text(
                    'Transaction Hash',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${txHash.substring(0, 16)}...${txHash.substring(txHash.length - 8)}',
                    style: const TextStyle(
                      fontSize: 14,
                      fontFamily: 'monospace',
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () => Navigator.of(context).pop(),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _currentHeaderColor,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: const Text(
                  'Done',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Stack(
      children: [
        AnimatedBuilder(
          animation: _colorAnimationController,
          builder: (context, child) {
            final color = _headerColorAnimation.value ?? _currentHeaderColor;
            return Scaffold(
              backgroundColor:
                  isDark ? const Color(0xFF0D1421) : Colors.grey[100],
              body: _showPinEntry
                  ? _buildPinEntryPage(color)
                  : _buildMainPage(color),
            );
          },
        ),
        // Confetti overlay
        Align(
          alignment: Alignment.topCenter,
          child: ConfettiWidget(
            confettiController: _confettiController,
            blastDirection: pi / 2,
            maxBlastForce: 5,
            minBlastForce: 2,
            emissionFrequency: 0.05,
            numberOfParticles: 50,
            gravity: 0.1,
            shouldLoop: false,
            colors: [
              _currentHeaderColor,
              Colors.green,
              Colors.blue,
              Colors.yellow,
              Colors.pink,
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildMainPage(Color headerColor) {
    return CustomScrollView(
      physics: const BouncingScrollPhysics(),
      slivers: [
        // Animated Header with balance
        SliverAppBar(
          expandedHeight: 100,
          floating: false,
          pinned: true,
          backgroundColor: headerColor,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back, color: Colors.white),
            onPressed: () => context.go('/dashboard'),
          ),
          title: const Text(
            'Send',
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 22,
            ),
          ),
          actions: [
            // Balance in header - same color as nav
            Center(
              child: Container(
                margin: const EdgeInsets.only(right: 12),
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: headerColor.withOpacity(0.3),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: _balanceLoaded
                    ? Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            '${_availableBalance.toStringAsFixed(6)} ${_selectedCoin.split('-').first}',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          if (_currentCryptoPrice > 0) ...[
                            const SizedBox(width: 4),
                            Text(
                              '(\$${(_availableBalance * _currentCryptoPrice).toStringAsFixed(2)})',
                              style: TextStyle(
                                color: Colors.white.withOpacity(0.7),
                                fontSize: 10,
                              ),
                            ),
                          ],
                        ],
                      )
                    : const SizedBox(
                        width: 60,
                        height: 12,
                        child: LinearProgressIndicator(
                          backgroundColor: Colors.white24,
                          valueColor: AlwaysStoppedAnimation(Colors.white),
                        ),
                      ),
              ),
            ),
          ],
          flexibleSpace: FlexibleSpaceBar(
            background: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    headerColor,
                    headerColor.withOpacity(0.85),
                  ],
                ),
              ),
            ),
          ),
        ),

        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Coin Selection Cards - Round circles
                Builder(
                  builder: (context) {
                    final isDark =
                        Theme.of(context).brightness == Brightness.dark;
                    return Text(
                      'Select Coin',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: isDark ? Colors.white : Colors.black87,
                      ),
                    );
                  },
                ),
                const SizedBox(height: 12),
                SizedBox(
                  height: 100,
                  child: ListView.builder(
                    scrollDirection: Axis.horizontal,
                    physics: const BouncingScrollPhysics(),
                    itemCount: _coins.length,
                    itemBuilder: (context, index) {
                      final coin = _coins[index];
                      final isSelected = coin.symbol == _selectedCoin;
                      final isDark =
                          Theme.of(context).brightness == Brightness.dark;
                      return GestureDetector(
                        onTap: () => _onCoinSelected(coin.symbol),
                        child: Container(
                          width: 80,
                          margin: const EdgeInsets.only(right: 12),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              AnimatedScale(
                                scale: isSelected ? 1.15 : 1.0,
                                duration: const Duration(milliseconds: 300),
                                curve: Curves.easeOutBack,
                                child: AnimatedContainer(
                                  duration: const Duration(milliseconds: 300),
                                  width: 60,
                                  height: 60,
                                  decoration: BoxDecoration(
                                    color: isSelected
                                        ? coin.color
                                        : (isDark
                                            ? const Color(0xFF1E2530)
                                            : Colors.white),
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: isSelected
                                          ? coin.color
                                          : (isDark
                                              ? Colors.white24
                                              : Colors.grey[300]!),
                                      width: isSelected ? 3 : 2,
                                    ),
                                    boxShadow: isSelected
                                        ? [
                                            BoxShadow(
                                              color:
                                                  coin.color.withOpacity(0.5),
                                              blurRadius: 15,
                                              offset: const Offset(0, 5),
                                            ),
                                          ]
                                        : [
                                            BoxShadow(
                                              color:
                                                  Colors.grey.withOpacity(0.2),
                                              blurRadius: 5,
                                              offset: const Offset(0, 2),
                                            ),
                                          ],
                                  ),
                                  child: Center(
                                    child: Icon(
                                      coin.icon,
                                      color: isSelected
                                          ? Colors.white
                                          : coin.color,
                                      size: 28,
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                coin.symbol.split('-').first,
                                style: TextStyle(
                                  color: isSelected
                                      ? coin.color
                                      : (isDark
                                          ? Colors.white70
                                          : Colors.grey[600]),
                                  fontWeight: isSelected
                                      ? FontWeight.bold
                                      : FontWeight.w500,
                                  fontSize: 11,
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),

                const SizedBox(height: 20),

                // Amount Input
                _buildAmountInput(),

                const SizedBox(height: 16),

                // Address Input
                _buildAddressInput(),

                const SizedBox(height: 16),

                // Memo Input (optional)
                _buildMemoInput(),

                const SizedBox(height: 16),

                // Fee Info
                Builder(
                  builder: (context) {
                    final isDark =
                        Theme.of(context).brightness == Brightness.dark;
                    return Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: isDark ? const Color(0xFF1E2530) : Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        border:
                            isDark ? Border.all(color: Colors.white10) : null,
                        boxShadow: isDark
                            ? null
                            : [
                                BoxShadow(
                                  color: Colors.grey.withOpacity(0.1),
                                  blurRadius: 10,
                                  offset: const Offset(0, 4),
                                ),
                              ],
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              Icon(Icons.local_gas_station,
                                  color: isDark
                                      ? Colors.white54
                                      : Colors.grey[500],
                                  size: 20),
                              const SizedBox(width: 8),
                              Text(
                                'Network Fee',
                                style: TextStyle(
                                    color:
                                        isDark ? Colors.white54 : Colors.grey),
                              ),
                            ],
                          ),
                          Text(
                            '${_fee.toStringAsFixed(8)} ${_selectedCoin.split('-').first}',
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              color: _currentHeaderColor,
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),

                const SizedBox(height: 24),

                // Slide to Send Button
                _buildSlideToSendButton(_currentHeaderColor),

                const SizedBox(height: 32),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildAmountInput() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E2530) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: isDark ? Border.all(color: Colors.white10) : null,
        boxShadow: isDark
            ? null
            : [
                BoxShadow(
                  color: Colors.grey.withOpacity(0.1),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Amount',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: isDark ? Colors.white : Colors.black87,
                ),
              ),
              Row(
                children: [
                  // Toggle USD/Crypto
                  Container(
                    decoration: BoxDecoration(
                      color: isDark ? Colors.white10 : Colors.grey[200],
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      children: [
                        GestureDetector(
                          onTap: () {
                            setState(() {
                              _useUsdInput = false;
                              _amountController.clear();
                            });
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: !_useUsdInput
                                  ? _currentHeaderColor
                                  : Colors.transparent,
                              borderRadius: BorderRadius.circular(15),
                            ),
                            child: Text(
                              _selectedCoin.split('-').first,
                              style: TextStyle(
                                color: !_useUsdInput
                                    ? Colors.white
                                    : (isDark
                                        ? Colors.white70
                                        : Colors.black87),
                                fontWeight: FontWeight.w600,
                                fontSize: 12,
                              ),
                            ),
                          ),
                        ),
                        GestureDetector(
                          onTap: () {
                            setState(() {
                              _useUsdInput = true;
                              _amountController.clear();
                            });
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: _useUsdInput
                                  ? _currentHeaderColor
                                  : Colors.transparent,
                              borderRadius: BorderRadius.circular(15),
                            ),
                            child: Text(
                              'USD',
                              style: TextStyle(
                                color: _useUsdInput
                                    ? Colors.white
                                    : (isDark
                                        ? Colors.white70
                                        : Colors.black87),
                                fontWeight: FontWeight.w600,
                                fontSize: 12,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                ],
              ),
            ],
          ),
          const SizedBox(height: 8),
          // Percentage buttons row
          Row(
            children: [
              _buildPercentButton('25%', 0.25),
              const SizedBox(width: 8),
              _buildPercentButton('50%', 0.50),
              const SizedBox(width: 8),
              _buildPercentButton('75%', 0.75),
              const SizedBox(width: 8),
              _buildPercentButton('MAX', 1.0),
            ],
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _amountController,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: isDark ? Colors.white : Colors.black87),
            decoration: InputDecoration(
              filled: true,
              fillColor: isDark ? const Color(0xFF2A3340) : Colors.grey[50],
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(
                    color: isDark ? Colors.white24 : Colors.grey[300]!),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(
                    color: isDark ? Colors.white24 : Colors.grey[300]!),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: _currentHeaderColor, width: 2),
              ),
              hintText: _useUsdInput ? '0.00' : '0.00000000',
              hintStyle:
                  TextStyle(color: isDark ? Colors.white38 : Colors.grey),
              prefixText: _useUsdInput ? '\$ ' : '',
              prefixStyle: TextStyle(
                  color: isDark ? Colors.white70 : Colors.black87,
                  fontSize: 24,
                  fontWeight: FontWeight.bold),
              suffixText: _useUsdInput ? null : _selectedCoin,
              suffixStyle: TextStyle(
                  color: _currentHeaderColor, fontWeight: FontWeight.bold),
            ),
            onChanged: (_) => setState(() {}),
          ),
          if (_amountController.text.isNotEmpty && _currentCryptoPrice > 0)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                _useUsdInput
                    ? '≈ ${(_getActualCryptoAmount()).toStringAsFixed(8)} $_selectedCoin'
                    : '≈ \$${((double.tryParse(_amountController.text) ?? 0) * _currentCryptoPrice).toStringAsFixed(2)} USD',
                style: TextStyle(
                  color: Colors.grey[600],
                  fontStyle: FontStyle.italic,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildAddressInput() {
    final address = _addressController.text.trim();
    final bool isValidAddress =
        address.isNotEmpty && _validateAddressFormat(address);
    final bool showValidation =
        address.length >= 3; // Show validation after 3+ chars
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E2530) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: isDark ? Border.all(color: Colors.white10) : null,
        boxShadow: isDark
            ? null
            : [
                BoxShadow(
                  color: Colors.grey.withOpacity(0.1),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Recipient Address',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: isDark ? Colors.white : Colors.black87,
                ),
              ),
              IconButton(
                icon: Icon(Icons.qr_code_scanner, color: _currentHeaderColor),
                onPressed: () async {
                  // Launch QR Scanner
                  final result = await Navigator.push<QrScanResult>(
                    context,
                    MaterialPageRoute(
                      builder: (context) => QrScannerPage(
                        expectedCoin: _selectedCoin,
                      ),
                    ),
                  );

                  if (result != null && result.address != null && mounted) {
                    setState(() {
                      _addressController.text = result.address!;
                      // If scanned QR has amount, fill it in
                      if (result.amount != null && result.amount!.isNotEmpty) {
                        _amountController.text = result.amount!;
                      }
                      // Auto-select coin if detected
                      if (result.coin != null) {
                        final matchingCoin = _coins.firstWhere(
                          (c) =>
                              c.symbol.toUpperCase() ==
                              result.coin!.toUpperCase(),
                          orElse: () => _coins.first,
                        );
                        if (matchingCoin.symbol != _selectedCoin) {
                          _onCoinSelected(matchingCoin.symbol);
                        }
                      }
                    });

                    // Show success feedback
                    final addr = result.address!;
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Row(
                          children: [
                            const Icon(Icons.check_circle, color: Colors.white),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                  'Address scanned: ${addr.substring(0, 8)}...${addr.substring(addr.length - 6)}'),
                            ),
                          ],
                        ),
                        backgroundColor: Colors.green,
                        behavior: SnackBarBehavior.floating,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
                    );
                  }
                },
              ),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _addressController,
            style: TextStyle(color: isDark ? Colors.white : Colors.black87),
            decoration: InputDecoration(
              filled: true,
              fillColor: isDark ? const Color(0xFF2A3340) : Colors.grey[50],
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(
                    color: isDark ? Colors.white24 : Colors.grey[300]!),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(
                  color: showValidation
                      ? (isValidAddress ? Colors.green : Colors.red)
                      : (isDark ? Colors.white24 : Colors.grey[300]!),
                  width: showValidation ? 2 : 1,
                ),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(
                  color: showValidation
                      ? (isValidAddress ? Colors.green : Colors.red)
                      : _currentHeaderColor,
                  width: 2,
                ),
              ),
              hintText: 'Enter wallet address',
              hintStyle:
                  TextStyle(color: isDark ? Colors.white38 : Colors.grey),
              suffixIcon: showValidation
                  ? Container(
                      margin: const EdgeInsets.only(right: 12),
                      child: Icon(
                        isValidAddress ? Icons.check_circle : Icons.cancel,
                        color: isValidAddress ? Colors.green : Colors.red,
                        size: 24,
                      ),
                    )
                  : null,
            ),
            onChanged: (value) {
              setState(() {});
            },
          ),
          if (showValidation)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Row(
                children: [
                  Icon(
                    isValidAddress ? Icons.check_circle : Icons.error_outline,
                    size: 14,
                    color: isValidAddress ? Colors.green : Colors.red,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    isValidAddress
                        ? 'Valid ${_selectedCoin.split('-').first} address'
                        : 'Invalid ${_selectedCoin.split('-').first} address format',
                    style: TextStyle(
                      color: isValidAddress ? Colors.green : Colors.red,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildMemoInput() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E2530) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: isDark ? Border.all(color: Colors.white10) : null,
        boxShadow: isDark
            ? null
            : [
                BoxShadow(
                  color: Colors.grey.withOpacity(0.1),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Memo (Optional)',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: isDark ? Colors.white : Colors.black87,
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _memoController,
            style: TextStyle(color: isDark ? Colors.white : Colors.black87),
            decoration: InputDecoration(
              filled: true,
              fillColor: isDark ? const Color(0xFF2A3340) : Colors.grey[50],
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(
                    color: isDark ? Colors.white24 : Colors.grey[300]!),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(
                    color: isDark ? Colors.white24 : Colors.grey[300]!),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: _currentHeaderColor, width: 2),
              ),
              hintText: 'Add a note',
              hintStyle:
                  TextStyle(color: isDark ? Colors.white38 : Colors.grey),
            ),
          ),
        ],
      ),
    );
  }

  // Build percentage button helper
  Widget _buildPercentButton(String label, double percent) {
    final isSelected = _selectedPercent == percent;
    // Use (balance - fee) as the spendable base so that
    // amount + fee never exceeds balance after pressing a % button.
    final spendable = (_availableBalance - _fee).clamp(0.0, double.infinity);
    final total = spendable;
    final isDisabled = !_balanceLoaded || total <= 0;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Expanded(
      child: GestureDetector(
        onTap: isDisabled
            ? null
            : () {
                final amount = total * percent;
                if (_useUsdInput && _currentCryptoPrice > 0) {
                  _amountController.text =
                      (amount * _currentCryptoPrice).toStringAsFixed(2);
                } else {
                  _amountController.text = amount.toStringAsFixed(8);
                }
                setState(() {
                  _selectedPercent = percent;
                });
              },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
          decoration: BoxDecoration(
            color: isDisabled
                ? (isDark ? Colors.white10 : Colors.grey[200])
                : (isSelected
                    ? _currentHeaderColor
                    : _currentHeaderColor.withOpacity(isDark ? 0.2 : 0.1)),
            borderRadius: BorderRadius.circular(8),
            border: isDark && !isSelected && !isDisabled
                ? Border.all(color: _currentHeaderColor.withOpacity(0.3))
                : null,
          ),
          child: Center(
            child: Text(
              label,
              style: TextStyle(
                color: isDisabled
                    ? (isDark ? Colors.white38 : Colors.grey)
                    : (isSelected ? Colors.white : _currentHeaderColor),
                fontWeight: FontWeight.w600,
                fontSize: 11,
              ),
            ),
          ),
        ),
      ),
    );
  }

  // Slide to Send Button for main page
  Widget _buildSlideToSendButton(Color color) {
    if (!_isFormValid) {
      return Container(
        height: 60,
        decoration: BoxDecoration(
          color: Colors.grey[300],
          borderRadius: BorderRadius.circular(30),
        ),
        child: const Center(
          child: Text(
            'Fill in all fields to continue',
            style: TextStyle(
              color: Colors.grey,
              fontWeight: FontWeight.w500,
              fontSize: 16,
            ),
          ),
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final maxSlide = constraints.maxWidth - 60;
        return GestureDetector(
          onHorizontalDragStart: (_) {
            setState(() => _isSliding = true);
          },
          onHorizontalDragUpdate: (details) {
            final newPosition =
                (_slidePosition * maxSlide + details.delta.dx) / maxSlide;
            _onSlideUpdate(newPosition);
          },
          onHorizontalDragEnd: (_) {
            setState(() => _isSliding = false);
            _onSlideComplete();
          },
          child: Container(
            height: 60,
            decoration: BoxDecoration(
              color: color.withOpacity(0.15),
              borderRadius: BorderRadius.circular(30),
              border: Border.all(color: color.withOpacity(0.3), width: 2),
            ),
            child: Stack(
              children: [
                // Animated background fill
                AnimatedContainer(
                  duration: const Duration(milliseconds: 100),
                  width: (_slidePosition * constraints.maxWidth).clamp(0.0, constraints.maxWidth),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        color.withOpacity(0.3),
                        color.withOpacity(0.5),
                      ],
                    ),
                    borderRadius: BorderRadius.circular(28),
                  ),
                ),

                // Text hint - IgnorePointer so it never blocks drag
                IgnorePointer(
                  child: Center(
                    child: AnimatedOpacity(
                      opacity: _slidePosition < 0.3 ? 1.0 : 0.0,
                      duration: const Duration(milliseconds: 200),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            'Slide to Send',
                            style: TextStyle(
                              color: color,
                              fontWeight: FontWeight.w600,
                              fontSize: 16,
                            ),
                          ),
                          const SizedBox(width: 8),
                          _buildAnimatedArrows(color),
                        ],
                      ),
                    ),
                  ),
                ),

                // Thumb indicator (no GestureDetector — parent handles all drag)
                Positioned(
                  left: (_slidePosition * maxSlide).clamp(0.0, maxSlide),
                  top: 0,
                  bottom: 0,
                  child: IgnorePointer(
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 100),
                      width: 60,
                      height: 60,
                      decoration: BoxDecoration(
                        color: color,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: color.withOpacity(0.4),
                            blurRadius: _isSliding ? 20 : 10,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Icon(
                        _slidePosition >= 0.85 ? Icons.check : Icons.double_arrow,
                        color: Colors.white,
                        size: 28,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // Animated arrows widget >>
  Widget _buildAnimatedArrows(Color color) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.0, end: 1.0),
      duration: const Duration(milliseconds: 1000),
      builder: (context, value, child) {
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Transform.translate(
              offset: Offset(value * 4, 0),
              child: Opacity(
                opacity: 0.4 + (value * 0.3),
                child: Icon(Icons.chevron_right, color: color, size: 20),
              ),
            ),
            Transform.translate(
              offset: Offset(value * 6, 0),
              child: Opacity(
                opacity: 0.6 + (value * 0.4),
                child: Icon(Icons.chevron_right, color: color, size: 20),
              ),
            ),
          ],
        );
      },
      onEnd: () {
        // Restart animation
        if (mounted) setState(() {});
      },
    );
  }

  Widget _buildPinEntryPage(Color headerColor) {
    final cryptoAmount = _getActualCryptoAmount();
    final address = _addressController.text.trim();
    final usdValue = _currentCryptoPrice > 0
        ? (cryptoAmount * _currentCryptoPrice).toStringAsFixed(2)
        : '—';
    final coinName = _coins
        .firstWhere((c) => c.symbol == _selectedCoin,
            orElse: () => _coins.first)
        .name;

    return Container(
      color: headerColor,
      child: SafeArea(
        bottom: false,
        child: Column(
          children: [
            // ── Top bar ──────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back_ios_new,
                        color: Colors.white, size: 20),
                    onPressed: () {
                      setState(() {
                        _showPinEntry = false;
                        _enteredPin = '';
                        _showSlideToSend = false;
                      });
                    },
                  ),
                  const Expanded(
                    child: Text(
                      'Confirm Transaction',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 17,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.3,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                  const SizedBox(width: 48),
                ],
              ),
            ),

            // ── Transaction summary ───────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
              child: Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(
                      color: Colors.white.withOpacity(0.25), width: 1),
                ),
                child: Column(
                  children: [
                    // Amount row
                    Row(
                      children: [
                        Container(
                          width: 48,
                          height: 48,
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.2),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            _coins
                                .firstWhere((c) => c.symbol == _selectedCoin,
                                    orElse: () => _coins.first)
                                .icon,
                            color: Colors.white,
                            size: 26,
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Sending $coinName',
                                style: TextStyle(
                                  color: Colors.white.withOpacity(0.75),
                                  fontSize: 12,
                                  fontWeight: FontWeight.w400,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                '${cryptoAmount.toStringAsFixed(6)} ${_selectedCoin.split('-').first}',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 22,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 0.2,
                                ),
                              ),
                              Text(
                                '≈ \$$usdValue USD',
                                style: TextStyle(
                                  color: Colors.white.withOpacity(0.75),
                                  fontSize: 13,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 14),
                    Divider(color: Colors.white.withOpacity(0.2), height: 1),
                    const SizedBox(height: 14),

                    // To address
                    _summaryRow(
                      icon: Icons.account_circle_outlined,
                      label: 'To',
                      value: address.length > 20
                          ? '${address.substring(0, 10)}…${address.substring(address.length - 8)}'
                          : address,
                      mono: true,
                    ),
                    const SizedBox(height: 10),
                    // Network fee
                    _summaryRow(
                      icon: Icons.local_gas_station_outlined,
                      label: 'Network Fee',
                      value:
                          '${_fee.toStringAsFixed(6)} ${_selectedCoin.split('-').first}',
                    ),
                    const SizedBox(height: 10),
                    // Total
                    _summaryRow(
                      icon: Icons.summarize_outlined,
                      label: 'Total Deducted',
                      value:
                          '${(cryptoAmount + _fee).toStringAsFixed(6)} ${_selectedCoin.split('-').first}',
                      bold: true,
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 12),

            // ── White sheet with PIN / slide ──────────────────────
            // While sending, skip the white sheet — show a transparent
            // spinner so the colored header fills the whole screen.
            if (_loading)
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const CircularProgressIndicator(
                      color: Colors.white,
                      strokeWidth: 3,
                    ),
                    const SizedBox(height: 20),
                    const Text(
                      'Broadcasting transaction...',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'This may take up to 30 seconds',
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.65),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              )
            else
              Expanded(
                child: Container(
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.only(
                      topLeft: Radius.circular(30),
                      topRight: Radius.circular(30),
                    ),
                  ),
                  child: _showSlideToSend
                      ? _buildConfirmSlideToSend(headerColor)
                      : _buildPinEntry(headerColor, null),
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// Small helper row for transaction summary
  Widget _summaryRow({
    required IconData icon,
    required String label,
    required String value,
    bool mono = false,
    bool bold = false,
  }) {
    return Row(
      children: [
        Icon(icon, color: Colors.white.withOpacity(0.7), size: 16),
        const SizedBox(width: 8),
        Text(
          label,
          style: TextStyle(
            color: Colors.white.withOpacity(0.7),
            fontSize: 12,
          ),
        ),
        const Spacer(),
        Text(
          value,
          style: TextStyle(
            color: Colors.white,
            fontSize: 13,
            fontWeight: bold ? FontWeight.bold : FontWeight.w500,
            fontFamily: mono ? 'monospace' : null,
          ),
        ),
      ],
    );
  }

  Widget _buildPinEntry(Color headerColor, [BoxConstraints? constraints]) {
    return LayoutBuilder(builder: (context, bc) {
      final double totalH = bc.maxHeight;
      final double keypadArea = (totalH - 200).clamp(180.0, 360.0);
      final double itemH = (keypadArea / 4).clamp(52.0, 80.0);
      final double itemW = (bc.maxWidth - 80) / 3;
      final double aspect = (itemW / itemH).clamp(0.9, 1.8);

      return SingleChildScrollView(
        physics: const ClampingScrollPhysics(),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 28),
          child: Column(
            children: [
              const SizedBox(height: 28),

              // Lock icon
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: headerColor.withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.lock_outline_rounded,
                    color: headerColor, size: 28),
              ),
              const SizedBox(height: 14),

              const Text(
                'Enter your PIN',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF1A1A2E),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Enter your 6-digit PIN to confirm the transaction',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13,
                  color: Colors.grey[500],
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 24),

              // PIN Dots
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(6, (index) {
                  final filled = index < _enteredPin.length;
                  return AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    margin: const EdgeInsets.symmetric(horizontal: 9),
                    width: filled ? 18 : 15,
                    height: filled ? 18 : 15,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: filled ? headerColor : Colors.transparent,
                      border: Border.all(
                        color: filled ? headerColor : Colors.grey[300]!,
                        width: 2,
                      ),
                      boxShadow: filled
                          ? [
                              BoxShadow(
                                color: headerColor.withOpacity(0.35),
                                blurRadius: 8,
                                offset: const Offset(0, 3),
                              ),
                            ]
                          : null,
                    ),
                  );
                }),
              ),

              const SizedBox(height: 28),

              // Number Pad
              GridView.count(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                crossAxisCount: 3,
                childAspectRatio: aspect,
                mainAxisSpacing: 10,
                crossAxisSpacing: 10,
                children: [
                  ...List.generate(
                      9, (i) => _buildNumberButton('${i + 1}', headerColor)),
                  const SizedBox(),
                  _buildNumberButton('0', headerColor),
                  _buildBackspaceButton(headerColor),
                ],
              ),

              const SizedBox(height: 16),
            ],
          ),
        ),
      );
    });
  }

  Widget _buildNumberButton(String digit, Color color) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          HapticFeedback.lightImpact();
          _onPinDigitPressed(digit);
        },
        borderRadius: BorderRadius.circular(100),
        child: Container(
          decoration: BoxDecoration(
            color: const Color(0xFFF5F6FA),
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.06),
                blurRadius: 6,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Center(
            child: Text(
              digit,
              style: const TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w600,
                color: Color(0xFF1A1A2E),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBackspaceButton(Color color) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          HapticFeedback.lightImpact();
          _onPinBackspace();
        },
        borderRadius: BorderRadius.circular(100),
        child: Container(
          decoration: BoxDecoration(
            color: const Color(0xFFF5F6FA),
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.06),
                blurRadius: 6,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Center(
            child: Icon(
              Icons.backspace_outlined,
              color: Colors.grey[600],
              size: 24,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildConfirmSlideToSend(Color headerColor) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        // Success icon
        TweenAnimationBuilder<double>(
          tween: Tween(begin: 0.0, end: 1.0),
          duration: const Duration(milliseconds: 500),
          builder: (context, value, child) {
            return Transform.scale(
              scale: value,
              child: Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  color: Colors.green.withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.check_circle,
                  color: Colors.green,
                  size: 50,
                ),
              ),
            );
          },
        ),
        const SizedBox(height: 16),
        const Text(
          'PIN Verified!',
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.bold,
            color: Colors.green,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Slide to confirm your transaction',
          style: TextStyle(
            color: Colors.grey[600],
            fontSize: 14,
          ),
        ),
        const SizedBox(height: 40),

        // Final Slide to Send — entire track is draggable
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 32),
          height: 70,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final maxSlide = constraints.maxWidth - 70;
              return GestureDetector(
                // Whole track responds to drag, not just the circle
                onHorizontalDragStart: (_) {
                  setState(() => _isSliding = true);
                },
                onHorizontalDragUpdate: (details) {
                  final newPosition =
                      (_slidePosition * maxSlide + details.delta.dx) /
                          maxSlide;
                  _onSlideUpdate(newPosition);
                },
                onHorizontalDragEnd: (_) {
                  setState(() => _isSliding = false);
                  _onSlideComplete();
                },
                child: Stack(
                  children: [
                    // Track background
                    Container(
                      height: 70,
                      decoration: BoxDecoration(
                        color: headerColor.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(35),
                        border: Border.all(
                          color: headerColor.withOpacity(0.25),
                        ),
                      ),
                    ),

                    // Fill animation
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 100),
                      width: 70 + (_slidePosition * maxSlide),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            headerColor.withOpacity(0.3),
                            headerColor.withOpacity(0.55),
                          ],
                        ),
                        borderRadius: BorderRadius.circular(35),
                      ),
                    ),

                    // Label — hidden once circle moves past it
                    IgnorePointer(
                      child: Center(
                        child: AnimatedOpacity(
                          opacity: _slidePosition < 0.3 ? 1.0 : 0.0,
                          duration: const Duration(milliseconds: 200),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                'Slide to Confirm',
                                style: TextStyle(
                                  color: headerColor,
                                  fontWeight: FontWeight.w600,
                                  fontSize: 16,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Icon(Icons.arrow_forward,
                                  color: headerColor, size: 20),
                            ],
                          ),
                        ),
                      ),
                    ),

                    // Draggable circle (no GestureDetector — parent handles it)
                    Positioned(
                      left: (_slidePosition * maxSlide).clamp(0.0, maxSlide),
                      top: 0,
                      bottom: 0,
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 100),
                        width: 70,
                        height: 70,
                        decoration: BoxDecoration(
                          color: headerColor,
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: headerColor.withOpacity(0.5),
                              blurRadius: _isSliding ? 25 : 15,
                              offset: const Offset(0, 5),
                            ),
                          ],
                        ),
                        child: Icon(
                          _slidePosition >= 0.85 ? Icons.check : Icons.send,
                          color: Colors.white,
                          size: 30,
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),

        const SizedBox(height: 60),
      ],
    );
  }
}

class CoinData {
  final String symbol;
  final String name;
  final Color color;
  final IconData icon;

  CoinData(this.symbol, this.name, this.color, this.icon);
}
