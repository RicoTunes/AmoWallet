import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

/// Result model for QR scan
class QrScanResult {
  final String? address;
  final String? coin;
  final String? amount;

  QrScanResult({this.address, this.coin, this.amount});

  factory QrScanResult.fromMap(Map<String, dynamic> map) {
    return QrScanResult(
      address: map['address'] as String?,
      coin: map['coin'] as String?,
      amount: map['amount'] as String?,
    );
  }
}

class QrScannerService {
  static final QrScannerService _instance = QrScannerService._internal();
  factory QrScannerService() => _instance;
  QrScannerService._internal();

  /// Parses a scanned QR code and extracts coin type and address
  /// Supports formats:
  /// - bitcoin:bc1qxyz...
  /// - ethereum:0x123...
  /// - Plain address: 0x123..., bc1q..., T..., etc.
  Map<String, String?> parseQrCode(String rawValue) {
    String? coin;
    String? address;
    String? amount;
    String? memo;

    // Handle URI schemes (BIP21 / EIP-681 style)
    if (rawValue.contains(':')) {
      final parts = rawValue.split(':');
      final scheme = parts[0].toLowerCase();
      
      // Map scheme to coin
      switch (scheme) {
        case 'bitcoin':
          coin = 'BTC';
          break;
        case 'ethereum':
          coin = 'ETH';
          break;
        case 'litecoin':
          coin = 'LTC';
          break;
        case 'dogecoin':
          coin = 'DOGE';
          break;
        case 'solana':
          coin = 'SOL';
          break;
        case 'tron':
          coin = 'TRX';
          break;
        case 'ripple':
        case 'xrp':
          coin = 'XRP';
          break;
        case 'bnb':
        case 'binance':
          coin = 'BNB';
          break;
      }

      // Parse address and query params
      if (parts.length > 1) {
        final addressPart = parts[1];
        if (addressPart.contains('?')) {
          final queryIndex = addressPart.indexOf('?');
          address = addressPart.substring(0, queryIndex);
          
          // Parse query parameters
          final queryString = addressPart.substring(queryIndex + 1);
          final params = Uri.splitQueryString(queryString);
          amount = params['amount'];
          memo = params['label'] ?? params['message'] ?? params['memo'];
        } else {
          address = addressPart;
        }
      }
    } else {
      // Plain address - try to detect coin type
      address = rawValue.trim();
      coin = _detectCoinFromAddress(address);
    }

    return {
      'coin': coin,
      'address': address,
      'amount': amount,
      'memo': memo,
    };
  }

  /// Detect coin type from address format
  String? _detectCoinFromAddress(String address) {
    // Bitcoin addresses
    if (address.startsWith('1') || address.startsWith('3') || address.startsWith('bc1')) {
      return 'BTC';
    }
    
    // Ethereum/EVM addresses
    if (address.startsWith('0x') && address.length == 42) {
      return 'ETH'; // Could also be BNB, but default to ETH
    }
    
    // Litecoin addresses
    if (address.startsWith('L') || address.startsWith('M') || address.startsWith('ltc1')) {
      return 'LTC';
    }
    
    // Dogecoin addresses
    if (address.startsWith('D') || address.startsWith('A')) {
      return 'DOGE';
    }
    
    // TRON addresses
    if (address.startsWith('T') && address.length == 34) {
      return 'TRX';
    }
    
    // XRP addresses
    if (address.startsWith('r') && address.length >= 25 && address.length <= 35) {
      return 'XRP';
    }
    
    // Solana addresses (Base58, 32-44 chars)
    if (address.length >= 32 && address.length <= 44 && !address.contains('0x')) {
      // Could be SOL, but also could be other base58 formats
      return 'SOL';
    }

    return null;
  }

  /// Validates if an address is valid for the given coin
  bool validateAddress(String coin, String address) {
    switch (coin.toUpperCase()) {
      case 'BTC':
        return address.startsWith('1') || 
               address.startsWith('3') || 
               address.startsWith('bc1');
      case 'ETH':
      case 'BNB':
      case 'USDT-ERC20':
      case 'USDT-BEP20':
        return address.startsWith('0x') && address.length == 42;
      case 'LTC':
        return address.startsWith('L') || 
               address.startsWith('M') || 
               address.startsWith('ltc1');
      case 'DOGE':
        return address.startsWith('D') || address.startsWith('A');
      case 'TRX':
      case 'USDT-TRC20':
        return address.startsWith('T') && address.length == 34;
      case 'XRP':
        return address.startsWith('r') && 
               address.length >= 25 && 
               address.length <= 35;
      case 'SOL':
        return address.length >= 32 && address.length <= 44;
      default:
        return address.length >= 26;
    }
  }
}

