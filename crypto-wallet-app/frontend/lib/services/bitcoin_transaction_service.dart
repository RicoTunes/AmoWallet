import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:logger/logger.dart';
import 'package:bitcoin_base/bitcoin_base.dart';

/// Service for creating and broadcasting REAL Bitcoin transactions
/// Used for THORChain swaps (BTC → other assets)
/// 
/// This implementation uses bitcoin_base library for proper:
/// - WIF private key handling
/// - ECDSA secp256k1 signing
/// - Transaction serialization
/// - Address encoding (legacy P2PKH, SegWit bech32)
class BitcoinTransactionService {
  static final BitcoinTransactionService _instance = BitcoinTransactionService._internal();
  factory BitcoinTransactionService() => _instance;
  BitcoinTransactionService._internal();

  final _logger = Logger();

  // Bitcoin network APIs
  static const String _blockstreamMainnet = 'https://blockstream.info/api';
  static const String _mempoolMainnet = 'https://mempool.space/api';

  // Minimum dust amount
  static const int _dustLimit = 546;

  /// Create and broadcast a REAL Bitcoin transaction for THORChain swap
  /// Returns transaction ID if successful
  Future<BitcoinTxResult> sendBitcoinForSwap({
    required String privateKeyWIF,
    required String fromAddress,
    required String toAddress, // THORChain inbound address (bech32)
    required int amountSatoshis,
    required String memo, // THORChain memo for OP_RETURN
    int feeRate = 2, // LOWERED: 2 sat/vbyte is fine for swaps (not urgent)
  }) async {
    try {
      _logger.i('🔄 Creating REAL Bitcoin transaction for THORChain swap');
      _logger.i('   From: $fromAddress');
      _logger.i('   To (THORChain vault): $toAddress');
      _logger.i('   Amount: $amountSatoshis sats');
      _logger.i('   Memo: $memo');

      // Step 1: Parse the private key from WIF
      final privateKey = ECPrivate.fromWif(privateKeyWIF, netVersion: BitcoinNetwork.mainnet.wifNetVer);
      final publicKey = privateKey.getPublic();
      _logger.i('   ✅ Private key parsed successfully');

      // Step 2: Get UTXOs for the address
      final utxos = await _getUTXOs(fromAddress);
      if (utxos.isEmpty) {
        throw Exception('No UTXOs found for address $fromAddress');
      }
      _logger.i('   Found ${utxos.length} UTXOs');

      // Step 3: Sort UTXOs by value (largest first) for optimal selection
      utxos.sort((a, b) => (b['value'] as int).compareTo(a['value'] as int));

      // Step 4: Calculate total available
      int totalAvailable = 0;
      for (final utxo in utxos) {
        totalAvailable += utxo['value'] as int;
      }
      _logger.i('   Total available: $totalAvailable sats');

      // Step 5: Determine address type
      final isSourceLegacy = fromAddress.startsWith('1');
      final isSourceSegwit = fromAddress.startsWith('bc1');
      final isSourceP2SH = fromAddress.startsWith('3');
      
      // Step 6: Smart UTXO selection - use minimum UTXOs needed
      List<Map<String, dynamic>> selectedUtxos = [];
      int selectedTotal = 0;
      
      // First try: select minimum UTXOs to cover amount + estimated fee
      for (final utxo in utxos) {
        selectedUtxos.add(utxo);
        selectedTotal += utxo['value'] as int;
        
        // Estimate fee with current UTXO count
        final numOutputs = 2; // vault + OP_RETURN (no change for max efficiency)
        final estimatedSize = _estimateTransactionSize(selectedUtxos.length, numOutputs, isSourceSegwit || isSourceP2SH);
        final estimatedFee = estimatedSize * feeRate;
        
        if (selectedTotal >= amountSatoshis + estimatedFee + 546) {
          break; // We have enough
        }
      }
      
      // Calculate final fee with selected UTXOs
      final numOutputs = 2 + (selectedTotal > amountSatoshis + 1000 ? 1 : 0);
      final estimatedSize = _estimateTransactionSize(selectedUtxos.length, numOutputs, isSourceSegwit || isSourceP2SH);
      final fee = estimatedSize * feeRate;
      _logger.i('   Using ${selectedUtxos.length}/${utxos.length} UTXOs');
      _logger.i('   Selected balance: $selectedTotal sats');
      _logger.i('   Estimated fee: $fee sats ($feeRate sat/vbyte)');

      if (selectedTotal < amountSatoshis + fee) {
        // Try using ALL UTXOs as last resort
        selectedUtxos = List.from(utxos);
        selectedTotal = totalAvailable;
        final maxFee = _estimateTransactionSize(utxos.length, 2, isSourceSegwit || isSourceP2SH) * feeRate;
        final maxSwappable = totalAvailable - maxFee - 546;
        final maxSwappableBtc = maxSwappable > 0 ? (maxSwappable / 100000000).toStringAsFixed(8) : '0';
        
        if (totalAvailable < amountSatoshis + maxFee) {
          throw Exception(
            'Insufficient funds for swap + network fee.\n'
            '• Your balance: $totalAvailable sats (${(totalAvailable / 100000000).toStringAsFixed(8)} BTC)\n'
            '• Swap amount: $amountSatoshis sats\n'
            '• Network fee: $maxFee sats (at $feeRate sat/vbyte)\n'
            '• Total needed: ${amountSatoshis + maxFee} sats\n'
            '• Max swappable: ${maxSwappable > 0 ? maxSwappable : 0} sats ($maxSwappableBtc BTC)\n\n'
            'Tip: Try 100% button to swap your entire balance!'
          );
        }
      }

      // Step 7: Build and sign the REAL transaction
      _logger.i('📝 Building REAL Bitcoin transaction...');
      
      final rawTx = await _buildRealTransaction(
        privateKey: privateKey,
        publicKey: publicKey,
        fromAddress: fromAddress,
        utxos: selectedUtxos, // Use selected UTXOs, not all
        toAddress: toAddress,
        amount: amountSatoshis,
        fee: fee,
        memo: memo,
        isSourceLegacy: isSourceLegacy,
        isSourceSegwit: isSourceSegwit,
      );
      
      _logger.i('   Raw transaction built: ${rawTx.length ~/ 2} bytes');

      // Step 8: Broadcast the transaction
      _logger.i('📡 Broadcasting transaction to Bitcoin network...');
      final txId = await _broadcastTransaction(rawTx);
      
      _logger.i('✅ Transaction broadcast successful!');
      _logger.i('   TxID: $txId');

      return BitcoinTxResult(
        success: true,
        txId: txId,
        explorerUrl: 'https://mempool.space/tx/$txId',
        amountSent: amountSatoshis,
        fee: fee,
        isSimulated: false,
      );
    } catch (e) {
      _logger.e('❌ Bitcoin transaction failed: $e');
      return BitcoinTxResult(
        success: false,
        error: e.toString(),
      );
    }
  }

