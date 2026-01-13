import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:logger/logger.dart';
import 'package:web3dart/web3dart.dart';

/// Service for signing and broadcasting real blockchain transactions
/// This enables REAL swaps by:
/// 1. Signing transactions with user's private key
/// 2. Broadcasting to the blockchain
/// 3. Tracking transaction status
class TransactionSigningService {
  static final TransactionSigningService _instance = TransactionSigningService._internal();
  factory TransactionSigningService() => _instance;
  TransactionSigningService._internal();

  final _logger = Logger();

  // RPC endpoints for different chains
  static const Map<int, String> _rpcUrls = {
    1: 'https://eth.llamarpc.com', // Ethereum Mainnet
    56: 'https://bsc-dataseed1.binance.org', // BSC
    137: 'https://polygon-rpc.com', // Polygon
    42161: 'https://arb1.arbitrum.io/rpc', // Arbitrum
    10: 'https://mainnet.optimism.io', // Optimism
    43114: 'https://api.avax.network/ext/bc/C/rpc', // Avalanche
    8453: 'https://mainnet.base.org', // Base
  };

  // Chain names for logging
  static const Map<int, String> _chainNames = {
    1: 'Ethereum',
    56: 'BSC',
    137: 'Polygon',
    42161: 'Arbitrum',
    10: 'Optimism',
    43114: 'Avalanche',
    8453: 'Base',
  };

  // Native token symbols
  static const Map<int, String> _nativeSymbols = {
    1: 'ETH',
    56: 'BNB',
    137: 'MATIC',
    42161: 'ETH',
    10: 'ETH',
    43114: 'AVAX',
    8453: 'ETH',
  };

  /// Get Web3 client for a specific chain
  Web3Client _getClient(int chainId) {
    final rpcUrl = _rpcUrls[chainId] ?? _rpcUrls[1]!;
    return Web3Client(rpcUrl, http.Client());
  }

  /// Sign and broadcast a transaction to the blockchain
  /// Returns the transaction hash if successful
  Future<TransactionResult> signAndBroadcast({
    required String privateKeyHex,
    required int chainId,
    required String toAddress,
    required String data,
    required BigInt value,
    BigInt? gasLimit,
    BigInt? gasPrice,
    BigInt? maxFeePerGas,
    BigInt? maxPriorityFeePerGas,
  }) async {
    final client = _getClient(chainId);
    final chainName = _chainNames[chainId] ?? 'Unknown';

    try {
      _logger.i('🔑 Signing transaction on $chainName (chainId: $chainId)');

      // Create credentials from private key
      final credentials = EthPrivateKey.fromHex(privateKeyHex);
      final fromAddress = credentials.address;

      _logger.i('📤 From: ${fromAddress.hex}');
      _logger.i('📥 To: $toAddress');

      // Get current gas price if not provided
      if (gasPrice == null && maxFeePerGas == null) {
        final currentGasPrice = await client.getGasPrice();
        gasPrice = currentGasPrice.getInWei;
        _logger.i('⛽ Gas price: ${gasPrice / BigInt.from(1e9)} Gwei');
      }

      // Get nonce
      final nonce = await client.getTransactionCount(fromAddress);
      _logger.i('🔢 Nonce: $nonce');

      // Estimate gas if not provided
      if (gasLimit == null) {
        try {
          gasLimit = await client.estimateGas(
            sender: fromAddress,
            to: EthereumAddress.fromHex(toAddress),
            data: _hexToBytes(data),
            value: EtherAmount.inWei(value),
          );
          // Add 20% buffer for safety
          gasLimit = (gasLimit * BigInt.from(120)) ~/ BigInt.from(100);
          _logger.i('⛽ Estimated gas: $gasLimit');
        } catch (e) {
          gasLimit = BigInt.from(300000); // Default for swaps
          _logger.w('⚠️ Gas estimation failed, using default: $gasLimit');
        }
      }

      // Create the transaction
      final transaction = Transaction(
        to: EthereumAddress.fromHex(toAddress),
        from: fromAddress,
        data: _hexToBytes(data),
        value: EtherAmount.inWei(value),
        gasPrice: gasPrice != null ? EtherAmount.inWei(gasPrice) : null,
        maxGas: gasLimit.toInt(),
        nonce: nonce,
      );

      _logger.i('📝 Transaction created, signing...');

      // Sign and send the transaction
      final txHash = await client.sendTransaction(
        credentials,
        transaction,
        chainId: chainId,
      );

      _logger.i('✅ Transaction sent! Hash: $txHash');

      // Get explorer URL
      final explorerUrl = _getExplorerUrl(chainId, txHash);

      return TransactionResult(
        success: true,
        txHash: txHash,
        chainId: chainId,
        chainName: chainName,
        explorerUrl: explorerUrl,
        fromAddress: fromAddress.hex,
        toAddress: toAddress,
        value: value,
        gasLimit: gasLimit,
        gasPrice: gasPrice,
        nonce: nonce,
      );
    } catch (e) {
      _logger.e('❌ Transaction failed: $e');
      return TransactionResult(
        success: false,
        error: e.toString(),
        chainId: chainId,
        chainName: chainName,
      );
    } finally {
      client.dispose();
    }
  }

