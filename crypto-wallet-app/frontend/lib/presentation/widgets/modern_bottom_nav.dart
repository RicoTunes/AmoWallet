import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:ui';
import 'dart:math' as math;

class ModernBottomNav extends StatefulWidget {
  final int currentIndex;
  final Function(int) onTap;
  final VoidCallback? onCenterTap;

  const ModernBottomNav({
    super.key,
    required this.currentIndex,
    required this.onTap,
    this.onCenterTap,
  });

  @override
  State<ModernBottomNav> createState() => _ModernBottomNavState();
}

class _ModernBottomNavState extends State<ModernBottomNav>
    with TickerProviderStateMixin {
  late AnimationController _centerButtonController;
  late AnimationController _navItemController;
  late Animation<double> _centerButtonScale;
  late Animation<double> _centerButtonRotation;
  
  // Track which item is animating to center
  int? _animatingIndex;

  @override
  void initState() {
    super.initState();
    
    _centerButtonController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    
    _navItemController = AnimationController(
      duration: const Duration(milliseconds: 400),
      vsync: this,
    );

    _centerButtonScale = Tween<double>(begin: 1.0, end: 0.85).animate(
      CurvedAnimation(parent: _centerButtonController, curve: Curves.easeOutBack),
    );
    
    _centerButtonRotation = Tween<double>(begin: 0.0, end: 0.25).animate(
      CurvedAnimation(parent: _centerButtonController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _centerButtonController.dispose();
    _navItemController.dispose();
    super.dispose();
  }

  void _onCenterButtonTap() {
    HapticFeedback.mediumImpact();
    _centerButtonController.forward().then((_) {
      _centerButtonController.reverse();
    });
    widget.onCenterTap?.call();
  }

  void _onNavItemTap(int index) {
    HapticFeedback.lightImpact();
    setState(() {
      _animatingIndex = index;
    });
    _navItemController.forward(from: 0).then((_) {
      setState(() {
        _animatingIndex = null;
      });
    });
    widget.onTap(index);
  }

  @override
  Widget build(BuildContext context) {
    // Get bottom padding for safe area
    final bottomPadding = MediaQuery.of(context).padding.bottom;
    
    return Container(
      // Fully transparent container - no black background
      color: Colors.transparent,
      height: 80 + bottomPadding,
      child: Padding(
        padding: EdgeInsets.fromLTRB(16, 0, 16, bottomPadding > 0 ? bottomPadding : 8),
        child: Stack(
          alignment: Alignment.bottomCenter,
          clipBehavior: Clip.none,
          children: [
            // Glassy navigation bar - semi-transparent to see content behind
            Positioned(
              bottom: 0,
                left: 0,
                right: 0,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(28),
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                    child: Container(
                      height: 56,
                      decoration: BoxDecoration(
                        // Glass effect - see content behind
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            const Color(0xFF1A1F2E).withOpacity(0.7),
                            const Color(0xFF0D1421).withOpacity(0.8),
                          ],
                        ),
                        borderRadius: BorderRadius.circular(28),
                        border: Border.all(
                          color: Colors.white.withOpacity(0.12),
                          width: 1,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.15),
                            blurRadius: 20,
                            offset: const Offset(0, -3),
                          ),
                        ],
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceAround,
                        children: [
                          // Left nav item - icon only
                          _buildNavItem(
                            index: 0,
                            icon: Icons.grid_view_rounded,
                          ),
                          // Spacer for center button
                          const SizedBox(width: 60),
                          // Right nav item - icon only
                          _buildNavItem(
                            index: 1,
                            icon: Icons.account_balance_rounded,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            
              // Center floating action button
              Positioned(
                bottom: 16,
                child: _buildCenterButton(),
              ),
            ],
          ),
        ),
      );
  }

  Widget _buildNavItem({
    required int index,
    required IconData icon,
  }) {
    final isActive = widget.currentIndex == index;
    final Color activeColor = const Color(0xFF10B981);
    final Color inactiveColor = Colors.white.withOpacity(0.6);

    return Expanded(
      child: GestureDetector(
        onTap: () => _onNavItemTap(index),
        behavior: HitTestBehavior.opaque,
        child: SizedBox(
          height: 56,
          child: Icon(
            icon,
            color: isActive ? activeColor : inactiveColor,
            size: 26,
          ),
        ),
      ),
    );
  }

  Widget _buildCenterButton() {
    return GestureDetector(
      onTap: _onCenterButtonTap,
      child: AnimatedBuilder(
        animation: _centerButtonController,
        builder: (context, child) {
          return Transform.scale(
            scale: _centerButtonScale.value,
            child: Transform.rotate(
              angle: _centerButtonRotation.value * 2 * math.pi,
              child: Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      Color(0xFF10B981),
                      Color(0xFF059669),
                    ],
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF10B981).withOpacity(0.4),
                      blurRadius: 20,
                      offset: const Offset(0, 8),
                      spreadRadius: 0,
                    ),
                    BoxShadow(
                      color: const Color(0xFF10B981).withOpacity(0.2),
                      blurRadius: 40,
                      offset: const Offset(0, 4),
                      spreadRadius: 5,
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.add_rounded,
                  color: Colors.white,
                  size: 28,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