  /// Build a REAL Bitcoin transaction using bitcoin_base
  Future<String> _buildRealTransaction({
    required ECPrivate privateKey,
    required ECPublic publicKey,
    required String fromAddress,
    required List<Map<String, dynamic>> utxos,
    required String toAddress,
    required int amount,
    required int fee,
    required String memo,
    required bool isSourceLegacy,
    required bool isSourceSegwit,
  }) async {
    // Build inputs
    final List<UtxoWithAddress> utxosWithAddress = [];
    int totalInput = 0;
    
    // Create the source address
    BitcoinBaseAddress sourceAddress;
    if (isSourceSegwit) {
      sourceAddress = publicKey.toSegwitAddress();
    } else {
      sourceAddress = publicKey.toAddress();
    }
    
    for (final utxo in utxos) {
      final txHash = utxo['txid'] as String;
      final vout = utxo['vout'] as int;
      final value = BigInt.from(utxo['value'] as int);
      
      // Create UTXO with address info for signing
      final utxoWithAddr = UtxoWithAddress(
        utxo: BitcoinUtxo(
          txHash: txHash,
          value: value,
          vout: vout,
          scriptType: isSourceSegwit ? SegwitAddressType.p2wpkh : P2pkhAddressType.p2pkh,
        ),
        ownerDetails: UtxoAddressDetails(
          publicKey: publicKey.toHex(),
          address: sourceAddress,
        ),
      );
      utxosWithAddress.add(utxoWithAddr);
      
      totalInput += utxo['value'] as int;
      
      // Stop if we have enough
      if (totalInput >= amount + fee + _dustLimit) break;
    }
    
    // Build outputs
    final List<BitcoinOutput> outputs = [];
    
    // 1. Main output to THORChain vault
    BitcoinBaseAddress vaultAddress;
    if (toAddress.startsWith('bc1q')) {
      // P2WPKH or P2WSH (bech32)
      if (toAddress.length == 42) {
        vaultAddress = P2wpkhAddress.fromAddress(address: toAddress, network: BitcoinNetwork.mainnet);
      } else {
        vaultAddress = P2wshAddress.fromAddress(address: toAddress, network: BitcoinNetwork.mainnet);
      }
    } else if (toAddress.startsWith('bc1p')) {
      // P2TR (taproot)
      vaultAddress = P2trAddress.fromAddress(address: toAddress, network: BitcoinNetwork.mainnet);
    } else if (toAddress.startsWith('3')) {
      vaultAddress = P2shAddress.fromAddress(address: toAddress, network: BitcoinNetwork.mainnet);
    } else {
      vaultAddress = P2pkhAddress.fromAddress(address: toAddress, network: BitcoinNetwork.mainnet);
    }
    
    outputs.add(BitcoinOutput(
      address: vaultAddress,
      value: BigInt.from(amount),
    ));
    
    // 2. Change output (if significant)
    final change = totalInput - amount - fee;
    if (change > _dustLimit) {
      outputs.add(BitcoinOutput(
        address: sourceAddress,
        value: BigInt.from(change),
      ));
    }
    
    // 3. Build using BitcoinTransactionBuilder
    final builder = BitcoinTransactionBuilder(
      outPuts: outputs,
      fee: BigInt.from(fee),
      network: BitcoinNetwork.mainnet,
      utxos: utxosWithAddress,
      memo: memo, // OP_RETURN memo
      enableRBF: true,
    );
    
    // Build and sign the transaction
    final transaction = builder.buildTransaction((trDigest, utxo, pubKey, sighash) {
      // Sign using ECDSA for non-taproot
      return privateKey.signECDSA(trDigest, sighash: sighash);
    });
    
    // Return serialized transaction
    return transaction.serialize();
  }

