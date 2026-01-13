import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:mobile_scanner/mobile_scanner.dart';

class QRScannerWidget extends StatefulWidget {
  final Function(String) onScanned;
  final Color accentColor;

  const QRScannerWidget({
    super.key,
    required this.onScanned,
    this.accentColor = const Color(0xFF8B5CF6),
  });

  @override
  State<QRScannerWidget> createState() => _QRScannerWidgetState();
}

class _QRScannerWidgetState extends State<QRScannerWidget> {
  MobileScannerController? _cameraController;
  bool _isFlashOn = false;
  bool _isCameraInitialized = false;
  bool _hasScanned = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    if (!kIsWeb) {
      _initializeCamera();
    }
  }

  Future<void> _initializeCamera() async {
    try {
      _cameraController = MobileScannerController(
        detectionSpeed: DetectionSpeed.normal,
        facing: CameraFacing.back,
        torchEnabled: false,
      );
      
      setState(() {
        _isCameraInitialized = true;
      });
    } catch (e) {
      setState(() {
        _errorMessage = 'Failed to initialize camera: $e';
      });
    }
  }

  @override
  void dispose() {
    _cameraController?.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_hasScanned) return;
    
    final List<Barcode> barcodes = capture.barcodes;
    for (final barcode in barcodes) {
      if (barcode.rawValue != null && barcode.rawValue!.isNotEmpty) {
        setState(() => _hasScanned = true);
        HapticFeedback.heavyImpact();
        widget.onScanned(barcode.rawValue!);
        Navigator.pop(context, barcode.rawValue);
        break;
      }
    }
  }

  Future<void> _pasteFromClipboard() async {
    final clipboardData = await Clipboard.getData(Clipboard.kTextPlain);
    if (clipboardData?.text != null && clipboardData!.text!.isNotEmpty) {
      HapticFeedback.mediumImpact();
      widget.onScanned(clipboardData.text!);
      Navigator.pop(context, clipboardData.text);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Clipboard is empty'),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.85,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      builder: (context, scrollController) => Container(
        decoration: const BoxDecoration(
          color: Color(0xFF0D1421),
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          children: [
            // Drag handle
            Container(
              margin: const EdgeInsets.only(top: 12),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 20),
            
            // Title
            Text(
              'Scan QR Code',
              style: TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Scan a wallet address or payment QR code',
              style: TextStyle(
                color: Colors.white60,
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 20),
            
            // Scanner or Fallback
            Expanded(
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 20),
                decoration: BoxDecoration(
                  color: const Color(0xFF1A1F2E),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: widget.accentColor.withOpacity(0.3),
                    width: 2,
                  ),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(18),
                  child: _buildScannerContent(),
                ),
              ),
            ),
            
            const SizedBox(height: 20),
            
            // Action buttons
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: [
                  // Flash toggle (mobile only)
                  if (!kIsWeb && _isCameraInitialized)
                    Expanded(
                      child: GestureDetector(
                        onTap: () {
                          HapticFeedback.lightImpact();
                          _cameraController?.toggleTorch();
                          setState(() => _isFlashOn = !_isFlashOn);
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          margin: const EdgeInsets.only(right: 8),
                          decoration: BoxDecoration(
                            color: _isFlashOn 
                                ? widget.accentColor 
                                : const Color(0xFF1A1F2E),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: _isFlashOn 
                                  ? widget.accentColor 
                                  : Colors.white12,
                            ),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                _isFlashOn ? Icons.flash_on : Icons.flash_off,
                                color: _isFlashOn ? Colors.white : Colors.white70,
                                size: 20,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                'Flash',
                                style: TextStyle(
                                  color: _isFlashOn ? Colors.white : Colors.white70,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  
                  // Paste from clipboard
                  Expanded(
                    child: GestureDetector(
                      onTap: _pasteFromClipboard,
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        margin: EdgeInsets.only(left: (!kIsWeb && _isCameraInitialized) ? 8 : 0),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [widget.accentColor, widget.accentColor.withOpacity(0.8)],
                          ),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.content_paste_rounded, color: Colors.white, size: 20),
                            const SizedBox(width: 8),
                            Text(
                              'Paste Address',
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            
            // Cancel button
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: GestureDetector(
                  onTap: () => Navigator.pop(context),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1A1F2E),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      'Cancel',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.white70,
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildScannerContent() {
    // Web fallback - no camera access
    if (kIsWeb) {
      return _buildWebFallback();
    }
    
    // Error state
    if (_errorMessage != null) {
      return _buildErrorState();
    }
    
    // Camera not initialized yet
    if (!_isCameraInitialized || _cameraController == null) {
      return _buildLoadingState();
    }
    
    // Camera scanner
    return Stack(
      children: [
        MobileScanner(
          controller: _cameraController!,
          onDetect: _onDetect,
        ),
        // Scan overlay
        Center(
          child: Container(
            width: 250,
            height: 250,
            decoration: BoxDecoration(
              border: Border.all(
                color: widget.accentColor,
                width: 3,
              ),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Stack(
              children: [
                // Corner decorations
                ...List.generate(4, (index) {
                  final isTop = index < 2;
                  final isLeft = index % 2 == 0;
                  return Positioned(
                    top: isTop ? 0 : null,
                    bottom: !isTop ? 0 : null,
                    left: isLeft ? 0 : null,
                    right: !isLeft ? 0 : null,
                    child: Container(
                      width: 30,
                      height: 30,
                      decoration: BoxDecoration(
                        border: Border(
                          top: isTop 
                              ? BorderSide(color: widget.accentColor, width: 4)
                              : BorderSide.none,
                          bottom: !isTop 
                              ? BorderSide(color: widget.accentColor, width: 4)
                              : BorderSide.none,
                          left: isLeft 
                              ? BorderSide(color: widget.accentColor, width: 4)
                              : BorderSide.none,
                          right: !isLeft 
                              ? BorderSide(color: widget.accentColor, width: 4)
                              : BorderSide.none,
                        ),
                      ),
                    ),
                  );
                }),
              ],
            ),
          ),
        ),
        // Scanning indicator
        Positioned(
          bottom: 20,
          left: 0,
          right: 0,
          child: Center(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.black54,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: widget.accentColor,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Scanning...',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildWebFallback() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(
          Icons.qr_code_scanner_rounded,
          color: widget.accentColor,
          size: 80,
        ),
        const SizedBox(height: 20),
        Text(
          'Camera not available on web',
          style: TextStyle(
            color: Colors.white70,
            fontSize: 16,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Use the paste button below',
          style: TextStyle(
            color: Colors.white54,
            fontSize: 14,
          ),
        ),
      ],
    );
  }

  Widget _buildLoadingState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          CircularProgressIndicator(
            color: widget.accentColor,
          ),
          const SizedBox(height: 16),
          Text(
            'Initializing camera...',
            style: TextStyle(
              color: Colors.white70,
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorState() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(
          Icons.error_outline,
          color: Colors.red,
          size: 60,
        ),
        const SizedBox(height: 16),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Text(
            _errorMessage ?? 'Camera error',
            style: TextStyle(
              color: Colors.white70,
              fontSize: 14,
            ),
            textAlign: TextAlign.center,
          ),
        ),
        const SizedBox(height: 16),
        Text(
          'Use the paste button below',
          style: TextStyle(
            color: Colors.white54,
            fontSize: 12,
          ),
        ),
      ],
    );
  }
}
