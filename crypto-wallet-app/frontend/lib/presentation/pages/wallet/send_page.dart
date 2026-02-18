import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/theme/app_theme.dart';
import '../../../services/wallet_service.dart';
import '../../../services/transaction_service.dart';
import '../../../services/blockchain_service.dart';
import '../../../services/biometric_auth_service.dart';
import '../../../services/pin_auth_service.dart';
import '../../../services/notification_service.dart';
import '../../../services/spending_limit_service.dart';
import '../../../services/confirmation_tracker_service.dart';
import '../../../utils/input_validator.dart';
import '../../widgets/pin_dialogs.dart';
import '../../widgets/transaction_confirmation_dialog.dart';

class SendPage extends ConsumerStatefulWidget {
  const SendPage({super.key, this.initialCoin, this.initialAddress});

  final String? initialCoin;
  final String? initialAddress;

  @override
  ConsumerState<SendPage> createState() => _SendPageState();
}

class _SendPageState extends ConsumerState<SendPage> {
  final WalletService _walletService = WalletService();
  final TransactionService _transactionService = TransactionService();
  final BlockchainService _blockchainService = BlockchainService();
  final BiometricAuthService _biometricService = BiometricAuthService();
  final PinAuthService _pinAuthService = PinAuthService();
  final NotificationService _notificationService = NotificationService();
  final SpendingLimitService _spendingLimitService = SpendingLimitService();
  final ConfirmationTrackerService _confirmationTracker = ConfirmationTrackerService();
  
  final TextEditingController _amountController = TextEditingController();
  final TextEditingController _addressController = TextEditingController();
  final TextEditingController _memoController = TextEditingController();
  
  String _selectedCoin = 'BTC';
  String? _myAddress;
  bool _loading = false;
  bool _validatingAddress = false;
  bool _balanceLoaded = false;
  double _availableBalance = 0.0;
  double _fee = 0.0;
  Map<String, double> _cachedBalances = {};
  Map<String, double> _cachedFees = {};
  
  // USD input mode
  bool _useUsdInput = false;
  double _currentCryptoPrice = 0.0; // Current price in USD
  Map<String, double> _cachedPrices = {}; // Cache crypto prices

  final List<String> _supportedCoins = [
    'BTC', 'ETH', 'BNB', 'USDT-ERC20', 'USDT-BEP20', 'USDT-TRC20',
    'TRX', 'XRP', 'SOL', 'LTC', 'DOGE'
  ];

  @override
  void initState() {
    super.initState();
    _selectedCoin = widget.initialCoin ?? 'BTC';
    _addressController.text = widget.initialAddress ?? '';
    _loadBalance();
    _loadCryptoPrice(); // Load price immediately on page load
  }

  Future<void> _loadBalance({bool forceRefresh = false}) async {
    // Use cached balance if available and not forcing refresh
    if (!forceRefresh && _cachedBalances.containsKey(_selectedCoin)) {
      setState(() {
        _availableBalance = _cachedBalances[_selectedCoin]!;
        _fee = _cachedFees[_selectedCoin]!;
        _balanceLoaded = true;
      });
      return;
    }

    try {
      // Get stored addresses for this coin
      final addresses = await _walletService.getStoredAddresses(_selectedCoin);
      if (addresses.isNotEmpty) {
        _myAddress = addresses.first;
        // Get real balance from blockchain
        final balance = await _blockchainService.getBalance(_selectedCoin, _myAddress!);
        final fee = await _calculateRealFee();
        
        setState(() {
          _availableBalance = balance;
          _fee = fee;
          _cachedBalances[_selectedCoin] = balance;
          _cachedFees[_selectedCoin] = fee;
          _balanceLoaded = true;
        });
      } else {
        final fee = await _calculateRealFee();
        setState(() {
          _availableBalance = 0.0;
          _fee = fee;
          _cachedBalances[_selectedCoin] = 0.0;
          _cachedFees[_selectedCoin] = fee;
          _balanceLoaded = true;
        });
      }
    } catch (e) {
      print('Error loading balance: $e');
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
      // Get real fee estimation from blockchain service
      return await _blockchainService.getFeeEstimate(_selectedCoin);
    } catch (e) {
      print('Error getting fee estimate, using fallback: $e');
      // Fallback to mock fee calculation
      switch (_selectedCoin) {
        case 'BTC':
          return 0.0001;
        case 'ETH':
        case 'BNB':
          return 0.001;
        case 'USDT-ERC20':
        case 'USDT-BEP20':
          return 0.005;
        case 'USDT-TRC20':
          return 1.0; // TRX for energy
        case 'XRP':
          return 0.00001;
        case 'SOL':
          return 0.000005;
        case 'LTC':
          return 0.001;
        case 'DOGE':
          return 1.0;
        default:
          return 0.001;
      }
    }
  }