  /// Get UTXOs for an address
  Future<List<Map<String, dynamic>>> _getUTXOs(String address) async {
    try {
      // Try Blockstream API first
      final response = await http.get(
        Uri.parse('$_blockstreamMainnet/address/$address/utxo'),
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);
        return data.map((utxo) => {
          'txid': utxo['txid'],
          'vout': utxo['vout'],
          'value': utxo['value'],
          'status': utxo['status'],
        }).toList();
      }

      // Fallback to Mempool.space
      final mempoolResponse = await http.get(
        Uri.parse('$_mempoolMainnet/address/$address/utxo'),
      ).timeout(const Duration(seconds: 10));

      if (mempoolResponse.statusCode == 200) {
        final List<dynamic> data = json.decode(mempoolResponse.body);
        return data.map((utxo) => {
          'txid': utxo['txid'],
          'vout': utxo['vout'],
          'value': utxo['value'],
          'status': utxo['status'],
        }).toList();
      }

      return [];
    } catch (e) {
      _logger.e('Failed to get UTXOs: $e');
      return [];
    }
  }

  /// Estimate transaction size in virtual bytes
  int _estimateTransactionSize(int numInputs, int numOutputs, bool isSegwit) {
    if (isSegwit) {
      // P2WPKH: ~68 vbytes per input, ~31 vbytes per output, ~10.5 overhead
      return (numInputs * 68) + (numOutputs * 31) + 11;
    } else {
      // P2PKH: ~148 bytes per input, ~34 bytes per output, ~10 overhead
      return (numInputs * 148) + (numOutputs * 34) + 10;
    }
  }

  /// Broadcast transaction to the network
  Future<String> _broadcastTransaction(String rawTx) async {
    // Try Blockstream first
    try {
      final response = await http.post(
        Uri.parse('$_blockstreamMainnet/tx'),
        body: rawTx,
        headers: {'Content-Type': 'text/plain'},
      ).timeout(const Duration(seconds: 30));

      if (response.statusCode == 200) {
        return response.body; // Returns txid
      }
      _logger.w('Blockstream response: ${response.statusCode} - ${response.body}');
    } catch (e) {
      _logger.w('Blockstream broadcast failed: $e');
    }

    // Fallback to Mempool.space
    try {
      final response = await http.post(
        Uri.parse('$_mempoolMainnet/tx'),
        body: rawTx,
        headers: {'Content-Type': 'text/plain'},
      ).timeout(const Duration(seconds: 30));

      if (response.statusCode == 200) {
        return response.body;
      }
      
      throw Exception('Broadcast failed: ${response.body}');
    } catch (e) {
      throw Exception('Failed to broadcast transaction: $e');
    }
  }

  /// Get current recommended fee rate
  Future<int> getRecommendedFeeRate() async {
    try {
      final response = await http.get(
        Uri.parse('$_mempoolMainnet/v1/fees/recommended'),
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        // Use half hour fee for swaps
        return data['halfHourFee'] ?? 10;
      }
      return 10; // Default
    } catch (e) {
      return 10; // Default on error
    }
  }

  /// Check transaction status
  Future<BitcoinTxStatus> getTransactionStatus(String txId) async {
    try {
      final response = await http.get(
        Uri.parse('$_blockstreamMainnet/tx/$txId'),
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final status = data['status'];
        
        return BitcoinTxStatus(
          found: true,
          confirmed: status['confirmed'] ?? false,
          blockHeight: status['block_height'],
          blockTime: status['block_time'],
        );
      }
      
      return BitcoinTxStatus(found: false);
    } catch (e) {
      return BitcoinTxStatus(found: false, error: e.toString());
    }
  }

  /// Calculate maximum swappable amount after fees
  Future<MaxSwapInfo> calculateMaxSwappableAmount({
    required String fromAddress,
    int feeRate = 2, // Use same low fee rate
  }) async {
    try {
      // Fetch UTXOs
      final utxos = await _getUTXOs(fromAddress);
      if (utxos.isEmpty) {
        return MaxSwapInfo(
          maxSatoshis: 0,
          totalBalance: 0,
          estimatedFee: 0,
          canSwap: false,
          reason: 'No UTXOs found',
        );
      }

      // Calculate total balance
      final totalBalance = utxos.fold<int>(0, (sum, utxo) => sum + (utxo['value'] as int));

      // Determine address type for fee estimation
      final isSegwit = fromAddress.startsWith('bc1') || fromAddress.startsWith('3');
      
      // Estimate transaction size (2 outputs: vault + OP_RETURN)
      final estimatedSize = _estimateTransactionSize(utxos.length, 2, isSegwit);
      final estimatedFee = estimatedSize * feeRate;

      // THORChain practical minimum (can be lower for small swaps)
      const thorchainMinimum = 1000; // Lowered from 10000
      
      // Calculate max (balance - fee - dust threshold)
      final maxSwappable = totalBalance - estimatedFee - _dustLimit;

      if (maxSwappable < thorchainMinimum) {
        return MaxSwapInfo(
          maxSatoshis: maxSwappable > 0 ? maxSwappable : 0,
          totalBalance: totalBalance,
          estimatedFee: estimatedFee,
          canSwap: false,
          reason: maxSwappable <= 0 
              ? 'Balance too low to cover network fees'
              : 'After fees, only $maxSwappable sats available (THORChain minimum ~$thorchainMinimum sats)',
        );
      }

      return MaxSwapInfo(
        maxSatoshis: maxSwappable,
        totalBalance: totalBalance,
        estimatedFee: estimatedFee,
        canSwap: true,
        reason: null,
      );
    } catch (e) {
      return MaxSwapInfo(
        maxSatoshis: 0,
        totalBalance: 0,
        estimatedFee: 0,
        canSwap: false,
        reason: 'Error: $e',
      );
    }
  }
}

/// Max swap calculation result
class MaxSwapInfo {
  final int maxSatoshis;
  final int totalBalance;
  final int estimatedFee;
  final bool canSwap;
  final String? reason;

  MaxSwapInfo({
    required this.maxSatoshis,
    required this.totalBalance,
    required this.estimatedFee,
    required this.canSwap,
    this.reason,
  });
  
  double get maxBtc => maxSatoshis / 100000000;
  double get totalBtc => totalBalance / 100000000;
}

/// Result of a Bitcoin transaction
class BitcoinTxResult {
  final bool success;
  final String? txId;
  final String? explorerUrl;
  final String? error;
  final int? amountSent;
  final int? fee;
  final bool isSimulated;
  final String? simulationReason;

  BitcoinTxResult({
    required this.success,
    this.txId,
    this.explorerUrl,
    this.error,
    this.amountSent,
    this.fee,
    this.isSimulated = false,
    this.simulationReason,
  });
}

/// Bitcoin transaction status
class BitcoinTxStatus {
  final bool found;
  final bool confirmed;
  final int? blockHeight;
  final int? blockTime;
  final String? error;

  BitcoinTxStatus({
    required this.found,
    this.confirmed = false,
    this.blockHeight,
    this.blockTime,
    this.error,
  });
}
