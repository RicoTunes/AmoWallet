import 'package:flutter/material.dart';
import 'dart:ui';

class AnimatedBottomNav extends StatefulWidget {
  final int currentIndex;
  final Function(int) onTap;

  const AnimatedBottomNav({
    super.key,
    required this.currentIndex,
    required this.onTap,
  });

  @override
  State<AnimatedBottomNav> createState() => _AnimatedBottomNavState();
}

class _AnimatedBottomNavState extends State<AnimatedBottomNav>
    with TickerProviderStateMixin {
  late List<AnimationController> _controllers;
  late List<Animation<double>> _scaleAnimations;

  @override
  void initState() {
    super.initState();
    _controllers = List.generate(
      3,
      (index) => AnimationController(
        duration: const Duration(milliseconds: 300),
        vsync: this,
      ),
    );

    _scaleAnimations = _controllers.map((controller) {
      return Tween<double>(begin: 1.0, end: 1.2).animate(
        CurvedAnimation(parent: controller, curve: Curves.easeInOut),
      );
    }).toList();

    // Animate the current index
    _controllers[widget.currentIndex].forward();
  }

  @override
  void didUpdateWidget(AnimatedBottomNav oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.currentIndex != widget.currentIndex) {
      _controllers[oldWidget.currentIndex].reverse();
      _controllers[widget.currentIndex].forward();
    }
  }

  @override
  void dispose() {
    for (var controller in _controllers) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardColor = isDark ? const Color(0xFF1A1F2E) : Colors.white;
    final textColor = isDark ? Colors.white : const Color(0xFF1E293B);
    final inactiveColor =
        isDark ? Colors.white.withOpacity(0.4) : const Color(0xFF64748B);
    final borderColor =
        isDark ? Colors.white.withOpacity(0.1) : Colors.black.withOpacity(0.05);

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
          child: Container(
            height: 72,
            decoration: BoxDecoration(
              color: cardColor.withOpacity(0.85),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(
                color: borderColor,
                width: 1,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(isDark ? 0.3 : 0.1),
                  blurRadius: 20,
                  offset: const Offset(0, 5),
                ),
                BoxShadow(
                  color: const Color(0xFF8B5CF6).withOpacity(0.1),
                  blurRadius: 30,
                  spreadRadius: -10,
                ),
              ],
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _buildNavItem(
                  context,
                  index: 0,
                  icon: Icons.dashboard_rounded,
                  label: 'Dashboard',
                  textColor: textColor,
                  inactiveColor: inactiveColor,
                ),
                _buildNavItem(
                  context,
                  index: 1,
                  icon: Icons.pie_chart_rounded,
                  label: 'Portfolio',
                  textColor: textColor,
                  inactiveColor: inactiveColor,
                ),
                _buildNavItem(
                  context,
                  index: 2,
                  icon: Icons.settings_rounded,
                  label: 'Settings',
                  textColor: textColor,
                  inactiveColor: inactiveColor,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildNavItem(
    BuildContext context, {
    required int index,
    required IconData icon,
    required String label,
    required Color textColor,
    required Color inactiveColor,
  }) {
    final isActive = widget.currentIndex == index;

    return Expanded(
      child: GestureDetector(
        onTap: () => widget.onTap(index),
        behavior: HitTestBehavior.opaque,
        child: AnimatedBuilder(
          animation: _controllers[index],
          builder: (context, child) {
            return Column(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Glassy icon container
                AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    gradient: isActive
                        ? LinearGradient(
                            colors: [
                              const Color(0xFF8B5CF6).withOpacity(0.3),
                              const Color(0xFF6366F1).withOpacity(0.2),
                            ],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          )
                        : null,
                    color: isActive ? null : Colors.transparent,
                    borderRadius: BorderRadius.circular(14),
                    border: isActive
                        ? Border.all(
                            color: const Color(0xFF8B5CF6).withOpacity(0.4),
                            width: 1,
                          )
                        : null,
                    boxShadow: isActive
                        ? [
                            BoxShadow(
                              color: const Color(0xFF8B5CF6).withOpacity(0.3),
                              blurRadius: 12,
                              spreadRadius: -2,
                            ),
                          ]
                        : null,
                  ),
                  child: Icon(
                    icon,
                    color: isActive ? Colors.white : inactiveColor,
                    size: 22,
                  ),
                ),
                const SizedBox(height: 4),
                // Label
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: isActive ? FontWeight.w600 : FontWeight.w500,
                    color: isActive ? textColor : inactiveColor,
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