/// Full-screen QR Scanner Widget
class QrScannerPage extends StatefulWidget {
  final String? expectedCoin;
  final Function(String address, String? coin, String? amount)? onScanned;

  const QrScannerPage({
    super.key,
    this.expectedCoin,
    this.onScanned,
  });

  @override
  State<QrScannerPage> createState() => _QrScannerPageState();
}

class _QrScannerPageState extends State<QrScannerPage> with SingleTickerProviderStateMixin {
  final MobileScannerController _controller = MobileScannerController(
    detectionSpeed: DetectionSpeed.normal,
    facing: CameraFacing.back,
    torchEnabled: false,
  );
  
  final QrScannerService _scannerService = QrScannerService();
  late AnimationController _animationController;
  late Animation<double> _animation;
  bool _hasScanned = false;
  bool _torchEnabled = false;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: const Duration(seconds: 2),
      vsync: this,
    )..repeat(reverse: true);
    
    _animation = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _animationController.dispose();
    _controller.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_hasScanned) return;
    
    final List<Barcode> barcodes = capture.barcodes;
    for (final barcode in barcodes) {
      final rawValue = barcode.rawValue;
      if (rawValue != null && rawValue.isNotEmpty) {
        _hasScanned = true;
        
        final parsed = _scannerService.parseQrCode(rawValue);
        final address = parsed['address'];
        final coin = parsed['coin'];
        final amount = parsed['amount'];

        if (address != null && address.isNotEmpty) {
          // Validate address if we have expected coin
          if (widget.expectedCoin != null && coin != null) {
            if (!_scannerService.validateAddress(widget.expectedCoin!, address)) {
              _showError('Invalid ${widget.expectedCoin} address');
              _hasScanned = false;
              return;
            }
          }

          // Success - return result
          if (widget.onScanned != null) {
            widget.onScanned!(address, coin, amount);
          }
          Navigator.pop(context, QrScanResult(
            address: address,
            coin: coin ?? widget.expectedCoin,
            amount: amount,
          ));
        } else {
          _showError('Invalid QR code');
          _hasScanned = false;
        }
        break;
      }
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  void _toggleTorch() {
    setState(() {
      _torchEnabled = !_torchEnabled;
    });
    _controller.toggleTorch();
  }

  @override
  Widget build(BuildContext context) {
    final scanAreaSize = MediaQuery.of(context).size.width * 0.7;

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // Camera Preview
          MobileScanner(
            controller: _controller,
            onDetect: _onDetect,
          ),

          // Dark overlay with cutout
          CustomPaint(
            painter: _ScannerOverlayPainter(
              scanAreaSize: scanAreaSize,
              borderColor: widget.expectedCoin != null 
                  ? _getCoinColor(widget.expectedCoin!) 
                  : Colors.blue,
            ),
            child: Container(),
          ),

          // Scanning line animation
          Center(
            child: SizedBox(
              width: scanAreaSize,
              height: scanAreaSize,
              child: AnimatedBuilder(
                animation: _animation,
                builder: (context, child) {
                  return Stack(
                    children: [
                      Positioned(
                        top: _animation.value * (scanAreaSize - 2),
                        left: 0,
                        right: 0,
                        child: Container(
                          height: 2,
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [
                                Colors.transparent,
                                widget.expectedCoin != null
                                    ? _getCoinColor(widget.expectedCoin!)
                                    : Colors.blue,
                                Colors.transparent,
                              ],
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: (widget.expectedCoin != null
                                    ? _getCoinColor(widget.expectedCoin!)
                                    : Colors.blue).withOpacity(0.5),
                                blurRadius: 10,
                                spreadRadius: 2,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ),

          // Top bar
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  // Back button
                  GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.5),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.arrow_back,
                        color: Colors.white,
                        size: 24,
                      ),
                    ),
                  ),
                  
                  // Title
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.5),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      widget.expectedCoin != null
                          ? 'Scan ${widget.expectedCoin} Address'
                          : 'Scan QR Code',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                  ),
                  
                  // Flash toggle
                  GestureDetector(
                    onTap: _toggleTorch,
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: _torchEnabled 
                            ? Colors.amber 
                            : Colors.black.withOpacity(0.5),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        _torchEnabled ? Icons.flash_on : Icons.flash_off,
                        color: Colors.white,
                        size: 24,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Bottom instructions
          Positioned(
            bottom: 80,
            left: 0,
            right: 0,
            child: Column(
              children: [
                Container(
                  margin: const EdgeInsets.symmetric(horizontal: 40),
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.7),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Column(
                    children: [
                      Icon(
                        Icons.qr_code_scanner,
                        color: widget.expectedCoin != null
                            ? _getCoinColor(widget.expectedCoin!)
                            : Colors.blue,
                        size: 32,
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Position QR code within the frame',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Scanning will happen automatically',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.grey[400],
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Color _getCoinColor(String coin) {
    final colors = {
      'BTC': const Color(0xFFF7931A),
      'ETH': const Color(0xFF627EEA),
      'BNB': const Color(0xFFF0B90B),
      'USDT': const Color(0xFF26A17B),
      'USDT-ERC20': const Color(0xFF26A17B),
      'USDT-BEP20': const Color(0xFF26A17B),
      'USDT-TRC20': const Color(0xFF26A17B),
      'SOL': const Color(0xFF9945FF),
      'XRP': const Color(0xFF23292F),
      'TRX': const Color(0xFFEB0029),
      'LTC': const Color(0xFFBFBBBB),
      'DOGE': const Color(0xFFC2A633),
    };
    return colors[coin.toUpperCase()] ?? Colors.blue;
  }
}

/// Custom painter for scanner overlay
class _ScannerOverlayPainter extends CustomPainter {
  final double scanAreaSize;
  final Color borderColor;

  _ScannerOverlayPainter({
    required this.scanAreaSize,
    required this.borderColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.black.withOpacity(0.6)
      ..style = PaintingStyle.fill;

    final centerX = size.width / 2;
    final centerY = size.height / 2;
    final halfSize = scanAreaSize / 2;

    // Draw dark overlay
    final path = Path()
      ..addRect(Rect.fromLTWH(0, 0, size.width, size.height))
      ..addRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(
            center: Offset(centerX, centerY),
            width: scanAreaSize,
            height: scanAreaSize,
          ),
          const Radius.circular(20),
        ),
      )
      ..fillType = PathFillType.evenOdd;

    canvas.drawPath(path, paint);

    // Draw border corners
    final cornerPaint = Paint()
      ..color = borderColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round;

    final cornerLength = 30.0;
    final left = centerX - halfSize;
    final top = centerY - halfSize;
    final right = centerX + halfSize;
    final bottom = centerY + halfSize;
    final radius = 20.0;

    // Top-left corner
    canvas.drawPath(
      Path()
        ..moveTo(left, top + cornerLength)
        ..lineTo(left, top + radius)
        ..quadraticBezierTo(left, top, left + radius, top)
        ..lineTo(left + cornerLength, top),
      cornerPaint,
    );

    // Top-right corner
    canvas.drawPath(
      Path()
        ..moveTo(right - cornerLength, top)
        ..lineTo(right - radius, top)
        ..quadraticBezierTo(right, top, right, top + radius)
        ..lineTo(right, top + cornerLength),
      cornerPaint,
    );

    // Bottom-left corner
    canvas.drawPath(
      Path()
        ..moveTo(left, bottom - cornerLength)
        ..lineTo(left, bottom - radius)
        ..quadraticBezierTo(left, bottom, left + radius, bottom)
        ..lineTo(left + cornerLength, bottom),
      cornerPaint,
    );

    // Bottom-right corner
    canvas.drawPath(
      Path()
        ..moveTo(right, bottom - cornerLength)
        ..lineTo(right, bottom - radius)
        ..quadraticBezierTo(right, bottom, right - radius, bottom)
        ..lineTo(right - cornerLength, bottom),
      cornerPaint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