  /// Sign and broadcast a swap transaction from backend quote
  Future<TransactionResult> executeSwapTransaction({
    required String privateKeyHex,
    required Map<String, dynamic> transactionData,
  }) async {
    // Parse transaction data from backend
    final chainId = transactionData['chainId'] as int? ?? 1;
    final toAddress = transactionData['to'] as String;
    final data = transactionData['data'] as String? ?? '0x';
    final valueStr = transactionData['value'] as String? ?? '0';
    final gasLimitStr = transactionData['gasLimit'] as String?;
    final gasPriceStr = transactionData['gasPrice'] as String?;

    final value = BigInt.tryParse(valueStr) ?? BigInt.zero;
    final gasLimit = gasLimitStr != null ? BigInt.tryParse(gasLimitStr) : null;
    final gasPrice = gasPriceStr != null ? BigInt.tryParse(gasPriceStr) : null;

    return signAndBroadcast(
      privateKeyHex: privateKeyHex,
      chainId: chainId,
      toAddress: toAddress,
      data: data,
      value: value,
      gasLimit: gasLimit,
      gasPrice: gasPrice,
    );
  }

  /// Check transaction status
  Future<TransactionStatus> getTransactionStatus(
    String txHash,
    int chainId,
  ) async {
    final client = _getClient(chainId);

    try {
      final receipt = await client.getTransactionReceipt(txHash);

      if (receipt == null) {
        return TransactionStatus(
          status: TxStatus.pending,
          confirmations: 0,
        );
      }

      final currentBlock = await client.getBlockNumber();
      final confirmations = receipt.blockNumber != null
          ? currentBlock - receipt.blockNumber.blockNum
          : 0;

      final success = receipt.status ?? false;

      return TransactionStatus(
        status: success ? TxStatus.confirmed : TxStatus.failed,
        confirmations: confirmations,
        blockNumber: receipt.blockNumber?.blockNum,
        gasUsed: receipt.gasUsed,
      );
    } catch (e) {
      _logger.e('Failed to get transaction status: $e');
      return TransactionStatus(
        status: TxStatus.unknown,
        error: e.toString(),
      );
    } finally {
      client.dispose();
    }
  }

  /// Get the balance of an address
  Future<BigInt> getBalance(String address, int chainId) async {
    final client = _getClient(chainId);

    try {
      final balance = await client.getBalance(EthereumAddress.fromHex(address));
      return balance.getInWei;
    } catch (e) {
      _logger.e('Failed to get balance: $e');
      return BigInt.zero;
    } finally {
      client.dispose();
    }
  }

  /// Get ERC20 token balance
  Future<BigInt> getTokenBalance(
    String tokenAddress,
    String walletAddress,
    int chainId,
  ) async {
    final client = _getClient(chainId);

    try {
      // ERC20 balanceOf function signature
      final data = '0x70a08231' +
          walletAddress.substring(2).padLeft(64, '0');

      final result = await client.call(
        contract: DeployedContract(
          ContractAbi.fromJson(
            json.encode([
              {
                'constant': true,
                'inputs': [
                  {'name': '_owner', 'type': 'address'}
                ],
                'name': 'balanceOf',
                'outputs': [
                  {'name': 'balance', 'type': 'uint256'}
                ],
                'type': 'function'
              }
            ]),
            'ERC20',
          ),
          EthereumAddress.fromHex(tokenAddress),
        ),
        function: ContractFunction(
          'balanceOf',
          [FunctionParameter('_owner', AddressType())],
        ),
        params: [EthereumAddress.fromHex(walletAddress)],
      );

      return result.first as BigInt;
    } catch (e) {
      _logger.e('Failed to get token balance: $e');
      return BigInt.zero;
    } finally {
      client.dispose();
    }
  }

  /// Approve ERC20 token spending (required before swaps)
  Future<TransactionResult> approveToken({
    required String privateKeyHex,
    required String tokenAddress,
    required String spenderAddress,
    required BigInt amount,
    required int chainId,
  }) async {
    // ERC20 approve function: approve(address spender, uint256 amount)
    final data = '0x095ea7b3' +
        spenderAddress.substring(2).padLeft(64, '0') +
        amount.toRadixString(16).padLeft(64, '0');

    return signAndBroadcast(
      privateKeyHex: privateKeyHex,
      chainId: chainId,
      toAddress: tokenAddress,
      data: data,
      value: BigInt.zero,
    );
  }