  void _onCoinChanged(String? coin) {
    if (coin != null) {
      // Clear any existing snackbars/toasts
      if (mounted) {
        ScaffoldMessenger.of(context).clearSnackBars();
      }
      setState(() {
        _selectedCoin = coin;
        _balanceLoaded = false;
      });
      _loadBalance();
    }
  }

  void _setMaxAmount() {
    final total = _availableBalance - _fee;
    if (total > 0) {
      if (_useUsdInput && _currentCryptoPrice > 0) {
        // Set max in USD
        _amountController.text = (total * _currentCryptoPrice).toStringAsFixed(2);
      } else {
        // Set max in crypto
        _amountController.text = total.toStringAsFixed(8);
      }
    }
  }

  // Load current crypto price from backend
  void _loadCryptoPrice() {
    // Check cache first
    if (_cachedPrices.containsKey(_selectedCoin)) {
      setState(() {
        _currentCryptoPrice = _cachedPrices[_selectedCoin]!;
      });
      return;
    }

    // Use instant approximate values (no API call needed)
    final prices = {
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
      'USDT-TRC20': 1.0,
    };
    
    setState(() {
      _currentCryptoPrice = prices[_selectedCoin] ?? 0.0;
      _cachedPrices[_selectedCoin] = _currentCryptoPrice;
    });
  }

  // Convert USD to crypto amount
  double _convertUsdToCrypto(double usdAmount) {
    if (_currentCryptoPrice == 0) return 0.0;
    return usdAmount / _currentCryptoPrice;
  }

  // Convert crypto to USD amount
  double _convertCryptoToUsd(double cryptoAmount) {
    return cryptoAmount * _currentCryptoPrice;
  }

  // Get the actual crypto amount to send (handles USD conversion)
  double _getActualCryptoAmount() {
    final inputAmount = double.tryParse(_amountController.text) ?? 0.0;
    if (_useUsdInput) {
      return _convertUsdToCrypto(inputAmount);
    }
    return inputAmount;
  }

  bool get _isFormValid {
    final inputAmount = double.tryParse(_amountController.text) ?? 0;
    final cryptoAmount = _getActualCryptoAmount();
    final address = _addressController.text.trim();
    return inputAmount > 0 &&
           cryptoAmount > 0 &&
           cryptoAmount <= (_availableBalance - _fee) &&
           address.isNotEmpty &&
           _validateAddressFormat(address);
  }

  bool _validateAddressFormat(String address) {
    // Basic format validation - in a real app, use blockchain service validation
    switch (_selectedCoin) {
      case 'BTC':
        return address.startsWith('1') || address.startsWith('3') || address.startsWith('bc1');
      case 'ETH':
      case 'BNB':
      case 'USDT-ERC20':
      case 'USDT-BEP20':
        return address.startsWith('0x') && address.length == 42;
      case 'TRX':
      case 'USDT-TRC20':
        return address.startsWith('T') && address.length == 34;
      case 'XRP':
        return address.startsWith('r') && address.length >= 25 && address.length <= 35;
      case 'SOL':
        return address.length >= 32 && address.length <= 44;
      case 'LTC':
        return address.startsWith('L') || address.startsWith('M') || address.startsWith('ltc1');
      case 'DOGE':
        return address.startsWith('D') || address.startsWith('A');
      default:
        return address.length >= 26 && address.length <= 64;
    }
  }

