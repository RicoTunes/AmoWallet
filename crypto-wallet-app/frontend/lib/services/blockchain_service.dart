import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:web3dart/web3dart.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:pointycastle/digests/sha256.dart';
import 'package:base58check/base58check.dart' as base58check;
import 'package:hex/hex.dart';
import '../core/config/api_config.dart';

class BlockchainService {
  final Dio _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 10),
    receiveTimeout: const Duration(seconds: 15),
    sendTimeout: const Duration(seconds: 10),
  ));
  // Configure Android options for better compatibility
  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage(
    aOptions: AndroidOptions(
      encryptedSharedPreferences: true,
    ),
  );

  // Blockchain API endpoints
  static const Map<String, String> _apiEndpoints = {
    'BTC': 'https://blockstream.info/api',
    'ETH':
        'https://mainnet.infura.io/v3/ecba451c1c7d4a659088b8a182b559f3', // Replace with actual key
    'BNB': 'https://bsc-dataseed.binance.org',
    'LTC': 'https://api.blockcypher.com/v1/ltc/main',
    'DOGE': 'https://api.blockcypher.com/v1/doge/main',
    'TRX': 'https://api.trongrid.io',
    'XRP': 'https://s1.ripple.com:51234',
    'SOL': 'https://api.mainnet-beta.solana.com',
  };

  // For demo purposes, we'll use public APIs that don't require keys
  static const Map<String, String> _publicApis = {
    'BTC': 'https://blockstream.info/api',
    'ETH': 'https://api.etherscan.io/api',
    'BNB': 'https://api.bscscan.com/api',
    'LTC': 'https://api.blockcypher.com/v1/ltc/main',
    'DOGE': 'https://api.blockcypher.com/v1/doge/main',
    'TRX': 'https://apilist.tronscan.org/api',
    'XRP': 'https://s1.ripple.com:51234',
    'SOL': 'https://api.mainnet-beta.solana.com',
  };

  /// Get balance for a specific coin/token and address
  Future<double> getBalance(String coin, String address) async {
    try {
      // Check if it's a token (contains '-')
      if (coin.contains('-')) {
        final parts = coin.split('-');
        final network = parts[1];
        final token = parts[0];

        switch (network) {
          case 'ERC20':
            return await _getTokenBalance(token, address, 'ethereum');
          case 'BEP20':
            return await _getTokenBalance(token, address, 'bsc');
          case 'TRC20':
            return await _getTokenBalance(token, address, 'tron');
          default:
            return 0.0;
        }
      }

      // Native coins
      switch (coin) {
        case 'BTC':
          return await _getBitcoinBalance(address);
        case 'ETH':
          return await _getEthereumBalance(address);
        case 'BNB':
          return await _getBscBalance(address);
        case 'LTC':
          return await _getLitecoinBalance(address);
        case 'DOGE':
          return await _getDogecoinBalance(address);
        case 'TRX':
          return await _getTronBalance(address);
        case 'XRP':
          return await _getRippleBalance(address);
        case 'SOL':
          return await _getSolanaBalance(address);
        default:
          return 0.0;
      }
    } catch (e) {
      print('Error getting balance for $coin: $e');
      return 0.0;
    }
  }

  /// Get token balance for supported networks
  Future<double> _getTokenBalance(
      String token, String address, String network) async {
    // Common token contract addresses
    final tokenContracts = {
      'ethereum': {
        'USDT': '0xdAC17F958D2ee523a2206206994597C13D831ec7',
        'USDC': '0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48',
        'WBTC': '0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599',
        'DAI': '0x6B175474E89094C44Da98b954EedeAC495271d0F',
      },
      'bsc': {
        'USDT': '0x55d398326f99059fF775485246999027B3197955',
        'USDC': '0x8AC76a51cc950d9822D68b83fE1Ad97B32Cd580d',
        'BUSD': '0xe9e7CEA3DedcA5984780Bafc599bD69ADd087D56',
      },
      'tron': {
        'USDT': 'TR7NHqjeKQxGTCi8q8ZY4pL8otSzgjLj6t',
        'USDC': 'TEkxiTehnzSmSe2XqrBj4w32RUN966rdz8',
      }
    };

    final contractAddress = tokenContracts[network]?[token];
    if (contractAddress == null) return 0.0;

    try {
      switch (network) {
        case 'ethereum':
          return await getErc20TokenBalance(
              address, contractAddress, 6); // USDT has 6 decimals
        case 'bsc':
          return await getBep20TokenBalance(
              address, contractAddress, 18); // Most BEP20 have 18
        case 'tron':
          return await getTrc20TokenBalance(address, contractAddress);
        default:
          return 0.0;
      }
    } catch (e) {
      print('Error getting $token balance on $network: $e');
      return 0.0;
    }
  }

  /// Get Bitcoin balance
  Future<double> _getBitcoinBalance(String address) async {
    try {
      // Use backend API instead of Blockstream
      final response = await _dio
          .get('${ApiConfig.baseUrl}/api/blockchain/balance/BTC/$address');
      final data = response.data;

      if (data is Map && data['success'] == true) {
        final balance =
            double.tryParse(data['balance']?.toString() ?? '0') ?? 0.0;
        return balance;
      }

      return 0.0;
    } catch (e) {
      print('Error fetching Bitcoin balance: $e');
      return 0.0;
    }
  }

  /// Get Ethereum balance
  Future<double> _getEthereumBalance(String address) async {
    try {
      // Try multiple APIs for reliability

      // Method 1: Use Infura JSON-RPC
      try {
        final infuraResponse = await _dio.post(
          'https://mainnet.infura.io/v3/ecba451c1c7d4a659088b8a182b559f3',
          data: {
            'jsonrpc': '2.0',
            'method': 'eth_getBalance',
            'params': [address, 'latest'],
            'id': 1,
          },
        );

        if (infuraResponse.data != null &&
            infuraResponse.data['result'] != null) {
          final hexBalance = infuraResponse.data['result'] as String;
          final balanceWei = BigInt.parse(hexBalance.substring(2), radix: 16);
          final balanceEth = balanceWei.toDouble() / 1e18;
          print('✅ ETH balance from Infura: $balanceEth');
          return balanceEth;
        }
      } catch (e) {
        print('Infura failed, trying Etherscan: $e');
      }

      // Method 2: Use Etherscan public API (no key needed for basic queries)
      try {
        final response = await _dio.get(
            'https://api.etherscan.io/api?module=account&action=balance&address=$address&tag=latest');
        final data = response.data;

        if (data is Map && data['status'] == '1') {
          final balanceWei = BigInt.parse(data['result']);
          final balanceEth = balanceWei.toDouble() / 1e18;
          print('✅ ETH balance from Etherscan: $balanceEth');
          return balanceEth;
        }
      } catch (e) {
        print('Etherscan failed: $e');
      }

      // Method 3: Use Cloudflare Ethereum Gateway
      try {
        final cfResponse = await _dio.post(
          'https://cloudflare-eth.com',
          data: {
            'jsonrpc': '2.0',
            'method': 'eth_getBalance',
            'params': [address, 'latest'],
            'id': 1,
          },
        );

        if (cfResponse.data != null && cfResponse.data['result'] != null) {
          final hexBalance = cfResponse.data['result'] as String;
          final balanceWei = BigInt.parse(hexBalance.substring(2), radix: 16);
          final balanceEth = balanceWei.toDouble() / 1e18;
          print('✅ ETH balance from Cloudflare: $balanceEth');
          return balanceEth;
        }
      } catch (e) {
        print('Cloudflare failed: $e');
      }

      return 0.0;
    } catch (e) {
      print('Error fetching Ethereum balance: $e');
      return 0.0;
    }
  }

  /// Get ERC20 token balance (USDT, USDC, etc.)
  Future<double> getErc20TokenBalance(
      String address, String contractAddress, int decimals) async {
    try {
      final response = await _dio.get(
          '${_publicApis['ETH']}?module=account&action=tokenbalance&contractaddress=$contractAddress&address=$address&tag=latest&apikey=YourApiKeyToken');
      final data = response.data;

      if (data is Map && data['status'] == '1') {
        final balanceWei = BigInt.parse(data['result']);
        final balance = balanceWei / BigInt.from(10).pow(decimals);
        return balance.toDouble();
      }

      return 0.0;
    } catch (e) {
      print('Error fetching ERC20 token balance: $e');
      return 0.0;
    }
  }

  /// Get BEP20 token balance (BSC USDT, etc.)
  Future<double> getBep20TokenBalance(
      String address, String contractAddress, int decimals) async {
    try {
      final response = await _dio.get(
          '${_publicApis['BNB']}?module=account&action=tokenbalance&contractaddress=$contractAddress&address=$address&tag=latest&apikey=YourApiKeyToken');
      final data = response.data;

      if (data is Map && data['status'] == '1') {
        final balanceWei = BigInt.parse(data['result']);
        final balance = balanceWei / BigInt.from(10).pow(decimals);
        return balance.toDouble();
      }

      return 0.0;
    } catch (e) {
      print('Error fetching BEP20 token balance: $e');
      return 0.0;
    }
  }

  /// Get TRC20 token balance (Tron USDT, etc.)
  Future<double> getTrc20TokenBalance(
      String address, String contractAddress) async {
    try {
      final cleanAddress =
          address.startsWith('T') ? address.substring(1) : address;
      final response = await _dio.get(
          '${_publicApis['TRX']}/token_trc20?contract=$contractAddress&account=$cleanAddress');
      final data = response.data;

      if (data is Map && data.containsKey('trc20_tokens')) {
        final tokens = data['trc20_tokens'];
        if (tokens is List && tokens.isNotEmpty) {
          for (final token in tokens) {
            if (token['tokenId'] == contractAddress) {
              final balance = double.parse(token['balance'] ?? '0');
              return balance / 1000000; // USDT on Tron has 6 decimals
            }
          }
        }
      }

      return 0.0;
    } catch (e) {
      print('Error fetching TRC20 token balance: $e');
      return 0.0;
    }
  }

  /// Get BSC balance
  Future<double> _getBscBalance(String address) async {
    try {
      final response = await _dio.get(
          '${_publicApis['BNB']}?module=account&action=balance&address=$address&tag=latest&apikey=YourApiKeyToken');
      final data = response.data;

      if (data is Map && data['status'] == '1') {
        final balanceWei = BigInt.parse(data['result']);
        final balanceBnb = balanceWei / BigInt.from(10).pow(18);
        return balanceBnb.toDouble();
      }

      return 0.0;
    } catch (e) {
      print('Error fetching BSC balance: $e');
      // Return 0 on error - only show real balances
      return 0.0;
    }
  }

  /// Get Litecoin balance
  Future<double> _getLitecoinBalance(String address) async {
    try {
      final response =
          await _dio.get('${_publicApis['LTC']}/addrs/$address/balance');
      final data = response.data;

      if (data is Map && data.containsKey('balance')) {
        final balance = data['balance'] / 100000000; // Convert satoshis to LTC
        return balance.toDouble();
      }

      return 0.0;
    } catch (e) {
      print('Error fetching Litecoin balance: $e');
      // Return 0 on error - only show real balances
      return 0.0;
    }
  }

  /// Get Dogecoin balance
  Future<double> _getDogecoinBalance(String address) async {
    try {
      final response =
          await _dio.get('${_publicApis['DOGE']}/addrs/$address/balance');
      final data = response.data;

      if (data is Map && data.containsKey('balance')) {
        final balance = data['balance'] / 100000000; // Convert satoshis to DOGE
        return balance.toDouble();
      }

      return 0.0;
    } catch (e) {
      print('Error fetching Dogecoin balance: $e');
      // Return 0 on error - only show real balances
      return 0.0;
    }
  }

  /// Get Tron balance
  Future<double> _getTronBalance(String address) async {
    try {
      // Remove the 'T' prefix if present
      final cleanAddress =
          address.startsWith('T') ? address.substring(1) : address;

      final response =
          await _dio.get('${_publicApis['TRX']}/account?address=$cleanAddress');
      final data = response.data;

      if (data is Map && data.containsKey('balance')) {
        final balanceSun = data['balance'];
        final balanceTrx = balanceSun / 1000000; // Convert SUN to TRX
        return balanceTrx.toDouble();
      }

      return 0.0;
    } catch (e) {
      print('Error fetching Tron balance: $e');
      // Return 0 on error - only show real balances
      return 0.0;
    }
  }

  /// Get Ripple balance
  Future<double> _getRippleBalance(String address) async {
    try {
      final payload = {
        "method": "account_info",
        "params": [
          {
            "account": address,
            "strict": true,
            "ledger_index": "current",
            "queue": true
          }
        ]
      };

      final response = await _dio.post(_publicApis['XRP']!,
          data: jsonEncode(payload),
          options: Options(headers: {'Content-Type': 'application/json'}));

      final data = response.data;

      if (data is Map &&
          data.containsKey('result') &&
          data['result']['status'] == 'success') {
        final balanceDrops = data['result']['account_data']['Balance'];
        final balanceXrp =
            int.parse(balanceDrops) / 1000000; // Convert drops to XRP
        return balanceXrp.toDouble();
      }

      return 0.0;
    } catch (e) {
      print('Error fetching Ripple balance: $e');
      // Return 0 on error - only show real balances
      return 0.0;
    }
  }

  /// Get Solana balance
  Future<double> _getSolanaBalance(String address) async {
    try {
      final payload = {
        "jsonrpc": "2.0",
        "id": 1,
        "method": "getBalance",
        "params": [address]
      };

      final response = await _dio.post(_publicApis['SOL']!,
          data: jsonEncode(payload),
          options: Options(headers: {'Content-Type': 'application/json'}));

      final data = response.data;

      if (data is Map && data.containsKey('result')) {
        final balanceLamports = data['result']['value'];
        final balanceSol =
            balanceLamports / 1000000000; // Convert lamports to SOL
        return balanceSol.toDouble();
      }

      return 0.0;
    } catch (e) {
      print('Error fetching Solana balance: $e');
      // Return 0 on error - only show real balances
      return 0.0;
    }
  }

  /// Get transaction history for an address
  Future<List<Map<String, dynamic>>> getTransactionHistory(
      String coin, String address) async {
    try {
      switch (coin) {
        case 'BTC':
          return await _getBitcoinTransactions(address);
        case 'ETH':
          return await _getEthereumTransactions(address);
        case 'BNB':
          return await _getBnbTransactions(address);
        // Add other coins as needed
        default:
          return [];
      }
    } catch (e) {
      print('Error getting transaction history for $coin: $e');
      return [];
    }
  }

  /// Get BNB/BSC transactions
  Future<List<Map<String, dynamic>>> _getBnbTransactions(String address) async {
    try {
      // Try backend API first
      try {
        final response = await _dio.get(
            '${ApiConfig.baseUrl}/api/blockchain/transactions/BNB/$address');
        final data = response.data;

        if (data is Map &&
            data['success'] == true &&
            data['transactions'] is List) {
          return (data['transactions'] as List).map((tx) {
            return {
              'hash': tx['hash'] ?? tx['txHash'] ?? '',
              'amount': double.tryParse(tx['amount']?.toString() ?? '0') ?? 0.0,
              'timestamp': tx['timestamp'] ??
                  DateTime.now().millisecondsSinceEpoch ~/ 1000,
              'confirmations': tx['confirmations'] ?? 0,
              'type': tx['type'] ?? 'unknown',
              'fromAddress': tx['fromAddress'] ?? tx['from'],
              'toAddress': tx['toAddress'] ?? tx['to'],
              'isPending': tx['isPending'] ?? false,
            };
          }).toList();
        }
      } catch (e) {
        print('Backend API failed, falling back to BscScan: $e');
      }

      // Fallback to BscScan
      final response = await _dio.get(
          '${_publicApis['BNB']}?module=account&action=txlist&address=$address&startblock=0&endblock=99999999&sort=desc&apikey=YourApiKeyToken');
      final data = response.data;

      if (data is Map && data['status'] == '1') {
        return (data['result'] as List)
            .take(20)
            .map<Map<String, dynamic>>((tx) {
          final valueWei =
              BigInt.tryParse(tx['value']?.toString() ?? '0') ?? BigInt.zero;
          final amount = valueWei.toDouble() / 1e18;
          return {
            'hash': tx['hash'],
            'amount': amount,
            'timestamp': int.tryParse(tx['timeStamp']?.toString() ?? '0') ?? 0,
            'confirmations':
                int.tryParse(tx['confirmations']?.toString() ?? '0') ?? 0,
            'type': tx['from'].toString().toLowerCase() == address.toLowerCase()
                ? 'sent'
                : 'received',
            'fromAddress': tx['from'],
            'toAddress': tx['to'],
          };
        }).toList();
      }

      return [];
    } catch (e) {
      print('Error fetching BNB transactions: $e');
      return [];
    }
  }

  /// Get Bitcoin transactions
  Future<List<Map<String, dynamic>>> _getBitcoinTransactions(
      String address) async {
    try {
      // Use backend API for transaction history
      final response = await _dio
          .get('${ApiConfig.baseUrl}/api/blockchain/transactions/BTC/$address');
      final data = response.data;

      if (data is Map &&
          data['success'] == true &&
          data['transactions'] is List) {
        return (data['transactions'] as List).map((tx) {
          return {
            'hash': tx['hash'] ?? tx['txid'] ?? '',
            'amount': double.tryParse(tx['amount']?.toString() ?? '0') ?? 0.0,
            'timestamp': tx['timestamp'] ??
                DateTime.now().millisecondsSinceEpoch ~/ 1000,
            'confirmations': tx['confirmations'] ?? 0,
            'type': tx['type'] ?? 'unknown',
            'fromAddress': tx['fromAddress'],
            'toAddress': tx['toAddress'],
            'isPending': tx['isPending'] ?? false,
          };
        }).toList();
      }

      return [];
    } catch (e) {
      print('Error fetching Bitcoin transactions: $e');
      return [];
    }
  }

  /// Calculate Bitcoin transaction amount for a specific address
  double _calculateBitcoinAmount(Map<String, dynamic> tx, String address) {
    try {
      double totalInput = 0.0;
      double totalOutput = 0.0;

      // Calculate inputs
      for (final input in tx['vin']) {
        if (input['prevout'] != null &&
            input['prevout']['scriptpubkey_address'] == address) {
          totalInput += (input['prevout']['value'] ?? 0) / 100000000;
        }
      }

      // Calculate outputs
      for (final output in tx['vout']) {
        if (output['scriptpubkey_address'] == address) {
          totalOutput += (output['value'] ?? 0) / 100000000;
        }
      }

      return totalOutput - totalInput;
    } catch (e) {
      return 0.0;
    }
  }

  /// Determine Bitcoin transaction type
  String _determineBitcoinTransactionType(
      Map<String, dynamic> tx, String address) {
    bool isSender = false;
    bool isReceiver = false;

    for (final input in tx['vin']) {
      if (input['prevout'] != null &&
          input['prevout']['scriptpubkey_address'] == address) {
        isSender = true;
      }
    }

    for (final output in tx['vout']) {
      if (output['scriptpubkey_address'] == address) {
        isReceiver = true;
      }
    }

    if (isSender && isReceiver) return 'self';
    if (isSender) return 'sent';
    if (isReceiver) return 'received';
    return 'unknown';
  }

  /// Get Ethereum transactions
  Future<List<Map<String, dynamic>>> _getEthereumTransactions(
      String address) async {
    try {
      // Try backend API first
      try {
        print('DEBUG ETH_TX: Trying backend API for $address');
        final response = await _dio.get(
            '${ApiConfig.baseUrl}/api/blockchain/transactions/ETH/$address');
        final data = response.data;
        print('DEBUG ETH_TX: Backend response: $data');

        if (data is Map &&
            data['success'] == true &&
            data['transactions'] is List) {
          final txList = (data['transactions'] as List).map((tx) {
            return {
              'hash': tx['hash'] ?? tx['txHash'] ?? '',
              'amount': double.tryParse(tx['amount']?.toString() ?? '0') ?? 0.0,
              'timestamp': tx['timestamp'] ??
                  DateTime.now().millisecondsSinceEpoch ~/ 1000,
              'confirmations': tx['confirmations'] ?? 0,
              'type': tx['type'] ?? 'unknown',
              'fromAddress': tx['fromAddress'] ?? tx['from'],
              'toAddress': tx['toAddress'] ?? tx['to'],
              'isPending': tx['isPending'] ?? false,
            };
          }).toList();
          print('DEBUG ETH_TX: Backend returned ${txList.length} transactions');
          return txList;
        }
      } catch (e) {
        print('DEBUG ETH_TX: Backend API failed: $e');
      }

      // Fallback to Etherscan
      print('DEBUG ETH_TX: Trying Etherscan fallback');
      final response = await _dio.get(
          '${_publicApis['ETH']}?module=account&action=txlist&address=$address&startblock=0&endblock=99999999&sort=desc&apikey=YourApiKeyToken');
      final data = response.data;
      print('DEBUG ETH_TX: Etherscan response status: ${data['status']}, message: ${data['message']}');

      if (data is Map && data['status'] == '1') {
        final txList = (data['result'] as List)
            .take(20)
            .map<Map<String, dynamic>>((tx) {
          final valueWei =
              BigInt.tryParse(tx['value']?.toString() ?? '0') ?? BigInt.zero;
          final amount = valueWei.toDouble() / 1e18;
          return {
            'hash': tx['hash'],
            'amount': amount,
            'timestamp': int.tryParse(tx['timeStamp']?.toString() ?? '0') ?? 0,
            'confirmations':
                int.tryParse(tx['confirmations']?.toString() ?? '0') ?? 0,
            'type': tx['from'].toString().toLowerCase() == address.toLowerCase()
                ? 'sent'
                : 'received',
            'fromAddress': tx['from'],
            'toAddress': tx['to'],
          };
        }).toList();
        print('DEBUG ETH_TX: Etherscan returned ${txList.length} transactions');
        return txList;
      }

      print('DEBUG ETH_TX: No transactions found');
      return [];
    } catch (e) {
      print('DEBUG ETH_TX: Error fetching Ethereum transactions: $e');
      return [];
    }
  }

  /// Get current gas price for Ethereum
  Future<BigInt> getEthereumGasPrice() async {
    try {
      final response = await _dio.get(
          '${_publicApis['ETH']}?module=proxy&action=eth_gasPrice&apikey=YourApiKeyToken');
      final data = response.data;

      if (data is Map && data.containsKey('result')) {
        return BigInt.parse(data['result'].replaceFirst('0x', ''), radix: 16);
      }

      return BigInt.from(20000000000); // Default 20 Gwei
    } catch (e) {
      return BigInt.from(20000000000);
    }
  }

  /// Validate address for a specific coin
  Future<bool> validateAddress(String coin, String address) async {
    try {
      switch (coin) {
        case 'BTC':
          return _validateBitcoinAddress(address);
        case 'ETH':
          return _validateEthereumAddress(address);
        case 'BNB':
          return _validateEthereumAddress(address); // BSC uses same format
        case 'LTC':
          return _validateLitecoinAddress(address);
        case 'DOGE':
          return _validateDogecoinAddress(address);
        case 'TRX':
          return _validateTronAddress(address);
        case 'XRP':
          return _validateRippleAddress(address);
        case 'SOL':
          return _validateSolanaAddress(address);
        default:
          return address.length >= 26 && address.length <= 64;
      }
    } catch (e) {
      return false;
    }
  }

  bool _validateBitcoinAddress(String address) {
    return address.startsWith('1') ||
        address.startsWith('3') ||
        address.startsWith('bc1');
  }

  bool _validateEthereumAddress(String address) {
    return address.startsWith('0x') && address.length == 42;
  }

  bool _validateLitecoinAddress(String address) {
    return address.startsWith('L') ||
        address.startsWith('M') ||
        address.startsWith('ltc1');
  }

  bool _validateDogecoinAddress(String address) {
    return address.startsWith('D') || address.startsWith('A');
  }

  bool _validateTronAddress(String address) {
    return address.startsWith('T') && address.length == 34;
  }

  bool _validateRippleAddress(String address) {
    return address.startsWith('r') &&
        address.length >= 25 &&
        address.length <= 35;
  }

  bool _validateSolanaAddress(String address) {
    return address.length >= 32 && address.length <= 44;
  }

  /// Get fee estimate for a specific coin
  Future<double> getFeeEstimate(String coin) async {
    try {
      switch (coin) {
        case 'BTC':
          return await _getBitcoinFeeEstimate();
        case 'ETH':
          return await _getEthereumFeeEstimate();
        case 'BNB':
          return await _getBscFeeEstimate();
        default:
          // Return mock fee for other coins
          return _getMockFeeEstimate(coin);
      }
    } catch (e) {
      print('Error getting fee estimate for $coin: $e');
      return _getMockFeeEstimate(coin);
    }
  }

  /// Get Bitcoin fee estimate
  Future<double> _getBitcoinFeeEstimate() async {
    try {
      final response =
          await _dio.get('https://mempool.space/api/v1/fees/recommended');
      final data = response.data;
      // Convert sat/vB to BTC for a typical transaction (226 vB)
      final feeRate = data['fastestFee'] ?? 20;
      return (feeRate * 226) / 100000000; // Convert to BTC
    } catch (e) {
      print('Error fetching Bitcoin fee: $e');
      return 0.0001; // Fallback fee
    }
  }

  /// Get Ethereum fee estimate
  Future<double> _getEthereumFeeEstimate() async {
    try {
      final gasPrice = await getEthereumGasPrice();
      // Typical gas limit for ETH transfer: 21000
      final gasLimit = BigInt.from(21000);
      final feeWei = gasPrice * gasLimit;
      return feeWei / BigInt.from(10).pow(18); // Convert to ETH
    } catch (e) {
      print('Error fetching Ethereum fee: $e');
      return 0.001; // Fallback fee
    }
  }

  /// Get BSC fee estimate
  Future<double> _getBscFeeEstimate() async {
    try {
      // BSC typically has lower fees than Ethereum
      final gasPrice = BigInt.from(5000000000); // 5 Gwei
      final gasLimit = BigInt.from(21000);
      final feeWei = gasPrice * gasLimit;
      return feeWei / BigInt.from(10).pow(18); // Convert to BNB
    } catch (e) {
      print('Error fetching BSC fee: $e');
      return 0.0005; // Fallback fee
    }
  }

  /// Get mock fee estimate for unsupported coins
  double _getMockFeeEstimate(String coin) {
    switch (coin) {
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

  /// Send transaction (simulated for demo)
  Future<String> sendTransaction({
    required String coin,
    required String fromAddress,
    required String toAddress,
    required double amount,
    required double fee,
    String? memo,
  }) async {
    try {
      print('🚀 Sending REAL $coin transaction...');
      print('📤 From: $fromAddress');
      print('📥 To: $toAddress');
      print('💰 Amount: $amount $coin');
      print('⛽ Fee: $fee $coin');

      // Get the private key from secure storage
      final storage = const FlutterSecureStorage();
      final privateKey =
          await storage.read(key: '${coin}_${fromAddress}_private');

      if (privateKey == null || privateKey.isEmpty) {
        throw Exception(
            'Private key not found. Cannot send transaction without private key.');
      }

      print('🔑 Private key found, preparing to send real transaction...');

      // Handle Bitcoin transactions differently
      if (coin == 'BTC') {
        print('🔵 Using Bitcoin-specific endpoint...');
        print('🔑 Sending private key in original format');

        final response = await _dio.post(
          '${ApiConfig.baseUrl}/api/blockchain/send/bitcoin',
          data: {
            'from': fromAddress,
            'to': toAddress,
            'amount': amount,
            'privateKeyWIF':
                privateKey, // Backend will handle hex or WIF format
            'fee': fee,
          },
        );

        if (response.data['success'] == true) {
          final txHash = response.data['txHash'];
          print('✅ Bitcoin transaction sent successfully!');
          print('📝 TX Hash: $txHash');
          print('🔗 Explorer: ${response.data['explorerUrl']}');
          return txHash;
        } else {
          throw Exception(
              response.data['error'] ?? 'Bitcoin transaction failed');
        }
      }

      // Handle Ethereum/BNB transactions
      if (['ETH', 'BNB'].contains(coin)) {
        // Send EVM transaction via backend API
        final response = await _dio.post(
          '${ApiConfig.baseUrl}/api/blockchain/send',
          data: {
            'network': coin,
            'from': fromAddress,
            'to': toAddress,
            'amount': amount,
            'privateKey': privateKey,
            'gasLimit': 21000,
            'memo': memo,
          },
        );

        if (response.data['success'] == true) {
          final txHash = response.data['txHash'];
          print('✅ Transaction sent successfully!');
          print('📝 TX Hash: $txHash');
          print('🔗 Explorer: ${response.data['explorerUrl']}');
          return txHash;
        } else {
          throw Exception(response.data['error'] ?? 'Transaction failed');
        }
      }
      
      // Handle Litecoin transactions
      if (coin == 'LTC') {
        print('🔵 Using Litecoin endpoint...');
        final response = await _dio.post(
          '${ApiConfig.baseUrl}/api/blockchain/send/litecoin',
          data: {
            'from': fromAddress,
            'to': toAddress,
            'amount': amount,
            'privateKeyWIF': privateKey,
          },
        );

        if (response.data['success'] == true) {
          final txHash = response.data['txHash'];
          print('✅ Litecoin transaction sent!');
          print('📝 TX Hash: $txHash');
          return txHash;
        } else {
          throw Exception(response.data['error'] ?? 'Litecoin transaction failed');
        }
      }
      
      // Handle Dogecoin transactions
      if (coin == 'DOGE') {
        print('🐕 Using Dogecoin endpoint...');
        final response = await _dio.post(
          '${ApiConfig.baseUrl}/api/blockchain/send/dogecoin',
          data: {
            'from': fromAddress,
            'to': toAddress,
            'amount': amount,
            'privateKeyWIF': privateKey,
          },
        );

        if (response.data['success'] == true) {
          final txHash = response.data['txHash'];
          print('✅ Dogecoin transaction sent!');
          print('📝 TX Hash: $txHash');
          return txHash;
        } else {
          throw Exception(response.data['error'] ?? 'Dogecoin transaction failed');
        }
      }
      
      // Handle Solana transactions
      if (coin == 'SOL') {
        print('☀️ Using Solana endpoint...');
        final response = await _dio.post(
          '${ApiConfig.baseUrl}/api/blockchain/send/solana',
          data: {
            'from': fromAddress,
            'to': toAddress,
            'amount': amount,
            'privateKey': privateKey,
          },
        );

        if (response.data['success'] == true) {
          final txHash = response.data['txHash'];
          print('✅ Solana transaction sent!');
          print('📝 TX Hash: $txHash');
          return txHash;
        } else {
          throw Exception(response.data['error'] ?? 'Solana transaction failed');
        }
      }
      
      // Handle TRON transactions
      if (coin == 'TRX') {
        print('⚡ Using TRON endpoint...');
        final response = await _dio.post(
          '${ApiConfig.baseUrl}/api/blockchain/send/tron',
          data: {
            'from': fromAddress,
            'to': toAddress,
            'amount': amount,
            'privateKey': privateKey,
          },
        );

        if (response.data['success'] == true) {
          final txHash = response.data['txHash'];
          print('✅ TRON transaction sent!');
          print('📝 TX Hash: $txHash');
          return txHash;
        } else {
          throw Exception(response.data['error'] ?? 'TRON transaction failed');
        }
      }
      
      // Handle XRP transactions
      if (coin == 'XRP') {
        print('💧 Using XRP endpoint...');
        final response = await _dio.post(
          '${ApiConfig.baseUrl}/api/blockchain/send/ripple',
          data: {
            'from': fromAddress,
            'to': toAddress,
            'amount': amount,
            'privateKey': privateKey,
          },
        );

        if (response.data['success'] == true) {
          final txHash = response.data['txHash'];
          print('✅ XRP transaction sent!');
          print('📝 TX Hash: $txHash');
          return txHash;
        } else {
          throw Exception(response.data['error'] ?? 'XRP transaction failed');
        }
      }

      throw Exception(
          '$coin transactions are not supported yet.');
    } catch (e) {
      print('❌ Error sending transaction: $e');

      // Provide user-friendly error messages
      if (e.toString().contains('Private key not found')) {
        throw Exception(
            'Cannot send transaction: Wallet not properly set up. Please import your wallet again.');
      } else if (e.toString().contains('INSUFFICIENT_FUNDS') ||
          e.toString().contains('Insufficient funds')) {
        throw Exception('Insufficient funds for transaction including fees.');
      } else if (e.toString().contains('INVALID_ARGUMENT')) {
        throw Exception(
            'Invalid transaction parameters. Please check the address and amount.');
      } else if (e.toString().contains('429')) {
        throw Exception(
            'Too many requests. Please wait a moment and try again.');
      } else if (e.toString().contains('No UTXOs available')) {
        throw Exception(
            'No confirmed Bitcoin available to send. Wait for your received transactions to confirm.');
      } else if (e.toString().contains('Private key does not match')) {
        throw Exception(
            'Wallet configuration error. Please re-import your wallet.');
      } else {
        throw Exception('Transaction failed: ${e.toString()}');
      }
    }
  }

  /// Get transaction confirmations from backend
  Future<Map<String, dynamic>> getTransactionConfirmations(
      String chain, String txHash) async {
    try {
      final response = await _dio.get(
        '${ApiConfig.baseUrl}/api/blockchain/confirmations/$chain/$txHash',
      );
      return response.data;
    } catch (e) {
      print('Error getting confirmations: $e');
      return {'confirmations': 0, 'status': 'unknown'};
    }
  }

  // Convert hex private key to WIF format for Bitcoin
  String _hexToWIF(String hexPrivateKey) {
    // Remove 0x prefix if present
    final cleanHex = hexPrivateKey.startsWith('0x')
        ? hexPrivateKey.substring(2)
        : hexPrivateKey;

    // Convert hex to bytes
    final privateKeyBytes = HEX.decode(cleanHex);

    // WIF format: version byte (0x80) + private key + compression flag (0x01) + checksum
    final versionByte = Uint8List.fromList([0x80]); // Mainnet private key
    final compressionFlag = Uint8List.fromList([0x01]); // Compressed public key

    // Combine: version + private key + compression
    final dataPayload = Uint8List.fromList([
      ...versionByte,
      ...privateKeyBytes,
      ...compressionFlag,
    ]);

    // Calculate checksum: first 4 bytes of double SHA256
    final sha256Digest = SHA256Digest();
    final firstHash = sha256Digest.process(dataPayload);
    final secondHash = sha256Digest.process(firstHash);
    final checksum = secondHash.sublist(0, 4);

    // Final payload: version + private key + compression + checksum
    final fullPayload = Uint8List.fromList([
      ...dataPayload,
      ...checksum,
    ]);

    // Base58 encode manually
    const String base58Chars =
        '123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz';
    String result = '';
    BigInt num = BigInt.parse(
        fullPayload.map((b) => b.toRadixString(16).padLeft(2, '0')).join(),
        radix: 16);

    while (num > BigInt.zero) {
      final remainder = num % BigInt.from(58);
      result = base58Chars[remainder.toInt()] + result;
      num = num ~/ BigInt.from(58);
    }

    // Add leading '1's for leading zeros
    for (final byte in fullPayload) {
      if (byte == 0) {
        result = '1$result';
      } else {
        break;
      }
    }

    return result;
  }
}