  /// Check if token is approved for spending
  Future<BigInt> getAllowance(
    String tokenAddress,
    String ownerAddress,
    String spenderAddress,
    int chainId,
  ) async {
    final client = _getClient(chainId);

    try {
      // ERC20 allowance function
      final contract = DeployedContract(
        ContractAbi.fromJson(
          json.encode([
            {
              'constant': true,
              'inputs': [
                {'name': '_owner', 'type': 'address'},
                {'name': '_spender', 'type': 'address'}
              ],
              'name': 'allowance',
              'outputs': [
                {'name': '', 'type': 'uint256'}
              ],
              'type': 'function'
            }
          ]),
          'ERC20',
        ),
        EthereumAddress.fromHex(tokenAddress),
      );

      final result = await client.call(
        contract: contract,
        function: contract.function('allowance'),
        params: [
          EthereumAddress.fromHex(ownerAddress),
          EthereumAddress.fromHex(spenderAddress),
        ],
      );

      return result.first as BigInt;
    } catch (e) {
      _logger.e('Failed to get allowance: $e');
      return BigInt.zero;
    } finally {
      client.dispose();
    }
  }

  /// Convert hex string to Uint8List
  Uint8List _hexToBytes(String hex) {
    if (hex.startsWith('0x')) {
      hex = hex.substring(2);
    }
    if (hex.isEmpty) return Uint8List(0);
    
    final bytes = <int>[];
    for (var i = 0; i < hex.length; i += 2) {
      bytes.add(int.parse(hex.substring(i, i + 2), radix: 16));
    }
    return Uint8List.fromList(bytes);
  }

  /// Get block explorer URL for transaction
  String _getExplorerUrl(int chainId, String txHash) {
    final explorers = {
      1: 'https://etherscan.io/tx/',
      56: 'https://bscscan.com/tx/',
      137: 'https://polygonscan.com/tx/',
      42161: 'https://arbiscan.io/tx/',
      10: 'https://optimistic.etherscan.io/tx/',
      43114: 'https://snowtrace.io/tx/',
      8453: 'https://basescan.org/tx/',
    };
    
    final baseUrl = explorers[chainId] ?? 'https://etherscan.io/tx/';
    return '$baseUrl$txHash';
  }

  /// Get chain ID from coin symbol
  int getChainIdFromCoin(String coin) {
    if (coin.contains('-BEP20') || coin.contains('-BSC') || coin == 'BNB') {
      return 56;
    }
    if (coin.contains('-POLYGON') || coin == 'MATIC') {
      return 137;
    }
    if (coin.contains('-ARB') || coin.contains('-ARBITRUM')) {
      return 42161;
    }
    if (coin.contains('-OP') || coin.contains('-OPTIMISM')) {
      return 10;
    }
    if (coin.contains('-AVAX') || coin == 'AVAX') {
      return 43114;
    }
    if (coin.contains('-BASE')) {
      return 8453;
    }
    // Default to Ethereum
    return 1;
  }

  /// Get native token symbol for chain
  String getNativeSymbol(int chainId) {
    return _nativeSymbols[chainId] ?? 'ETH';
  }

  /// Get chain name
  String getChainName(int chainId) {
    return _chainNames[chainId] ?? 'Unknown';
  }
}

/// Result of a transaction broadcast
class TransactionResult {
  final bool success;
  final String? txHash;
  final String? error;
  final int chainId;
  final String chainName;
  final String? explorerUrl;
  final String? fromAddress;
  final String? toAddress;
  final BigInt? value;
  final BigInt? gasLimit;
  final BigInt? gasPrice;
  final int? nonce;

  TransactionResult({
    required this.success,
    this.txHash,
    this.error,
    required this.chainId,
    required this.chainName,
    this.explorerUrl,
    this.fromAddress,
    this.toAddress,
    this.value,
    this.gasLimit,
    this.gasPrice,
    this.nonce,
  });

  Map<String, dynamic> toJson() => {
    'success': success,
    'txHash': txHash,
    'error': error,
    'chainId': chainId,
    'chainName': chainName,
    'explorerUrl': explorerUrl,
    'fromAddress': fromAddress,
    'toAddress': toAddress,
    'value': value?.toString(),
    'gasLimit': gasLimit?.toString(),
    'gasPrice': gasPrice?.toString(),
    'nonce': nonce,
  };
}

/// Transaction status enum
enum TxStatus {
  pending,
  confirmed,
  failed,
  unknown,
}

/// Transaction status details
class TransactionStatus {
  final TxStatus status;
  final int confirmations;
  final int? blockNumber;
  final BigInt? gasUsed;
  final String? error;

  TransactionStatus({
    required this.status,
    this.confirmations = 0,
    this.blockNumber,
    this.gasUsed,
    this.error,
  });
}