  /// Estimate USD value of transaction
  /// In production, this should call a real-time price API
  Future<double> _estimateUSDValue(double amount, String coin) async {
    // Approximate prices (in production, fetch from CoinGecko/CoinMarketCap API)
    final Map<String, double> approximatePrices = {
      'BTC': 45000.0,
      'ETH': 2500.0,
      'BNB': 300.0,
      'USDT-ERC20': 1.0,
      'USDT-BEP20': 1.0,
      'USDT-TRC20': 1.0,
      'TRX': 0.10,
      'XRP': 0.60,
      'SOL': 100.0,
      'LTC': 70.0,
      'DOGE': 0.08,
    };
    
    final price = approximatePrices[coin] ?? 0.0;
    return amount * price;
  }

  Future<void> _sendTransaction() async {
    if (!_isFormValid) return;

    // Step 1: Require authentication
    print('🔐 Starting authentication check...');
    
    // First check if biometric is available and enabled
    final isBiometricAvailable = await _pinAuthService.isBiometricAvailable();
    final isBiometricEnabled = await _pinAuthService.isBiometricEnabled();
    
    bool authenticated = false;
    
    if (isBiometricAvailable && isBiometricEnabled) {
      // Try biometric authentication first
      authenticated = await _biometricService.authenticateWithBiometrics(
        reason: 'Authenticate to send transaction',
      );
      print('🔐 Biometric authentication returned: $authenticated');
    }
    
    if (!authenticated) {
      // Try PIN authentication
      final pinSet = await _pinAuthService.isPinSet();
      print('🔐 isPINSet: $pinSet');
      
      if (!pinSet) {
        // No authentication method set up - show warning
        print('❌ No PIN set - showing warning');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Please set up PIN or biometric authentication in Settings'),
              backgroundColor: Colors.orange,
            ),
          );
        }
        return;
      }
      print('✅ PIN is set - showing PIN dialog');

      // Show PIN dialog
      if (mounted) {
        authenticated = await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (context) => const PINVerificationDialog(
            title: 'Authenticate',
            subtitle: 'Enter your PIN to send transaction',
          ),
        ) ?? false;
      }

      // Check if widget is still mounted after dialog closes (context may be disposed)
      if (!mounted) {
        print('⚠️ Widget disposed after PIN dialog, aborting send');
        return;
      }

      if (!authenticated) {
        print('❌ PIN authentication failed or cancelled');
        return;
      }
      print('✅ PIN authentication successful');
    }

    // Step 2: Check spending limits
    final cryptoAmount = _getActualCryptoAmount(); // Get actual crypto amount (handles USD conversion)
    
    // Get approximate USD value for spending limit check
    // Note: In production, you'd get real-time price from an API
    final approximateUSD = await _estimateUSDValue(cryptoAmount, _selectedCoin);
    
    final spendingValidation = await _spendingLimitService.validateTransaction(approximateUSD);
    
    if (!spendingValidation.isAllowed) {
      // Transaction exceeds daily limit
      if (mounted) {
        await showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Daily Limit Exceeded'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(spendingValidation.message),
                const SizedBox(height: 16),
                Text('Current Spending: \$${spendingValidation.currentSpending.toStringAsFixed(2)}'),
                Text('Daily Limit: \$${spendingValidation.dailyLimit.toStringAsFixed(2)}'),
                Text('This Transaction: \$${spendingValidation.attemptedAmount.toStringAsFixed(2)}'),
                Text('Excess Amount: \$${spendingValidation.excessAmount.toStringAsFixed(2)}'),
                const SizedBox(height: 8),
                Text(
                  'Limit resets at midnight UTC',
                  style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('OK'),
              ),
            ],
          ),
        );
      }
      return;
    } else if (spendingValidation.isWarning) {
      // Show warning but allow to proceed
      if (mounted) {
        final proceed = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Spending Limit Warning'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(spendingValidation.message),
                const SizedBox(height: 16),
                Text('Current Spending: \$${spendingValidation.currentSpending.toStringAsFixed(2)}'),
                Text('Daily Limit: \$${spendingValidation.dailyLimit.toStringAsFixed(2)}'),
                Text('After This Transaction: \$${(spendingValidation.currentSpending + spendingValidation.attemptedAmount).toStringAsFixed(2)}'),
                Text('Remaining After: \$${spendingValidation.remainingLimit.toStringAsFixed(2)}'),
                const SizedBox(height: 8),
                Text(
                  'Do you want to proceed?',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('Proceed'),
              ),
            ],
          ),
        ) ?? false;
        
        if (!proceed) {
          return;
        }
      }
    }

    // Step 3: Show transaction confirmation dialog
    final address = _addressController.text.trim();
    final total = cryptoAmount + _fee;

    if (mounted) {
      final confirmed = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (context) => TransactionConfirmationDialog(
          recipientAddress: address,
          amount: cryptoAmount.toStringAsFixed(8),
          coin: _selectedCoin,
          networkFee: '$_fee $_selectedCoin',
          estimatedTotal: '${total.toStringAsFixed(8)} $_selectedCoin',
          onConfirm: () {},
        ),
      ) ?? false;

      if (!confirmed) {
        return;
      }
    }

    // Step 3: Execute transaction
    setState(() => _loading = true);
    try {
      final memo = _memoController.text.trim();

      // Validate address with blockchain service
      final isAddressValid = await _blockchainService.validateAddress(_selectedCoin, address);
      if (!isAddressValid) {
        throw Exception('Invalid address for $_selectedCoin');
      }

      // Send real transaction using blockchain service
      final txHash = await _blockchainService.sendTransaction(
        coin: _selectedCoin,
        fromAddress: _myAddress!,
        toAddress: address,
        amount: cryptoAmount,
        fee: _fee,
        memo: memo.isNotEmpty ? memo : null,
      );

      // Optimistically deduct balance (amount + fee) so user sees immediate update
      final optimisticDeduction = cryptoAmount + _fee;
      setState(() {
        _availableBalance = (_availableBalance - optimisticDeduction);
        _cachedBalances[_selectedCoin] = _availableBalance;
      });

      // Record the sent transaction locally as pending (include txHash)
      await _transactionService.recordSentTransaction(
        coin: _selectedCoin,
        amount: cryptoAmount,
        toAddress: address,
        fromAddress: _myAddress,
        fee: _fee,
        memo: memo.isNotEmpty ? memo : null,
        txHash: txHash,
      );

      // Record spending for daily limit tracking
      await _spendingLimitService.recordTransaction(approximateUSD);

      // Start tracking transaction confirmations
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

      // Note: ConfirmationTrackerService will update notification status as confirmations arrive

      // Show success message with transaction hash
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Successfully sent ${cryptoAmount.toStringAsFixed(8)} $_selectedCoin'),
                const SizedBox(height: 4),
                Text(
                  'TX: ${txHash.substring(0, 16)}...',
                  style: const TextStyle(fontSize: 12),
                ),
              ],
            ),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 5),
          ),
        );
      }

      // Clear form and refresh balance
      _amountController.clear();
      _addressController.clear();
      _memoController.clear();
      
      // Refresh balance to show updated amount
      _loadBalance(forceRefresh: true);

      // Navigate back or to transactions page
      if (mounted) {
        context.go('/transactions');
      }

    } catch (e) {
      // Show failure notification
      await _notificationService.showNotification(
        title: 'Transaction Failed',
        message: 'Failed to send $_selectedCoin: ${e.toString().length > 50 ? e.toString().substring(0, 50) + "..." : e.toString()}',
        type: NotificationType.failed,
        data: {
          'type': 'failed',
          'coin': _selectedCoin,
          'error': e.toString(),
        },
      );

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to send transaction: $e'),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 5),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  void _showConfirmationDialog() {
    final amount = double.tryParse(_amountController.text) ?? 0;
    final address = _addressController.text.trim();
    final memo = _memoController.text.trim();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Confirm Transaction'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildConfirmationRow('Coin', _selectedCoin),
            _buildConfirmationRow('Amount', '$amount $_selectedCoin'),
            _buildConfirmationRow('To Address', address),
            _buildConfirmationRow('Network Fee', '$_fee $_selectedCoin'),
            _buildConfirmationRow('Total', '${amount + _fee} $_selectedCoin'),
            if (memo.isNotEmpty) _buildConfirmationRow('Memo', memo),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _sendTransaction();
            },
            child: const Text('Confirm & Send'),
          ),
        ],
      ),
    );
  }

  Widget _buildConfirmationRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 80,
            child: Text(
              label,
              style: AppTheme.bodyMedium.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: AppTheme.bodyMedium,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final amount = double.tryParse(_amountController.text) ?? 0;
    final total = amount + _fee;

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go('/dashboard'),
        ),
        title: const Text('Send'),
        actions: [
          IconButton(
            icon: const Icon(Icons.history),
            onPressed: () => context.go('/transactions'),
            tooltip: 'View Transaction History',
          ),
        ],
      ),
      body: SingleChildScrollView(
              padding: const EdgeInsets.all(AppConstants.defaultPadding),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Coin Selection
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Select Coin',
                            style: AppTheme.titleMedium.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 12),
                          DropdownButtonFormField<String>(
                            value: _selectedCoin,
                            items: _supportedCoins.map((coin) {
                              return DropdownMenuItem(
                                value: coin,
                                child: Text(coin),
                              );
                            }).toList(),
                            onChanged: _onCoinChanged,
                            decoration: const InputDecoration(
                              border: OutlineInputBorder(),
                              contentPadding: EdgeInsets.symmetric(horizontal: 12),
                            ),
                          ),
                          if (!_balanceLoaded)
                            const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 16),

                  // Balance Information
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Balance',
                            style: AppTheme.titleMedium.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 8),
                          _balanceLoaded
                              ? Text(
                                  '$_availableBalance $_selectedCoin',
                                  style: AppTheme.headlineSmall.copyWith(
                                    fontWeight: FontWeight.w700,
                                  ),
                                )
                              : Container(
                                  width: 120,
                                  height: 24,
                                  decoration: BoxDecoration(
                                    color: Theme.of(context).colorScheme.surface,
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Center(
                                    child: Text(
                                      'Loading...',
                                      style: AppTheme.bodyMedium.copyWith(
                                        color: Theme.of(context).colorScheme.onSurface.withAlpha(150),
                                      ),
                                    ),
                                  ),
                                ),
                          const SizedBox(height: 8),
                          Text(
                            'Available to send',
                            style: AppTheme.bodyMedium.copyWith(
                              color: Theme.of(context).colorScheme.onSurface.withAlpha(150),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 16),

                  // Amount Input
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                'Amount',
                                style: AppTheme.titleMedium.copyWith(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              Row(
                                children: [
                                  // USD/Crypto toggle
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: Colors.grey[200],
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
                                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                            decoration: BoxDecoration(
                                              color: !_useUsdInput ? Colors.blue : Colors.transparent,
                                              borderRadius: BorderRadius.circular(15),
                                            ),
                                            child: Text(
                                              _selectedCoin,
                                              style: TextStyle(
                                                color: !_useUsdInput ? Colors.white : Colors.black87,
                                                fontWeight: FontWeight.w600,
                                                fontSize: 12,
                                              ),
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 4),
                                        GestureDetector(
                                          onTap: () {
                                            // Load price when switching to USD mode (instant)
                                            if (!_useUsdInput) {
                                              _loadCryptoPrice();
                                            }
                                            setState(() {
                                              _useUsdInput = true;
                                              _amountController.clear();
                                            });
                                          },
                                          child: Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                            decoration: BoxDecoration(
                                              color: _useUsdInput ? Colors.blue : Colors.transparent,
                                              borderRadius: BorderRadius.circular(15),
                                            ),
                                            child: Text(
                                              'USD',
                                              style: TextStyle(
                                                color: _useUsdInput ? Colors.white : Colors.black87,
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
                                  TextButton(
                                    onPressed: _setMaxAmount,
                                    child: const Text('MAX'),
                                  ),
                                ],
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          TextField(
                            controller: _amountController,
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            inputFormatters: InputValidator.amountFormatters(maxDecimals: _useUsdInput ? 2 : 8),
                            decoration: InputDecoration(
                              border: const OutlineInputBorder(),
                              hintText: _useUsdInput ? '0.00' : '0.00000000',
                              prefixText: _useUsdInput ? '\$ ' : '',
                              suffixText: _useUsdInput ? null : _selectedCoin,
                              suffixStyle: AppTheme.bodyMedium.copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                              errorText: _amountController.text.isNotEmpty
                                  ? InputValidator.validateAmount(
                                      _amountController.text,
                                      maxAmount: _useUsdInput 
                                        ? _availableBalance * _currentCryptoPrice 
                                        : _availableBalance,
                                      maxDecimals: _useUsdInput ? 2 : 8,
                                    )
                                  : null,
                            ),
                            onChanged: (_) => setState(() {}),
                          ),
                          // Show conversion
                          if (_amountController.text.isNotEmpty && _currentCryptoPrice > 0)
                            Padding(
                              padding: const EdgeInsets.only(top: 8),
                              child: Text(
                                _useUsdInput
                                    ? '≈ ${_convertUsdToCrypto(double.tryParse(_amountController.text) ?? 0).toStringAsFixed(8)} $_selectedCoin'
                                    : '≈ \$${_convertCryptoToUsd(double.tryParse(_amountController.text) ?? 0).toStringAsFixed(2)} USD',
                                style: AppTheme.bodySmall.copyWith(
                                  color: Colors.grey[600],
                                  fontStyle: FontStyle.italic,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 16),

                  // Address Input
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Recipient Address',
                            style: AppTheme.titleMedium.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 12),
                          TextField(
                            controller: _addressController,
                            inputFormatters: InputValidator.addressFormatters(),
                            decoration: InputDecoration(
                              border: const OutlineInputBorder(),
                              hintText: 'Enter wallet address',
                              errorText: _addressController.text.isNotEmpty
                                  ? InputValidator.validateAddress(
                                      _addressController.text,
                                      _selectedCoin,
                                    )
                                  : null,
                            ),
                            maxLines: 2,
                            onChanged: (_) => setState(() {}),
                          ),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 16),

                  // Memo Input (Optional)
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Memo (Optional)',
                            style: AppTheme.titleMedium.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 12),
                          TextField(
                            controller: _memoController,
                            decoration: InputDecoration(
                              border: const OutlineInputBorder(),
                              hintText: 'Add a note for this transaction',
                              errorText: InputValidator.validateMemo(
                                _memoController.text,
                                maxLength: 256,
                              ),
                            ),
                            maxLines: 2,
                            onChanged: (_) => setState(() {}),
                          ),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 24),

                  // Transaction Summary
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Transaction Summary',
                            style: AppTheme.titleMedium.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 12),
                          _buildSummaryRow('Amount', '$amount $_selectedCoin'),
                          _buildSummaryRow('Network Fee', '$_fee $_selectedCoin'),
                          const Divider(),
                          _buildSummaryRow(
                            'Total',
                            '$total $_selectedCoin',
                            isBold: true,
                          ),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 32),

                  // Send Button
                  ElevatedButton(
                    onPressed: _isFormValid && !_loading ? _showConfirmationDialog : null,
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                    child: _loading
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                            ),
                          )
                        : const Text(
                            'Send',
                            style: TextStyle(fontSize: 16),
                          ),
                  ),

                  const SizedBox(height: 16),
                ],
              ),
            ),
    );
  }

  Widget _buildSummaryRow(String label, String value, {bool isBold = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: AppTheme.bodyMedium.copyWith(
              color: Theme.of(context).colorScheme.onSurface.withAlpha(150),
            ),
          ),
          Text(
            value,
            style: isBold
                ? AppTheme.bodyMedium.copyWith(fontWeight: FontWeight.w600)
                : AppTheme.bodyMedium,
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _amountController.dispose();
    _addressController.dispose();
    _memoController.dispose();
    super.dispose();
  }
}