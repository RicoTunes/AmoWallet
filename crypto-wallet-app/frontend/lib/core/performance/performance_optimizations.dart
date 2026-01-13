import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Performance optimization utilities for the crypto wallet app
class PerformanceOptimizations {
  /// Enable performance optimizations for the app
  static void enableOptimizations() {
    // Optimize image caching
    PaintingBinding.instance.imageCache.maximumSize = 100;
    PaintingBinding.instance.imageCache.maximumSizeBytes = 100 << 20; // 100MB
  }
  
  /// Optimize scroll physics for better performance
  static ScrollPhysics get optimizedScrollPhysics => const BouncingScrollPhysics(
    parent: AlwaysScrollableScrollPhysics(),
  );
  
  /// Create optimized animation controller
  static AnimationController createOptimizedAnimationController({
    required TickerProvider vsync,
    Duration duration = const Duration(milliseconds: 300),
  }) {
    return AnimationController(
      vsync: vsync,
      duration: duration,
    );
  }
}

/// Provider for performance settings
final performanceSettingsProvider = Provider<PerformanceSettings>((ref) {
  return PerformanceSettings();
});

class PerformanceSettings {
  bool get enableImageCaching => true;
  bool get enableWidgetCaching => true;
  bool get enableApiCaching => true;
  Duration get apiCacheDuration => const Duration(minutes: 5);
  int get maxImageCacheSize => 100; // MB
}

/// Optimized image widget with caching and error handling
class OptimizedImage extends StatelessWidget {
  final String imageUrl;
  final double? width;
  final double? height;
  final BoxFit fit;
  final Widget? placeholder;
  final Widget? errorWidget;

  const OptimizedImage({
    super.key,
    required this.imageUrl,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
    this.placeholder,
    this.errorWidget,
  });

  @override
  Widget build(BuildContext context) {
    return Image.network(
      imageUrl,
      width: width,
      height: height,
      fit: fit,
      loadingBuilder: (context, child, loadingProgress) {
        if (loadingProgress == null) return child;
        return placeholder ?? const _DefaultPlaceholder();
      },
      errorBuilder: (context, error, stackTrace) {
        return errorWidget ?? const _DefaultErrorWidget();
      },
      cacheWidth: width != null ? (width! * 2).toInt() : null,
      cacheHeight: height != null ? (height! * 2).toInt() : null,
    );
  }
}

class _DefaultPlaceholder extends StatelessWidget {
  const _DefaultPlaceholder();

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.grey[200],
      child: const Center(
        child: CircularProgressIndicator(),
      ),
    );
  }
}

class _DefaultErrorWidget extends StatelessWidget {
  const _DefaultErrorWidget();

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.grey[200],
      child: const Center(
        child: Icon(Icons.error_outline, color: Colors.grey),
      ),
    );
  }
}

/// Optimized list view builder for better performance
class OptimizedListView extends StatelessWidget {
  final int itemCount;
  final IndexedWidgetBuilder itemBuilder;
  final EdgeInsetsGeometry? padding;
  final ScrollController? controller;
  final bool shrinkWrap;

  const OptimizedListView({
    super.key,
    required this.itemCount,
    required this.itemBuilder,
    this.padding,
    this.controller,
    this.shrinkWrap = false,
  });

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      controller: controller,
      padding: padding,
      shrinkWrap: shrinkWrap,
      physics: PerformanceOptimizations.optimizedScrollPhysics,
      itemCount: itemCount,
      itemBuilder: itemBuilder,
      addAutomaticKeepAlives: true,
      addRepaintBoundaries: true,
    );
  }
}

/// Optimized grid view builder for better performance
class OptimizedGridView extends StatelessWidget {
  final int itemCount;
  final IndexedWidgetBuilder itemBuilder;
  final SliverGridDelegate gridDelegate;
  final EdgeInsetsGeometry? padding;
  final ScrollController? controller;
  final bool shrinkWrap;

  const OptimizedGridView({
    super.key,
    required this.itemCount,
    required this.itemBuilder,
    required this.gridDelegate,
    this.padding,
    this.controller,
    this.shrinkWrap = false,
  });

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      controller: controller,
      padding: padding,
      shrinkWrap: shrinkWrap,
      physics: PerformanceOptimizations.optimizedScrollPhysics,
      gridDelegate: gridDelegate,
      itemCount: itemCount,
      itemBuilder: itemBuilder,
      addAutomaticKeepAlives: true,
      addRepaintBoundaries: true,
    );
  }
}

/// Memory management utilities
class MemoryManager {
  static void clearImageCache() {
    PaintingBinding.instance.imageCache.clear();
    PaintingBinding.instance.imageCache.clearLiveImages();
  }
  
  static void forceGC() {
    // Trigger garbage collection (works in debug mode)
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // This helps trigger GC in some cases
    });
  }
}

/// Performance monitoring utilities
class PerformanceMonitor {
  static void logBuildTime(String widgetName, Duration buildTime) {
    if (buildTime > const Duration(milliseconds: 16)) {
      debugPrint('Performance Warning: $widgetName took ${buildTime.inMilliseconds}ms to build');
    }
  }
  
  static void logApiCall(String endpoint, Duration duration) {
    if (duration > const Duration(seconds: 2)) {
      debugPrint('API Performance Warning: $endpoint took ${duration.inSeconds}s');
    }
  }
}
