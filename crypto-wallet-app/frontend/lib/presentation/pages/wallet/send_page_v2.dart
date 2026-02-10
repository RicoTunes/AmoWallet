import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:confetti/confetti.dart';
import 'dart:math' as math;

import '../../../core/constants/app_constants.dart';
import '../../../models/transaction_model.dart';
import '../../../services/wallet_service.dart';
import '../../../services/transaction_service.dart';
import '../../../services/blockchain_service.dart';
import '../../../services/biometric_auth_service.dart';
import '../../../services/pin_auth_service.dart';
import '../../../services/notification_service.dart';
import '../../widgets/qr_scanner_widget.dart';

class SendPageV2 extends ConsumerStatefulWidget {
  const SendPageV2({super.key, this.initialCoin, this.initialAddress});

  final String? initialCoin;
  final String? initialAddress;

  @override
  ConsumerState<SendPageV2> createState() => _SendPageV2State();
}

class _SendPageV2State extends ConsumerState<SendPageV2>
    with TickerProviderStateMixin {
  final WalletService _walletService = WalletService();
  final TransactionService _transactionService = TransactionService();
  final BlockchainService _blockchainService = BlockchainService();
  final BiometricAuthService _biometricService = BiometricAuthService();
  final PinAuthService _pinAuthService = PinAuthService();
  final NotificationService _notificationService = NotificationService();

  final TextEditingController _amountController = TextEditingController();
  final TextEditingController _addressController = TextEditingController();

  // Confetti controller
  late ConfettiController _confettiController;

  // Animation controllers
  late AnimationController _colorAnimationController;
  late AnimationController _slideController;
  late Animation<Color?> _headerColorAnimation;

  // PIN entry state
  bool _showPinEntry = false;
  String _enteredPin = '';
  bool _pinError = false;

  // Slide to send state
  bool _showSlideToSend = false;
  double _slideProgress = 0.0;
  bool _isSending = false;
  bool _sendSuccess = false;

  String _selectedCoin = 'BTC';
  double _availableBalance = 0.0;
  double _fee = 0.0;
  bool _loadingBalance = false;
  bool _loading = false;
  Color _currentHeaderColor = const Color(0xFFF7931A); // BTC Orange

  // Coin configurations with colors
  final List<Map<String, dynamic>> _coins = [
    {
      'symbol': 'BTC',
      'name': 'Bitcoin',
      'color': Color(0xFFF7931A),
      'icon': Icons.currency_bitcoin
    },
    {
      'symbol': 'ETH',
      'name': 'Ethereum',
      'color': Color(0xFF627EEA),
      'icon': Icons.diamond_outlined
    },
    {
      'symbol': 'BNB',
      'name': 'BNB',
      'color': Color(0xFFF3BA2F),
      'icon': Icons.hexagon_outlined
    },
    {
      'symbol': 'SOL',
      'name': 'Solana',
      'color': Color(0xFF00FFA3),
      'icon': Icons.sunny
    },
    {
      'symbol': 'USDT',
      'name': 'Tether',
      'color': Color(0xFF26A17B),
      'icon': Icons.attach_money
    },
    {
      'symbol': 'TRX',
      'name': 'TRON',
      'color': Color(0xFFEF0027),
      'icon': Icons.flash_on
    },
    {
      'symbol': 'XRP',
      'name': 'XRP',
      'color': Color(0xFF00AAE4),
      'icon': Icons.water_drop_outlined
    },
    {
      'symbol': 'DOGE',
      'name': 'Dogecoin',
      'color': Color(0xFFC2A633),
      'icon': Icons.pets
    },
    {
      'symbol': 'LTC',
      'name': 'Litecoin',
      'color': Color(0xFFBFBBBB),
      'icon': Icons.bolt
    },
  ];

  @override
  void initState() {
    super.initState();
    _selectedCoin = widget.initialCoin ?? 'BTC';
    _addressController.text = widget.initialAddress ?? '';

    _confettiController =
        ConfettiController(duration: const Duration(seconds: 3));

    _colorAnimationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );

    _slideController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );

    _updateHeaderColor(_getCoinColor(_selectedCoin));
    _loadBalance();
  }

  @override
  void dispose() {
    _confettiController.dispose();
    _colorAnimationController.dispose();
    _slideController.dispose();
    _amountController.dispose();
    _addressController.dispose();
    super.dispose();
  }

  Color _getCoinColor(String symbol) {
    return _coins.firstWhere(
      (c) => c['symbol'] == symbol,
      orElse: () => {'color': const Color(0xFF8B5CF6)},
    )['color'] as Color;
  }

  void _updateHeaderColor(Color newColor) {
    final oldColor = _currentHeaderColor;
    _headerColorAnimation = ColorTween(begin: oldColor, end: newColor).animate(
      CurvedAnimation(
          parent: _colorAnimationController, curve: Curves.easeInOut),
    );
    _colorAnimationController.forward(from: 0);
    setState(() => _currentHeaderColor = newColor);
  }

  void _selectCoin(String symbol) {
    HapticFeedback.selectionClick();
    setState(() {
      _selectedCoin = symbol;
      _availableBalance = 0.0; // Reset balance immediately
      _selectedPercent = null; // Reset percentage selection
      _amountController.clear(); // Clear amount input
      _loadingBalance = true;
    });
    _updateHeaderColor(_getCoinColor(symbol));
    _loadBalance();
  }

  Future<void> _loadBalance() async {
    setState(() => _loadingBalance = true);
    try {
      final addresses = await _walletService.getStoredAddresses(_selectedCoin);
      if (addresses.isNotEmpty) {
        final balance =
            await _blockchainService.getBalance(_selectedCoin, addresses.first);
        final fee = await _blockchainService.getFeeEstimate(_selectedCoin);
        if (mounted) {
          setState(() {
            _availableBalance = balance;
            _fee = fee;
            _loadingBalance = false;
          });
        }
      } else {
        if (mounted) {
          setState(() {
            _availableBalance = 0.0;
            _fee = 0.001;
            _loadingBalance = false;
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _availableBalance = 0.0;
          _fee = 0.001;
          _loadingBalance = false;
        });
      }
    }
  }

  void _proceedToPin() {
    // Validate inputs first
    final amount = double.tryParse(_amountController.text) ?? 0;
    if (amount <= 0) {
      _showError('Please enter a valid amount');
      return;
    }
    if (_addressController.text.isEmpty) {
      _showError('Please enter a recipient address');
      return;
    }
    if (amount + _fee > _availableBalance) {
      _showError('Insufficient balance');
      return;
    }

    HapticFeedback.mediumImpact();
    setState(() {
      _showPinEntry = true;
      _enteredPin = '';
      _pinError = false;
    });
  }

  void _onPinDigitEntered(String digit) {
    if (_enteredPin.length >= 6) return;

    HapticFeedback.lightImpact();
    setState(() {
      _enteredPin += digit;
      _pinError = false;
    });

    if (_enteredPin.length == 6) {
      _verifyPin();
    }
  }

  void _onPinBackspace() {
    if (_enteredPin.isEmpty) return;

    HapticFeedback.lightImpact();
    setState(() {
      _enteredPin = _enteredPin.substring(0, _enteredPin.length - 1);
      _pinError = false;
    });
  }

  Future<void> _verifyPin() async {
    final isValid = await _pinAuthService.verifyPin(_enteredPin);

    if (isValid) {
      HapticFeedback.heavyImpact();
      setState(() {
        _showPinEntry = false;
        _showSlideToSend = true;
      });
    } else {
      HapticFeedback.vibrate();
      setState(() {
        _pinError = true;
        _enteredPin = '';
      });
    }
  }

  void _onSlideUpdate(double progress) {
    setState(() => _slideProgress = progress);
  }

  Future<void> _executeTransaction() async {
    if (_isSending) return;

    HapticFeedback.heavyImpact();
    setState(() {
      _isSending = true;
      _slideProgress = 1.0;
    });

    try {
      final amount = double.parse(_amountController.text);
      final toAddress = _addressController.text.trim();

      // Get the sender's address
      final addresses = await _walletService.getStoredAddresses(_selectedCoin);
      if (addresses.isEmpty) {
        throw Exception('No wallet found for $_selectedCoin');
      }
      final fromAddress = addresses.first;

      // Send real transaction via blockchain service
      final txHash = await _blockchainService.sendTransaction(
        coin: _selectedCoin,
        fromAddress: fromAddress,
        toAddress: toAddress,
        amount: amount,
        fee: _fee,
      );

      // Store transaction locally for history
      final transaction = Transaction(
        id: txHash,
        type: 'sent',
        coin: _selectedCoin,
        amount: amount,
        address: fromAddress,
        fromAddress: fromAddress,
        toAddress: toAddress,
        txHash: txHash,
        timestamp: DateTime.now(),
        status: 'pending',
        fee: _fee,
        memo: 'Sent from wallet',
        isPending: true,
      );
      await _transactionService.storeTransaction(transaction);

      // Success!
      HapticFeedback.heavyImpact();
      _confettiController.play();

      setState(() {
        _sendSuccess = true;
        _isSending = false;
      });

      _notificationService.showNotification(
        title: 'Transaction Sent!',
        message:
            'Sent $amount $_selectedCoin successfully\nTX: ${txHash.substring(0, 16)}...',
        type: NotificationType.success,
      );

      // Wait for confetti then go back
      await Future.delayed(const Duration(seconds: 3));
      if (mounted) {
        context.go('/dashboard');
      }
    } catch (e) {
      setState(() {
        _isSending = false;
        _slideProgress = 0.0;
      });
      _showError('Transaction failed: ${e.toString()}');
    }
  }

  Future<void> _openQRScanner() async {
    HapticFeedback.lightImpact();
    
    // Show QR scanner bottom sheet with real camera support
    final result = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => QRScannerWidget(
        accentColor: _currentHeaderColor,
        onScanned: (value) {
          // This callback is for additional handling if needed
        },
      ),
    );
    
    if (result != null && result.isNotEmpty) {
      // Parse the scanned result - could be just address or crypto URI
      String address = result;
      String? amount;
      String? coin;
      
      // Check for crypto URI format (e.g., bitcoin:address?amount=0.1)
      if (result.contains(':')) {
        final uri = Uri.tryParse(result);
        if (uri != null) {
          // Extract coin from scheme
          final scheme = uri.scheme.toLowerCase();
          if (scheme == 'bitcoin' || scheme == 'btc') coin = 'BTC';
          else if (scheme == 'ethereum' || scheme == 'eth') coin = 'ETH';
          else if (scheme == 'solana' || scheme == 'sol') coin = 'SOL';
          else if (scheme == 'bnb' || scheme == 'bsc') coin = 'BNB';
          else if (scheme == 'tron' || scheme == 'trx') coin = 'TRX';
          else if (scheme == 'litecoin' || scheme == 'ltc') coin = 'LTC';
          else if (scheme == 'dogecoin' || scheme == 'doge') coin = 'DOGE';
          else if (scheme == 'ripple' || scheme == 'xrp') coin = 'XRP';
          
          address = uri.path;
          amount = uri.queryParameters['amount'];
        }
      }
      
      setState(() {
        _addressController.text = address;
        if (amount != null) {
          _amountController.text = amount;
        }
        if (coin != null) {
          _selectCoin(coin);
        }
      });
      
      _showSuccess('Address scanned successfully!');
    }
  }

  void _showSuccess(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: const Color(0xFF10B981),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  void _showError(String message) {
    HapticFeedback.vibrate();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D1421),
      body: Stack(
        children: [
          // Main content
          if (_showPinEntry)
            _buildPinEntryScreen()
          else if (_showSlideToSend)
            _buildSlideToSendScreen()
          else
            _buildMainSendScreen(),

          // Confetti overlay
          Align(
            alignment: Alignment.topCenter,
            child: ConfettiWidget(
              confettiController: _confettiController,
              blastDirection: math.pi / 2,
              maxBlastForce: 5,
              minBlastForce: 2,
              emissionFrequency: 0.05,
              numberOfParticles: 50,
              gravity: 0.1,
              shouldLoop: false,
              colors: [
                _currentHeaderColor,
                Colors.white,
                const Color(0xFF8B5CF6),
                const Color(0xFF10B981),
                const Color(0xFFFFD700),
              ],
            ),
          ),

          // Success overlay
          if (_sendSuccess) _buildSuccessOverlay(),
        ],
      ),
    );
  }

  // Track selected percentage
  int? _selectedPercent;

  Widget _buildMainSendScreen() {
    return AnimatedBuilder(
      animation: _colorAnimationController,
      builder: (context, child) {
        final headerColor = _headerColorAnimation?.value ?? _currentHeaderColor;

        return CustomScrollView(
          slivers: [
            // Animated color header
            SliverToBoxAdapter(
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 400),
                curve: Curves.easeInOut,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      headerColor.withOpacity(0.15),
                      const Color(0xFF1A1F2E),
                    ],
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                  ),
                ),
                child: SafeArea(
                  bottom: false,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 16),
                    child: Row(
                      children: [
                        GestureDetector(
                          onTap: () {
                            HapticFeedback.lightImpact();
                            context.go('/dashboard');
                          },
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 300),
                            width: 44,
                            height: 44,
                            decoration: BoxDecoration(
                              color: headerColor.withOpacity(0.2),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: headerColor.withOpacity(0.3),
                                width: 1,
                              ),
                            ),
                            child: Icon(
                              Icons.arrow_back_ios_new_rounded,
                              color: headerColor,
                              size: 18,
                            ),
                          ),
                        ),
                        Expanded(
                          child: Column(
                            children: [
                              const Text(
                                'Send Crypto',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 4),
                              AnimatedDefaultTextStyle(
                                duration: const Duration(milliseconds: 300),
                                style: TextStyle(
                                  color: headerColor,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w500,
                                ),
                                child: Text(_selectedCoin),
                              ),
                            ],
                          ),
                        ),
                        GestureDetector(
                          onTap: () => _openQRScanner(),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 300),
                            width: 44,
                            height: 44,
                            decoration: BoxDecoration(
                              color: headerColor.withOpacity(0.2),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: headerColor.withOpacity(0.3),
                                width: 1,
                              ),
                            ),
                            child: Icon(
                              Icons.qr_code_scanner_rounded,
                              color: headerColor,
                              size: 20,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),

            // Coin selection cards
            SliverToBoxAdapter(
              child: _buildCoinSelection(),
            ),

            // Amount input
            SliverToBoxAdapter(
              child: _buildAmountSection(),
            ),

            // Address input
            SliverToBoxAdapter(
              child: _buildAddressSection(),
            ),

            // Fee info
            SliverToBoxAdapter(
              child: _buildFeeSection(),
            ),

            // Continue button
            SliverToBoxAdapter(
              child: _buildContinueButton(),
            ),

            const SliverToBoxAdapter(
              child: SizedBox(height: 40),
            ),
          ],
        );
      },
    );
  }

  Widget _buildCoinSelection() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Select Coin',
            style: TextStyle(
              color: Colors.white70,
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 90,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: _coins.length,
              itemBuilder: (context, index) {
                final coin = _coins[index];
                final isSelected = _selectedCoin == coin['symbol'];
                final color = coin['color'] as Color;

                return GestureDetector(
                  onTap: () => _selectCoin(coin['symbol'] as String),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 300),
                    curve: Curves.easeInOut,
                    width: 75,
                    margin: const EdgeInsets.only(right: 12),
                    decoration: BoxDecoration(
                      gradient: isSelected
                          ? LinearGradient(
                              colors: [
                                color.withOpacity(0.3),
                                color.withOpacity(0.1)
                              ],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            )
                          : null,
                      color: isSelected ? null : const Color(0xFF1A1F2E),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: isSelected ? color : Colors.transparent,
                        width: 2,
                      ),
                      boxShadow: isSelected
                          ? [
                              BoxShadow(
                                color: color.withOpacity(0.3),
                                blurRadius: 12,
                                spreadRadius: 0,
                              ),
                            ]
                          : null,
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            color: isSelected ? color : color.withOpacity(0.2),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Icon(
                            coin['icon'] as IconData,
                            color: isSelected ? Colors.white : color,
                            size: 20,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          coin['symbol'] as String,
                          style: TextStyle(
                            color: isSelected ? Colors.white : Colors.white60,
                            fontSize: 12,
                            fontWeight:
                                isSelected ? FontWeight.bold : FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAmountSection() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Amount',
                style: TextStyle(
                  color: Colors.white70,
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
              _loadingBalance
                  ? Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(
                          width: 12,
                          height: 12,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: _currentHeaderColor,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          'Loading...',
                          style: TextStyle(
                            color: _currentHeaderColor,
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    )
                  : Text(
                      'Balance: ${_availableBalance.toStringAsFixed(8)} $_selectedCoin',
                      style: TextStyle(
                        color: _currentHeaderColor,
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
            ),
            child: TextField(
              controller: _amountController,
              style: const TextStyle(
                color: Color(0xFF1A1F2E),
                fontSize: 24,
                fontWeight: FontWeight.bold,
              ),
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                hintText: '0.00',
                hintStyle: TextStyle(
                  color: Color(0xFF9CA3AF),
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
                border: InputBorder.none,
                contentPadding: EdgeInsets.symmetric(vertical: 16),
              ),
            ),
          ),
          const SizedBox(height: 12),
          // Percentage buttons with color selection
          Row(
            children: [25, 50, 75, 100].map((percent) {
              final isSelected = _selectedPercent == percent;
              return Expanded(
                child: GestureDetector(
                  onTap: () {
                    HapticFeedback.lightImpact();
                    setState(() => _selectedPercent = percent);
                    // Ensure we don't get negative amounts
                    final maxSendable = _availableBalance - _fee;
                    final amount = maxSendable > 0 ? maxSendable * percent / 100 : 0.0;
                    _amountController.text = amount > 0 ? amount.toStringAsFixed(8) : '0.0';
                  },
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    margin: EdgeInsets.only(right: percent < 100 ? 8 : 0),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? _currentHeaderColor
                          : const Color(0xFF1A1F2E),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: isSelected
                            ? _currentHeaderColor
                            : Colors.transparent,
                        width: 1,
                      ),
                    ),
                    child: Center(
                      child: Text(
                        '$percent%',
                        style: TextStyle(
                          color: isSelected ? Colors.white : Colors.white70,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildAddressSection() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Recipient Address',
            style: TextStyle(
              color: Colors.white70,
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _addressController,
                    style: const TextStyle(
                      color: Color(0xFF1A1F2E),
                      fontSize: 14,
                    ),
                    decoration: const InputDecoration(
                      hintText: 'Enter wallet address',
                      hintStyle: TextStyle(
                        color: Color(0xFF9CA3AF),
                      ),
                      border: InputBorder.none,
                      contentPadding: EdgeInsets.symmetric(vertical: 16),
                    ),
                  ),
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Address Book
                    GestureDetector(
                      onTap: () async {
                        HapticFeedback.lightImpact();
                        final address = await context.push<String>(
                          '/address-book',
                          extra: {'selectForCoin': _selectedCoin},
                        );
                        if (address != null) {
                          _addressController.text = address;
                        }
                      },
                      child: Icon(
                        Icons.contacts_rounded,
                        color: _currentHeaderColor,
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 12),
                    // Paste
                    GestureDetector(
                      onTap: () async {
                        HapticFeedback.lightImpact();
                        final data = await Clipboard.getData('text/plain');
                        if (data?.text != null) {
                          _addressController.text = data!.text!;
                        }
                      },
                      child: const Icon(
                        Icons.paste_rounded,
                        color: Color(0xFF6B7280),
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 12),
                    // QR Scanner
                    GestureDetector(
                      onTap: () => _openQRScanner(),
                      child: Icon(
                        Icons.qr_code_scanner_rounded,
                        color: _currentHeaderColor,
                        size: 20,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFeeSection() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFF1A1F2E),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'Network Fee',
              style: TextStyle(
                color: Colors.white70,
                fontSize: 14,
              ),
            ),
            Text(
              '${_fee.toStringAsFixed(8)} $_selectedCoin',
              style: TextStyle(
                color: _currentHeaderColor,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildContinueButton() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: GestureDetector(
        onTap: _proceedToPin,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 18),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                _currentHeaderColor,
                _currentHeaderColor.withOpacity(0.8)
              ],
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
            ),
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: _currentHeaderColor.withOpacity(0.3),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: const Center(
            child: Text(
              'Continue',
              style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPinEntryScreen() {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 500),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            _currentHeaderColor.withOpacity(0.2),
            const Color(0xFF0D1421),
          ],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
      ),
      child: SafeArea(
        child: Column(
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.all(20),
              child: Row(
                children: [
                  GestureDetector(
                    onTap: () {
                      HapticFeedback.lightImpact();
                      setState(() {
                        _showPinEntry = false;
                        _enteredPin = '';
                      });
                    },
                    child: Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(
                        Icons.arrow_back_ios_new_rounded,
                        color: Colors.white,
                        size: 18,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            const Spacer(),

            // Lock icon
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: _currentHeaderColor.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.lock_rounded,
                color: _currentHeaderColor,
                size: 40,
              ),
            ),
            const SizedBox(height: 24),

            // Title
            const Text(
              'Enter PIN',
              style: TextStyle(
                color: Colors.white,
                fontSize: 24,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Enter your 6-digit PIN to continue',
              style: TextStyle(
                color: Colors.white.withOpacity(0.6),
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 40),

            // PIN dots
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(6, (index) {
                final isFilled = index < _enteredPin.length;
                return AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  margin: const EdgeInsets.symmetric(horizontal: 8),
                  width: 16,
                  height: 16,
                  decoration: BoxDecoration(
                    color: _pinError
                        ? Colors.red
                        : (isFilled
                            ? _currentHeaderColor
                            : Colors.white.withOpacity(0.2)),
                    shape: BoxShape.circle,
                  ),
                );
              }),
            ),

            if (_pinError) ...[
              const SizedBox(height: 16),
              const Text(
                'Incorrect PIN. Try again.',
                style: TextStyle(
                  color: Colors.red,
                  fontSize: 14,
                ),
              ),
            ],

            const Spacer(),

            // Keypad
            _buildPinKeypad(),

            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  Widget _buildPinKeypad() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 40),
      child: Column(
        children: [
          for (var row = 0; row < 4; row++)
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  for (var col = 0; col < 3; col++)
                    _buildKeypadButton(row, col),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildKeypadButton(int row, int col) {
    String? digit;
    IconData? icon;
    VoidCallback? onTap;

    if (row < 3) {
      digit = '${row * 3 + col + 1}';
      onTap = () => _onPinDigitEntered(digit!);
    } else {
      if (col == 0) {
        // Biometric (optional)
        icon = Icons.fingerprint;
        onTap = () async {
          final success = await _biometricService.authenticate();
          if (success) {
            setState(() {
              _showPinEntry = false;
              _showSlideToSend = true;
            });
          }
        };
      } else if (col == 1) {
        digit = '0';
        onTap = () => _onPinDigitEntered('0');
      } else {
        icon = Icons.backspace_outlined;
        onTap = _onPinBackspace;
      }
    }

    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: MediaQuery.of(context).size.width * 0.18, // Responsive width
        height: MediaQuery.of(context).size.width * 0.18, // Responsive height
        decoration: BoxDecoration(
          color: const Color(0xFF1A1F2E),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Center(
          child: digit != null
              ? Text(
                  digit,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: MediaQuery.of(context).size.width * 0.06, // Responsive font size
                    fontWeight: FontWeight.w600,
                  ),
                )
              : Icon(
                  icon,
                  color: Colors.white.withOpacity(0.7),
                  size: MediaQuery.of(context).size.width * 0.07, // Responsive icon size
                ),
        ),
      ),
    );
  }

  Widget _buildSlideToSendScreen() {
    final amount = double.tryParse(_amountController.text) ?? 0;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 500),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            _currentHeaderColor.withOpacity(0.2),
            const Color(0xFF0D1421),
          ],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            children: [
              // Header
              Row(
                children: [
                  GestureDetector(
                    onTap: () {
                      HapticFeedback.lightImpact();
                      setState(() {
                        _showSlideToSend = false;
                        _slideProgress = 0;
                      });
                    },
                    child: Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(
                        Icons.arrow_back_ios_new_rounded,
                        color: Colors.white,
                        size: 18,
                      ),
                    ),
                  ),
                  const Expanded(
                    child: Text(
                      'Confirm Send',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const SizedBox(width: 40),
                ],
              ),

              const Spacer(),

              // Amount display
              Container(
                width: 100,
                height: 100,
                decoration: BoxDecoration(
                  color: _currentHeaderColor.withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  _coins.firstWhere(
                    (c) => c['symbol'] == _selectedCoin,
                    orElse: () => {'icon': Icons.token},
                  )['icon'] as IconData,
                  color: _currentHeaderColor,
                  size: 50,
                ),
              ),
              const SizedBox(height: 24),

              Text(
                '${amount.toStringAsFixed(8)} $_selectedCoin',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 32,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'to ${_addressController.text.substring(0, math.min(8, _addressController.text.length))}...${_addressController.text.length > 8 ? _addressController.text.substring(_addressController.text.length - 6) : ''}',
                style: TextStyle(
                  color: Colors.white.withOpacity(0.6),
                  fontSize: 14,
                ),
              ),

              const Spacer(),

              // Slide to send
              _buildSlideToSendButton(),

              const SizedBox(height: 40),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSlideToSendButton() {
    return Container(
      height: 70,
      decoration: BoxDecoration(
        color: const Color(0xFF1A1F2E),
        borderRadius: BorderRadius.circular(35),
      ),
      child: Stack(
        children: [
          // Progress fill
          AnimatedContainer(
            duration: const Duration(milliseconds: 100),
            width: (MediaQuery.of(context).size.width - 40) * _slideProgress,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  _currentHeaderColor,
                  _currentHeaderColor.withOpacity(0.7)
                ],
              ),
              borderRadius: BorderRadius.circular(35),
            ),
          ),

          // Text
          Center(
            child: AnimatedOpacity(
              duration: const Duration(milliseconds: 200),
              opacity: _slideProgress < 0.5 ? 1 : 0,
              child: const Text(
                'Slide to Send →',
                style: TextStyle(
                  color: Colors.white54,
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ),

          // Slider button
          Positioned(
            left:
                _slideProgress * (MediaQuery.of(context).size.width - 40 - 60),
            top: 5,
            child: GestureDetector(
              onHorizontalDragUpdate: (details) {
                if (_isSending) return;
                final newProgress = (_slideProgress +
                        details.delta.dx /
                            (MediaQuery.of(context).size.width - 100))
                    .clamp(0.0, 1.0);
                _onSlideUpdate(newProgress);
              },
              onHorizontalDragEnd: (details) {
                if (_isSending) return;
                if (_slideProgress > 0.8) {
                  _executeTransaction();
                } else {
                  setState(() => _slideProgress = 0);
                }
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 100),
                width: 60,
                height: 60,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      _currentHeaderColor,
                      _currentHeaderColor.withOpacity(0.8)
                    ],
                  ),
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: _currentHeaderColor.withOpacity(0.3),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Center(
                  child: _isSending
                      ? const SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 2,
                          ),
                        )
                      : const Icon(
                          Icons.arrow_forward_rounded,
                          color: Colors.white,
                          size: 28,
                        ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSuccessOverlay() {
    return Container(
      color: const Color(0xFF0D1421).withOpacity(0.95),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 120,
              height: 120,
              decoration: BoxDecoration(
                color: const Color(0xFF10B981).withOpacity(0.2),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.check_circle_rounded,
                color: Color(0xFF10B981),
                size: 80,
              ),
            ),
            const SizedBox(height: 24),
            const Text(
              'Transaction Sent!',
              style: TextStyle(
                color: Colors.white,
                fontSize: 28,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Your $_selectedCoin is on its way',
              style: TextStyle(
                color: Colors.white.withOpacity(0.6),
                fontSize: 16,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
