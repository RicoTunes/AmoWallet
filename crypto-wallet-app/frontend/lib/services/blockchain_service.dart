import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../core/config/api_config.dart';

class BlockchainService {
  final Dio _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 30),
    receiveTimeout: const Duration(seconds: 90),
    sendTimeout: const Duration(seconds: 30),
  ));

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
        case 'USDT':
          // USDT is a token - check all networks where it might exist
          // Try ERC20 first (most common)
          double usdtBalance = 0.0;
          try {
            usdtBalance = await _getTokenBalance('USDT', address, 'ethereum');
            if (usdtBalance > 0) return usdtBalance;
          } catch (_) {}
          try {
            usdtBalance = await _getTokenBalance('USDT', address, 'bsc');
            if (usdtBalance > 0) return usdtBalance;
          } catch (_) {}
          try {
            usdtBalance = await _getTokenBalance('USDT', address, 'tron');
            if (usdtBalance > 0) return usdtBalance;
          } catch (_) {}
          return usdtBalance;
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

  /// Get Bitcoin balance with multiple fallback APIs for reliability
  Future<double> _getBitcoinBalance(String address) async {
    print('🔍 Fetching BTC balance for: $address');
    
    // Validate BTC address format
    if (address.isEmpty) {
      print('❌ Empty BTC address');
      return 0.0;
    }
    
    // Method 1: Try Blockstream API directly (fastest, most reliable)
    try {
      final blockstreamUrl = 'https://blockstream.info/api/address/$address';
      print('📡 Trying Blockstream: $blockstreamUrl');
      
      final response = await _dio.get(
        blockstreamUrl,
        options: Options(
          receiveTimeout: const Duration(seconds: 8),
          headers: {'Accept': 'application/json'},
        ),
      );
      
      if (response.data != null) {
        final data = response.data;
        // Blockstream returns balance in satoshis in chain_stats and mempool_stats
        final chainStats = data['chain_stats'] ?? {};
        final mempoolStats = data['mempool_stats'] ?? {};
        
        final funded = (chainStats['funded_txo_sum'] ?? 0) as int;
        final spent = (chainStats['spent_txo_sum'] ?? 0) as int;
        final mempoolFunded = (mempoolStats['funded_txo_sum'] ?? 0) as int;
        final mempoolSpent = (mempoolStats['spent_txo_sum'] ?? 0) as int;
        
        final totalSatoshis = (funded - spent) + (mempoolFunded - mempoolSpent);
        final balance = totalSatoshis / 100000000.0; // Convert satoshis to BTC
        
        print('✅ BTC balance from Blockstream: $balance BTC ($totalSatoshis sats)');
        return balance;
      }
    } catch (e) {
      print('⚠️ Blockstream failed: $e');
    }
    
    // Method 2: Try Mempool.space API
    try {
      final mempoolUrl = 'https://mempool.space/api/address/$address';
      print('📡 Trying Mempool.space: $mempoolUrl');
      
      final response = await _dio.get(
        mempoolUrl,
        options: Options(receiveTimeout: const Duration(seconds: 8)),
      );
      
      if (response.data != null) {
        final data = response.data;
        final chainStats = data['chain_stats'] ?? {};
        final mempoolStats = data['mempool_stats'] ?? {};
        
        final funded = (chainStats['funded_txo_sum'] ?? 0) as int;
        final spent = (chainStats['spent_txo_sum'] ?? 0) as int;
        final mempoolFunded = (mempoolStats['funded_txo_sum'] ?? 0) as int;
        final mempoolSpent = (mempoolStats['spent_txo_sum'] ?? 0) as int;
        
        final totalSatoshis = (funded - spent) + (mempoolFunded - mempoolSpent);
        final balance = totalSatoshis / 100000000.0;
        
        print('✅ BTC balance from Mempool.space: $balance BTC');
        return balance;
      }
    } catch (e) {
      print('⚠️ Mempool.space failed: $e');
    }
    
    // Method 3: Try BlockCypher API
    try {
      final blockcypherUrl = 'https://api.blockcypher.com/v1/btc/main/addrs/$address/balance';
      print('📡 Trying BlockCypher: $blockcypherUrl');
      
      final response = await _dio.get(
        blockcypherUrl,
        options: Options(receiveTimeout: const Duration(seconds: 8)),
      );
      
      if (response.data != null) {
        final data = response.data;
        final balanceSat = (data['balance'] ?? 0) as int;
        final unconfirmedSat = (data['unconfirmed_balance'] ?? 0) as int;
        final totalSatoshis = balanceSat + unconfirmedSat;
        final balance = totalSatoshis / 100000000.0;
        
        print('✅ BTC balance from BlockCypher: $balance BTC');
        return balance;
      }
    } catch (e) {
      print('⚠️ BlockCypher failed: $e');
    }
    
    // Method 4: Try backend API as last resort
    try {
      final response = await _dio.get(
        '${ApiConfig.baseUrl}/api/blockchain/balance/BTC/$address',
        options: Options(receiveTimeout: const Duration(seconds: 8)),
      );
      final data = response.data;

      if (data is Map && data['success'] == true) {
        final balance = double.tryParse(data['balance']?.toString() ?? '0') ?? 0.0;
        print('✅ BTC balance from backend: $balance BTC');
        return balance;
      }
    } catch (e) {
      print('⚠️ Backend API failed: $e');
    }

    print('❌ All BTC balance APIs failed for $address');
    return 0.0;
  }

  /// Get Ethereum balance with robust multi-API fallback
  Future<double> _getEthereumBalance(String address) async {
    debugPrint('🔄 Fetching ETH balance for: $address');
    
    // Format address properly (0x prefix, lowercase)
    final addr = _formatEthereumAddress(address);
    debugPrint('📍 Formatted address: $addr');
    
    // Method 1: Use backend proxy (Infura key stays server-side, never in APK)
    try {
      final backendResponse = await _dio.get(
        'https://amowallet-backend-production.up.railway.app/api/blockchain/balance/ETH/$addr',
        options: Options(receiveTimeout: const Duration(seconds: 10)),
      );

      debugPrint('📡 Infura response: ${backendResponse.statusCode} - ${backendResponse.data}');

      if (backendResponse.data != null && backendResponse.data['success'] == true) {
        final balance = (backendResponse.data['balance'] as num).toDouble();
        debugPrint('✅ ETH balance from Infura: $balance');
        return balance;
      }
    } catch (e) {
      debugPrint('⚠️ Backend ETH balance failed: $e');
    }

    // Method 2: Use Cloudflare Ethereum Gateway (fast, free)
    try {
      final cfResponse = await _dio.post(
        'https://cloudflare-eth.com',
        data: {
          'jsonrpc': '2.0',
          'method': 'eth_getBalance',
          'params': [addr, 'latest'],
          'id': 1,
        },
        options: Options(receiveTimeout: const Duration(seconds: 6)),
      );

      if (cfResponse.data != null && cfResponse.data['result'] != null) {
        final hexBalance = cfResponse.data['result'] as String;
        if (hexBalance.length > 2) {
          final balanceWei = BigInt.parse(hexBalance.substring(2), radix: 16);
          final balanceEth = balanceWei.toDouble() / 1e18;
          print('✅ ETH balance from Cloudflare: $balanceEth');
          return balanceEth;
        }
      }
    } catch (e) {
      print('⚠️ Cloudflare failed: $e');
    }

    // Method 3: Use Etherscan public API
    try {
      final response = await _dio.get(
        'https://api.etherscan.io/api?module=account&action=balance&address=$addr&tag=latest',
        options: Options(receiveTimeout: const Duration(seconds: 6)),
      );
      final data = response.data;

      if (data is Map && data['status'] == '1') {
        final balanceWei = BigInt.parse(data['result']);
        final balanceEth = balanceWei.toDouble() / 1e18;
        print('✅ ETH balance from Etherscan: $balanceEth');
        return balanceEth;
      }
    } catch (e) {
      print('⚠️ Etherscan failed: $e');
    }

    // Method 4: Use Alchemy free tier
    try {
      final alchemyResponse = await _dio.post(
        'https://eth-mainnet.g.alchemy.com/v2/demo',
        data: {
          'jsonrpc': '2.0',
          'method': 'eth_getBalance',
          'params': [addr, 'latest'],
          'id': 1,
        },
        options: Options(receiveTimeout: const Duration(seconds: 6)),
      );

      if (alchemyResponse.data != null && alchemyResponse.data['result'] != null) {
        final hexBalance = alchemyResponse.data['result'] as String;
        if (hexBalance.length > 2) {
          final balanceWei = BigInt.parse(hexBalance.substring(2), radix: 16);
          final balanceEth = balanceWei.toDouble() / 1e18;
          print('✅ ETH balance from Alchemy: $balanceEth');
          return balanceEth;
        }
      }
    } catch (e) {
      print('⚠️ Alchemy failed: $e');
    }

    // Method 5: Try backend API as last resort
    try {
      final response = await _dio.get(
        '${ApiConfig.baseUrl}/api/blockchain/balance/ETH/$addr',
        options: Options(receiveTimeout: const Duration(seconds: 6)),
      );
      final data = response.data;

      if (data is Map && data['success'] == true) {
        final balance = double.tryParse(data['balance']?.toString() ?? '0') ?? 0.0;
        print('✅ ETH balance from backend: $balance');
        return balance;
      }
    } catch (e) {
      print('⚠️ Backend API failed: $e');
    }

    print('❌ All ETH balance APIs failed for $address');
    return 0.0;
  }

  /// Get ERC20 token balance (USDT, USDC, etc.)
  Future<double> getErc20TokenBalance(
      String address, String contractAddress, int decimals) async {
    // Try backend proxy first
    try {
      final response = await _dio.get(
        '${ApiConfig.baseUrl}/api/blockchain/balance/ETH/$address',
        options: Options(receiveTimeout: const Duration(seconds: 8)),
      );
      if (response.data is Map && response.data['success'] == true) {
        final balance = double.tryParse(response.data['balance']?.toString() ?? '0') ?? 0.0;
        if (balance > 0) return balance;
      }
    } catch (_) {}

    // Fallback: Etherscan free tier (no key needed for low volume)
    try {
      final response = await _dio.get(
          '${_publicApis['ETH']}?module=account&action=tokenbalance&contractaddress=$contractAddress&address=$address&tag=latest');
      final data = response.data;
      if (data is Map && data['status'] == '1') {
        final balanceWei = BigInt.parse(data['result']);
        final balance = balanceWei / BigInt.from(10).pow(decimals);
        return balance.toDouble();
      }
    } catch (e) {
      debugPrint('Error fetching ERC20 token balance: $e');
    }
    return 0.0;
  }

  /// Get BEP20 token balance (BSC USDT, etc.)
  Future<double> getBep20TokenBalance(
      String address, String contractAddress, int decimals) async {
    // Try backend proxy first
    try {
      final response = await _dio.get(
        '${ApiConfig.baseUrl}/api/blockchain/balance/BNB/$address',
        options: Options(receiveTimeout: const Duration(seconds: 8)),
      );
      if (response.data is Map && response.data['success'] == true) {
        final balance = double.tryParse(response.data['balance']?.toString() ?? '0') ?? 0.0;
        if (balance > 0) return balance;
      }
    } catch (_) {}

    // Fallback: BscScan free tier
    try {
      final response = await _dio.get(
          '${_publicApis['BNB']}?module=account&action=tokenbalance&contractaddress=$contractAddress&address=$address&tag=latest');
      final data = response.data;
      if (data is Map && data['status'] == '1') {
        final balanceWei = BigInt.parse(data['result']);
        final balance = balanceWei / BigInt.from(10).pow(decimals);
        return balance.toDouble();
      }
    } catch (e) {
      debugPrint('Error fetching BEP20 token balance: $e');
    }
    return 0.0;
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
    // Try backend proxy first
    try {
      final response = await _dio.get(
        '${ApiConfig.baseUrl}/api/blockchain/balance/BNB/$address',
        options: Options(receiveTimeout: const Duration(seconds: 10)),
      );
      final data = response.data;
      if (data is Map && data['success'] == true) {
        final balance = double.tryParse(data['balance']?.toString() ?? '0') ?? 0.0;
        debugPrint('✅ BNB balance from backend: $balance');
        return balance;
      }
    } catch (e) {
      debugPrint('⚠️ Backend BNB balance failed: $e');
    }

    // Fallback: BscScan free tier (no key needed)
    try {
      final response = await _dio.get(
          '${_publicApis['BNB']}?module=account&action=balance&address=$address&tag=latest');
      final data = response.data;
      if (data is Map && data['status'] == '1') {
        final balanceWei = BigInt.parse(data['result']);
        final balanceBnb = balanceWei / BigInt.from(10).pow(18);
        return balanceBnb.toDouble();
      }
    } catch (e) {
      debugPrint('Error fetching BSC balance: $e');
    }
    return 0.0;
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
    // Method 1: Use backend proxy (avoids CORS on web)
    try {
      final backendResponse = await _dio.get(
        '${ApiConfig.baseUrl}/api/blockchain/balance/TRX/$address',
        options: Options(receiveTimeout: const Duration(seconds: 10)),
      );
      if (backendResponse.data != null &&
          backendResponse.data['success'] == true) {
        return double.parse(backendResponse.data['balance'].toString());
      }
    } catch (e) {
      debugPrint('⚠️ Backend TRX balance failed: $e');
    }

    // Method 2: Direct trongrid.io (mobile only — CORS blocked on web)
    try {
      final response = await _dio.get(
        'https://api.trongrid.io/v1/accounts/$address',
        options: Options(receiveTimeout: const Duration(seconds: 8)),
      );
      final data = response.data;
      if (data is Map &&
          data.containsKey('data') &&
          (data['data'] as List).isNotEmpty) {
        final accountData = (data['data'] as List).first;
        final balanceSun = accountData['balance'] ?? 0;
        return (balanceSun / 1000000).toDouble();
      }
      return 0.0;
    } catch (e) {
      debugPrint('Error fetching Tron balance: $e');
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
        case 'SOL':
          return await _getSolanaTransactions(address);
        case 'DOGE':
          return await _getDogeTransactions(address);
        case 'LTC':
          return await _getLitecoinTransactions(address);
        case 'XRP':
          return await _getXrpTransactions(address);
        case 'TRX':
          return await _getTronTransactions(address);
        case 'POLYGON':
        case 'MATIC':
          return await _getPolygonTransactions(address);
        default:
          print('Transaction history not supported for $coin');
          return [];
      }
    } catch (e) {
      print('Error getting transaction history for $coin: $e');
      return [];
    }
  }
  
  /// Get Solana transactions
  Future<List<Map<String, dynamic>>> _getSolanaTransactions(String address) async {
    try {
      final response = await _dio.post(
        _publicApis['SOL']!,
        data: {
          'jsonrpc': '2.0',
          'id': 1,
          'method': 'getSignaturesForAddress',
          'params': [address, {'limit': 20}],
        },
      );
      
      if (response.data['result'] != null) {
        return (response.data['result'] as List).map((tx) {
          return {
            'hash': tx['signature'] ?? '',
            'amount': 0.0, // SOL doesn't include amount in signatures
            'timestamp': tx['blockTime'] ?? 0,
            'confirmations': tx['confirmationStatus'] == 'finalized' ? 100 : 0,
            'type': 'unknown',
            'fromAddress': '',
            'toAddress': '',
          };
        }).toList();
      }
      return [];
    } catch (e) {
      print('Error fetching Solana transactions: $e');
      return [];
    }
  }
  
  /// Get Dogecoin transactions
  Future<List<Map<String, dynamic>>> _getDogeTransactions(String address) async {
    try {
      final response = await _dio.get(
        'https://dogechain.info/api/v1/address/transactions/$address',
      );
      
      if (response.data['transactions'] != null) {
        return (response.data['transactions'] as List).take(20).map((tx) {
          final amount = (tx['value'] as num?)?.toDouble() ?? 0.0;
          return {
            'hash': tx['hash'] ?? '',
            'amount': amount.abs(),
            'timestamp': tx['time'] ?? 0,
            'confirmations': tx['confirmations'] ?? 0,
            'type': amount >= 0 ? 'received' : 'sent',
            'fromAddress': '',
            'toAddress': '',
          };
        }).toList();
      }
      return [];
    } catch (e) {
      print('Error fetching Dogecoin transactions: $e');
      return [];
    }
  }
  
  /// Get Litecoin transactions  
  Future<List<Map<String, dynamic>>> _getLitecoinTransactions(String address) async {
    try {
      final response = await _dio.get(
        'https://api.blockcypher.com/v1/ltc/main/addrs/$address?limit=20',
      );
      
      if (response.data['txrefs'] != null) {
        return (response.data['txrefs'] as List).map((tx) {
          final amount = ((tx['value'] as num?) ?? 0) / 100000000;
          return {
            'hash': tx['tx_hash'] ?? '',
            'amount': amount.abs(),
            'timestamp': DateTime.tryParse(tx['confirmed'] ?? '')?.millisecondsSinceEpoch ?? 0,
            'confirmations': tx['confirmations'] ?? 0,
            'type': tx['tx_input_n'] == -1 ? 'received' : 'sent',
            'fromAddress': '',
            'toAddress': '',
          };
        }).toList();
      }
      return [];
    } catch (e) {
      print('Error fetching Litecoin transactions: $e');
      return [];
    }
  }
  
  /// Get XRP transactions
  Future<List<Map<String, dynamic>>> _getXrpTransactions(String address) async {
    try {
      final response = await _dio.post(
        _publicApis['XRP']!,
        data: {
          'method': 'account_tx',
          'params': [
            {'account': address, 'limit': 20}
          ]
        },
      );
      
      if (response.data['result']?['transactions'] != null) {
        return (response.data['result']['transactions'] as List).map((item) {
          final tx = item['tx'];
          final amount = ((tx['Amount'] as num?) ?? 0) / 1000000;
          return {
            'hash': tx['hash'] ?? '',
            'amount': amount.abs(),
            'timestamp': (tx['date'] ?? 0) + 946684800, // Ripple epoch
            'confirmations': 100,
            'type': tx['Destination'] == address ? 'received' : 'sent',
            'fromAddress': tx['Account'] ?? '',
            'toAddress': tx['Destination'] ?? '',
          };
        }).toList();
      }
      return [];
    } catch (e) {
      print('Error fetching XRP transactions: $e');
      return [];
    }
  }
  
  /// Get Tron transactions
  Future<List<Map<String, dynamic>>> _getTronTransactions(String address) async {
    try {
      final response = await _dio.get(
        'https://api.trongrid.io/v1/accounts/$address/transactions?limit=20',
      );
      
      if (response.data['data'] != null) {
        return (response.data['data'] as List).map((tx) {
          final rawData = tx['raw_data'];
          final contract = rawData?['contract']?[0];
          final value = contract?['parameter']?['value'];
          final amount = ((value?['amount'] as num?) ?? 0) / 1000000;
          
          return {
            'hash': tx['txID'] ?? '',
            'amount': amount.abs(),
            'timestamp': (tx['block_timestamp'] ?? 0) ~/ 1000,
            'confirmations': 100,
            'type': value?['to_address'] == address ? 'received' : 'sent',
            'fromAddress': value?['owner_address'] ?? '',
            'toAddress': value?['to_address'] ?? '',
          };
        }).toList();
      }
      return [];
    } catch (e) {
      print('Error fetching Tron transactions: $e');
      return [];
    }
  }
  
  /// Get Polygon transactions
  Future<List<Map<String, dynamic>>> _getPolygonTransactions(String address) async {
    try {
      final response = await _dio.get(
        'https://api.polygonscan.com/api?module=account&action=txlist&address=$address&startblock=0&endblock=99999999&sort=desc',
      );
      
      if (response.data['status'] == '1' && response.data['result'] != null) {
        return (response.data['result'] as List).take(20).map((tx) {
          final valueWei = BigInt.tryParse(tx['value']?.toString() ?? '0') ?? BigInt.zero;
          final amount = valueWei.toDouble() / 1e18;
          return {
            'hash': tx['hash'] ?? '',
            'amount': amount.abs(),
            'timestamp': int.tryParse(tx['timeStamp']?.toString() ?? '0') ?? 0,
            'confirmations': int.tryParse(tx['confirmations']?.toString() ?? '0') ?? 0,
            'type': tx['from'].toString().toLowerCase() == address.toLowerCase() ? 'sent' : 'received',
            'fromAddress': tx['from'] ?? '',
            'toAddress': tx['to'] ?? '',
          };
        }).toList();
      }
      return [];
    } catch (e) {
      print('Error fetching Polygon transactions: $e');
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

      // Fallback to BscScan free tier
      final response = await _dio.get(
          '${_publicApis['BNB']}?module=account&action=txlist&address=$address&startblock=0&endblock=99999999&sort=desc');
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

      // Fallback to Etherscan free tier
      print('DEBUG ETH_TX: Trying Etherscan fallback');
      final response = await _dio.get(
          '${_publicApis['ETH']}?module=account&action=txlist&address=$address&startblock=0&endblock=99999999&sort=desc');
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
    // Try backend fees endpoint first
    try {
      final response = await _dio.get(
        '${ApiConfig.baseUrl}/api/blockchain/fees/ETH',
        options: Options(receiveTimeout: const Duration(seconds: 6)),
      );
      if (response.data is Map && response.data['gasPrice'] != null) {
        final gasPriceGwei = double.tryParse(response.data['gasPrice'].toString()) ?? 20.0;
        return BigInt.from((gasPriceGwei * 1e9).toInt());
      }
    } catch (_) {}

    // Fallback: Etherscan free tier
    try {
      final response = await _dio.get(
          '${_publicApis['ETH']}?module=proxy&action=eth_gasPrice');
      final data = response.data;
      if (data is Map && data.containsKey('result')) {
        return BigInt.parse(data['result'].replaceFirst('0x', ''), radix: 16);
      }
    } catch (_) {}

    return BigInt.from(20000000000); // Default 20 Gwei
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

  /// Format Ethereum address to proper format (0x prefix, lowercase)
  String _formatEthereumAddress(String address) {
    // Remove 0x if present and convert to lowercase
    String formatted = address.replaceAll('0x', '').toLowerCase();
    // Ensure it's exactly 40 hex characters
    if (formatted.length != 40) {
      print('⚠️ Address has unusual length: ${formatted.length}');
    }
    // Add 0x prefix
    return '0x$formatted';
  }
}
