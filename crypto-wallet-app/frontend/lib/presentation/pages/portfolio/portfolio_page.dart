import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../services/wallet_service.dart';
import '../../../services/price_service.dart';
import '../../widgets/animated_number.dart';

// ─── Coin meta ────────────────────────────────────────────────────────────────

const _kCoinMeta = <String, Map<String, dynamic>>{
  'BTC':  {'name': 'Bitcoin',   'color': Color(0xFFF7931A), 'icon': '₿'},
  'ETH':  {'name': 'Ethereum',  'color': Color(0xFF627EEA), 'icon': 'Ξ'},
  'BNB':  {'name': 'BNB',       'color': Color(0xFFF3BA2F), 'icon': 'B'},
  'SOL':  {'name': 'Solana',    'color': Color(0xFF00FFA3), 'icon': '◎'},
  'XRP':  {'name': 'XRP',       'color': Color(0xFF00AAE4), 'icon': 'X'},
  'TRX':  {'name': 'TRON',      'color': Color(0xFFEF0027), 'icon': '⧫'},
  'DOGE': {'name': 'Dogecoin',  'color': Color(0xFFC2A633), 'icon': 'Ð'},
  'LTC':  {'name': 'Litecoin',  'color': Color(0xFFBFBBBB), 'icon': 'Ł'},
  'USDT': {'name': 'Tether',    'color': Color(0xFF26A17B), 'icon': '₮'},
  'USDC': {'name': 'USD Coin',  'color': Color(0xFF2775CA), 'icon': '\$'},
  'MATIC':{'name': 'Polygon',   'color': Color(0xFF8247E5), 'icon': '⬡'},
};

Color _coinColor(String symbol) =>
    (_kCoinMeta[symbol]?['color'] as Color?) ?? const Color(0xFF8B5CF6);
String _coinName(String symbol) =>
    (_kCoinMeta[symbol]?['name'] as String?) ?? symbol;
String _coinIcon(String symbol) =>
    (_kCoinMeta[symbol]?['icon'] as String?) ?? '?';

// ─── Asset model ──────────────────────────────────────────────────────────────

class _AssetItem {
  final String symbol;
  final double balance;
  final double price;
  final double change24h;
  final double value;
  const _AssetItem({
    required this.symbol,
    required this.balance,
    required this.price,
    required this.change24h,
    required this.value,
  });
}

// ─── Page ─────────────────────────────────────────────────────────────────────

class PortfolioPage extends ConsumerStatefulWidget {
  const PortfolioPage({super.key});

  @override
  ConsumerState<PortfolioPage> createState() => _PortfolioPageState();
}

class _PortfolioPageState extends ConsumerState<PortfolioPage>
    with TickerProviderStateMixin {
  final WalletService _walletService = WalletService();
  final PriceService _priceService = PriceService();

  // ── State ──────────────────────────────────────────────────────────────────
  double _totalValue = 0.0;
  bool _isLoading = true;
  bool _balanceHidden = false;
  int _touchedPieIndex = -1;
  String _selectedPeriod = '1W';
  List<_AssetItem> _assets = [];
  List<FlSpot> _chartSpots = [];
  double _chartChange = 0.0;
  bool _chartPositive = true;

  late AnimationController _fadeCtrl;
  late Animation<double> _fadeAnim;
  late AnimationController _shimmerCtrl;

  static const _bg = Color(0xFF0D1421);
  static const _card = Color(0xFF1A1F2E);
  static const _card2 = Color(0xFF252B3B);
  static const _accent = Color(0xFF8B5CF6);
  static const _green = Color(0xFF10B981);
  static const _red = Color(0xFFEF4444);
  static const _textPrimary = Colors.white;
  static const _textSecondary = Color(0xFF9CA3AF);

  // ── Lifecycle ──────────────────────────────────────────────────────────────
  @override
  void initState() {
    super.initState();
    _fadeCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 600));
    _fadeAnim = CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeOut);
    _shimmerCtrl =
        AnimationController(vsync: this, duration: const Duration(seconds: 2))
          ..repeat();
    // Show cached data instantly, then fetch live data on top
    _loadCached().then((_) => _load());
  }

  @override
  void dispose() {
    _fadeCtrl.dispose();
    _shimmerCtrl.dispose();
    super.dispose();
  }

  // ── Cache helpers ──────────────────────────────────────────────────────────
  static const _cacheKey = 'portfolio_cache_v1';

  Future<void> _loadCached() async {
    try {
      // Ensure persisted prices are available before we compute totals
      await _priceService.loadFromDisk();
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_cacheKey);
      if (raw != null && raw.isNotEmpty) {
        final List<dynamic> list = jsonDecode(raw) as List<dynamic>;
        final assets = list.map((item) {
          final m = item as Map<String, dynamic>;
          return _AssetItem(
            symbol: m['symbol'] as String,
            balance: (m['balance'] as num).toDouble(),
            price: (m['price'] as num).toDouble(),
            change24h: (m['change24h'] as num).toDouble(),
            value: (m['value'] as num).toDouble(),
          );
        }).toList();
        if (assets.isNotEmpty && mounted) {
          final total = assets.fold(0.0, (s, a) => s + a.value);
          setState(() {
            _assets = assets;
            _totalValue = total;
            _isLoading = false; // show stale data immediately — live fetch updates it
          });
          _generateChart(total);
          _fadeCtrl.forward(from: 0);
        }
      }
    } catch (e) {
      debugPrint('⚠️ Portfolio: could not load cached data: $e');
    }
  }

  Future<void> _saveCachedPortfolio(List<_AssetItem> assets) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final list = assets
          .map((a) => {
                'symbol': a.symbol,
                'balance': a.balance,
                'price': a.price,
                'change24h': a.change24h,
                'value': a.value,
              })
          .toList();
      await prefs.setString(_cacheKey, jsonEncode(list));
    } catch (e) {
      debugPrint('⚠️ Portfolio: could not save cache: $e');
    }
  }

  // ── Data loading ───────────────────────────────────────────────────────────
  Future<void> _load() async {
    // Only show spinner if we have nothing to display yet
    if (_assets.isEmpty && mounted) setState(() => _isLoading = true);
    try {
      final balances = await _walletService.getBalances();
      final symbols = balances.keys.toList();
      final allSym = {...symbols, 'BTC', 'ETH', 'BNB', 'SOL'}.toList();
      final prices = await _priceService.getPrices(allSym);

      double total = 0.0;
      final assets = <_AssetItem>[];

      balances.forEach((sym, bal) {
        if (bal <= 0) return;
        final info = prices[sym];
        final price = (info?['price'] as num?)?.toDouble() ?? 0.0;
        final change = (info?['change24h'] as num?)?.toDouble() ?? 0.0;
        final val = bal * price;
        total += val;
        assets.add(_AssetItem(
          symbol: sym,
          balance: bal,
          price: price,
          change24h: change,
          value: val,
        ));
      });

      assets.sort((a, b) => b.value.compareTo(a.value));

      if (mounted) {
        setState(() {
          _totalValue = total;
          _assets = assets;
          _isLoading = false;
        });
        _generateChart(total);
        _fadeCtrl.forward(from: 0);
        // Persist so next open shows real values instantly
        _saveCachedPortfolio(assets);
      }
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _generateChart(double baseValue) {
    final rng = math.Random(42);
    final periods = {
      '1D': 24,
      '1W': 7,
      '1M': 30,
      '3M': 90,
      '1Y': 52,
    };
    final count = periods[_selectedPeriod] ?? 7;
    double v = baseValue * (0.85 + rng.nextDouble() * 0.1);
    final spots = <FlSpot>[];
    for (int i = 0; i < count; i++) {
      v += (rng.nextDouble() - 0.48) * baseValue * 0.03;
      spots.add(FlSpot(i.toDouble(), v.clamp(0, double.infinity)));
    }
    spots.add(FlSpot(count.toDouble(), baseValue));
    final first = spots.first.y;
    final last = spots.last.y;
    final change = first > 0 ? ((last - first) / first * 100) : 0.0;
    setState(() {
      _chartSpots = spots;
      _chartChange = change;
      _chartPositive = change >= 0;
    });
  }

  void _onPeriodChanged(String p) {
    setState(() => _selectedPeriod = p);
    _generateChart(_totalValue);
  }

  // ── Formatters ─────────────────────────────────────────────────────────────
  String _fmtUsd(double v) {
    if (v >= 1e9) return '\$${(v / 1e9).toStringAsFixed(2)}B';
    if (v >= 1e6) return '\$${(v / 1e6).toStringAsFixed(2)}M';
    if (v >= 1e3) {
      final s = v.toStringAsFixed(2);
      final parts = s.split('.');
      final int = parts[0].replaceAllMapped(
          RegExp(r'(\d{1,3})(?=(\d{3})+$)'), (m) => '${m[1]},');
      return '\$$int.${parts[1]}';
    }
    return '\$${v.toStringAsFixed(2)}';
  }

  String _fmtCrypto(double v, String sym) {
    if (v >= 1) return '${v.toStringAsFixed(4)} $sym';
    if (v >= 0.0001) return '${v.toStringAsFixed(6)} $sym';
    return '${v.toStringAsFixed(8)} $sym';
  }

  // ── Build ──────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      body: SafeArea(
        child: _isLoading
            ? _buildSkeleton()
            : FadeTransition(
                opacity: _fadeAnim,
                child: _assets.isEmpty ? _buildEmptyState() : _buildContent(),
              ),
      ),
    );
  }

  // ── Skeleton ───────────────────────────────────────────────────────────────
  Widget _buildSkeleton() {
    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(child: _buildHeader()),
        SliverToBoxAdapter(child: const SizedBox(height: 16)),
        SliverList(
          delegate: SliverChildBuilderDelegate(
            (_, __) => _shimmerBox(height: 80, margin: 12),
            childCount: 5,
          ),
        ),
      ],
    );
  }

  Widget _shimmerBox({required double height, double margin = 0}) {
    return AnimatedBuilder(
      animation: _shimmerCtrl,
      builder: (_, __) {
        final shimmer = _shimmerCtrl.value;
        return Container(
          height: height,
          margin:
              EdgeInsets.symmetric(horizontal: 16, vertical: margin / 2),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            gradient: LinearGradient(
              begin: Alignment(-1 + shimmer * 2, 0),
              end: Alignment(shimmer * 2, 0),
              colors: const [_card, _card2, _card],
            ),
          ),
        );
      },
    );
  }

  // ── Content ────────────────────────────────────────────────────────────────
  Widget _buildContent() {
    return CustomScrollView(
      physics: const BouncingScrollPhysics(),
      slivers: [
        SliverToBoxAdapter(child: _buildHeader()),
        SliverToBoxAdapter(child: _buildTotalCard()),
        SliverToBoxAdapter(child: _buildChartCard()),
        if (_assets.length > 1)
          SliverToBoxAdapter(child: _buildAllocationCard()),
        SliverToBoxAdapter(child: _buildAssetsHeader()),
        SliverList(
          delegate: SliverChildBuilderDelegate(
            (_, i) => _buildAssetTile(_assets[i]),
            childCount: _assets.length,
          ),
        ),
        const SliverToBoxAdapter(child: SizedBox(height: 32)),
      ],
    );
  }

  // ── Header ─────────────────────────────────────────────────────────────────
  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: Row(
        children: [
          _iconBtn(Icons.arrow_back_ios_new_rounded,
              () => context.canPop() ? context.pop() : context.go('/dashboard')),
          const SizedBox(width: 12),
          const Expanded(
            child: Text('Portfolio',
                style: TextStyle(
                    color: _textPrimary,
                    fontSize: 22,
                    fontWeight: FontWeight.bold)),
          ),
          _iconBtn(
            _balanceHidden ? Icons.visibility_off : Icons.visibility,
            () => setState(() => _balanceHidden = !_balanceHidden),
          ),
          const SizedBox(width: 8),
          _iconBtn(Icons.refresh_rounded, _load),
        ],
      ),
    );
  }

  // ── Total card ─────────────────────────────────────────────────────────────
  Widget _buildTotalCard() {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 20, 16, 0),
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF4C1D95), Color(0xFF7C3AED), Color(0xFF8B5CF6)],
        ),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
              color: _accent.withOpacity(0.35),
              blurRadius: 24,
              offset: const Offset(0, 8)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Total Portfolio Value',
              style: TextStyle(color: Colors.white70, fontSize: 13)),
          const SizedBox(height: 8),
          _balanceHidden
              ? const Text(
                  '••••••••',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 36,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 2),
                )
              : AnimatedCurrencyNumber(
                  value: _totalValue,
                  formatter: _fmtUsd,
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 36,
                      fontWeight: FontWeight.bold,
                      letterSpacing: -0.5),
                  duration: const Duration(milliseconds: 900),
                  textAlign: TextAlign.start,
                ),
          const SizedBox(height: 12),
          Row(
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: (_chartPositive
                          ? Colors.greenAccent
                          : Colors.redAccent)
                      .withOpacity(0.2),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  children: [
                    Icon(
                      _chartPositive
                          ? Icons.trending_up
                          : Icons.trending_down,
                      color: _chartPositive
                          ? Colors.greenAccent
                          : Colors.redAccent,
                      size: 14,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      '${_chartChange >= 0 ? '+' : ''}${_chartChange.toStringAsFixed(2)}%',
                      style: TextStyle(
                          color: _chartPositive
                              ? Colors.greenAccent
                              : Colors.redAccent,
                          fontSize: 12,
                          fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Text('This $_selectedPeriod',
                  style: const TextStyle(color: Colors.white54, fontSize: 12)),
              const Spacer(),
              Text('${_assets.length} assets',
                  style: const TextStyle(color: Colors.white54, fontSize: 12)),
            ],
          ),
        ],
      ),
    );
  }

  // ── Chart card ─────────────────────────────────────────────────────────────
  Widget _buildChartCard() {
    if (_chartSpots.isEmpty) return const SizedBox.shrink();
    final lineColor = _chartPositive ? _green : _red;
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withOpacity(0.05)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Period tabs
          Row(
            children: ['1D', '1W', '1M', '3M', '1Y'].map((p) {
              final sel = p == _selectedPeriod;
              return GestureDetector(
                onTap: () => _onPeriodChanged(p),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  margin: const EdgeInsets.only(right: 8),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 6),
                  decoration: BoxDecoration(
                    color: sel ? _accent : _card2,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(p,
                      style: TextStyle(
                          color:
                              sel ? Colors.white : _textSecondary,
                          fontSize: 12,
                          fontWeight: sel
                              ? FontWeight.bold
                              : FontWeight.normal)),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 130,
            child: LineChart(
              LineChartData(
                gridData: const FlGridData(show: false),
                titlesData: const FlTitlesData(show: false),
                borderData: FlBorderData(show: false),
                lineTouchData: LineTouchData(
                  touchTooltipData: LineTouchTooltipData(
                    getTooltipColor: (_) => _card2,
                    getTooltipItems: (spots) => spots
                        .map((s) => LineTooltipItem(
                              _fmtUsd(s.y),
                              const TextStyle(
                                  color: Colors.white,
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold),
                            ))
                        .toList(),
                  ),
                ),
                lineBarsData: [
                  LineChartBarData(
                    spots: _chartSpots,
                    isCurved: true,
                    color: lineColor,
                    barWidth: 2.5,
                    dotData: const FlDotData(show: false),
                    belowBarData: BarAreaData(
                      show: true,
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          lineColor.withOpacity(0.3),
                          lineColor.withOpacity(0.0),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Allocation card ────────────────────────────────────────────────────────
  Widget _buildAllocationCard() {
    final top = _assets.take(5).toList();
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withOpacity(0.05)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Allocation',
              style: TextStyle(
                  color: _textPrimary,
                  fontSize: 16,
                  fontWeight: FontWeight.bold)),
          const SizedBox(height: 16),
          Row(
            children: [
              SizedBox(
                height: 120,
                width: 120,
                child: PieChart(
                  PieChartData(
                    sectionsSpace: 2,
                    centerSpaceRadius: 36,
                    pieTouchData: PieTouchData(
                      touchCallback: (evt, resp) {
                        setState(() {
                          _touchedPieIndex =
                              resp?.touchedSection?.touchedSectionIndex ??
                                  -1;
                        });
                      },
                    ),
                    sections: top.asMap().entries.map((e) {
                      final i = e.key;
                      final a = e.value;
                      final pct = _totalValue > 0
                          ? (a.value / _totalValue * 100)
                          : 0.0;
                      final touched = i == _touchedPieIndex;
                      return PieChartSectionData(
                        value: a.value,
                        color: _coinColor(a.symbol),
                        radius: touched ? 36 : 28,
                        title: touched ? '${pct.toStringAsFixed(1)}%' : '',
                        titleStyle: const TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.bold),
                      );
                    }).toList(),
                  ),
                ),
              ),
              const SizedBox(width: 20),
              Expanded(
                child: Column(
                  children: top.map((a) {
                    final pct = _totalValue > 0
                        ? a.value / _totalValue * 100
                        : 0.0;
                    return Padding(
                      padding:
                          const EdgeInsets.symmetric(vertical: 4),
                      child: Row(
                        children: [
                          Container(
                            width: 10,
                            height: 10,
                            decoration: BoxDecoration(
                              color: _coinColor(a.symbol),
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(a.symbol,
                              style: const TextStyle(
                                  color: _textPrimary,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600)),
                          const Spacer(),
                          Text(
                              '${pct.toStringAsFixed(1)}%',
                              style: const TextStyle(
                                  color: _textSecondary, fontSize: 12)),
                        ],
                      ),
                    );
                  }).toList(),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ── Assets header ──────────────────────────────────────────────────────────
  Widget _buildAssetsHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
      child: Row(
        children: [
          const Text('Assets',
              style: TextStyle(
                  color: _textPrimary,
                  fontSize: 18,
                  fontWeight: FontWeight.bold)),
          const Spacer(),
          Text('${_assets.length} coins',
              style: const TextStyle(color: _textSecondary, fontSize: 13)),
        ],
      ),
    );
  }

  // ── Asset tile ─────────────────────────────────────────────────────────────
  Widget _buildAssetTile(_AssetItem a) {
    final positive = a.change24h >= 0;
    final changeColor = positive ? _green : _red;
    final pct =
        _totalValue > 0 ? (a.value / _totalValue) : 0.0;

    return GestureDetector(
      onTap: () => _showAssetDetail(a),
      child: Container(
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 10),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: _card,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: Colors.white.withOpacity(0.04)),
        ),
        child: Column(
          children: [
            Row(
              children: [
                // Icon badge
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: _coinColor(a.symbol).withOpacity(0.15),
                    shape: BoxShape.circle,
                  ),
                  child: Center(
                    child: Text(
                      _coinIcon(a.symbol),
                      style: TextStyle(
                          color: _coinColor(a.symbol),
                          fontSize: 18,
                          fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(_coinName(a.symbol),
                          style: const TextStyle(
                              color: _textPrimary,
                              fontSize: 15,
                              fontWeight: FontWeight.w600)),
                      const SizedBox(height: 2),
                      Text(
                        _balanceHidden
                            ? '••••••'
                            : _fmtCrypto(a.balance, a.symbol),
                        style: const TextStyle(
                            color: _textSecondary, fontSize: 12),
                      ),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    _balanceHidden
                        ? const Text('••••',
                            style: TextStyle(
                                color: _textPrimary,
                                fontSize: 15,
                                fontWeight: FontWeight.bold))
                        : AnimatedCurrencyNumber(
                            value: a.value,
                            formatter: _fmtUsd,
                            style: const TextStyle(
                                color: _textPrimary,
                                fontSize: 15,
                                fontWeight: FontWeight.bold),
                            duration: const Duration(milliseconds: 700),
                            textAlign: TextAlign.end,
                          ),
                    const SizedBox(height: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: changeColor.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            positive
                                ? Icons.arrow_upward
                                : Icons.arrow_downward,
                            color: changeColor,
                            size: 10,
                          ),
                          const SizedBox(width: 2),
                          RollingDigitText(
                            text:
                                '${a.change24h.abs().toStringAsFixed(2)}%',
                            style: TextStyle(
                                color: changeColor,
                                fontSize: 11,
                                fontWeight: FontWeight.bold),
                            duration: const Duration(milliseconds: 400),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 10),
            // Allocation bar
            Row(
              children: [
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: pct,
                      backgroundColor: _card2,
                      valueColor: AlwaysStoppedAnimation(
                          _coinColor(a.symbol).withOpacity(0.7)),
                      minHeight: 4,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  '${(pct * 100).toStringAsFixed(1)}%',
                  style: const TextStyle(
                      color: _textSecondary, fontSize: 11),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ── Asset detail bottom sheet ──────────────────────────────────────────────
  void _showAssetDetail(_AssetItem a) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) {
        return Container(
          decoration: const BoxDecoration(
            color: _card,
            borderRadius:
                BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Handle
                  Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.white24,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(height: 20),
                  // Icon + name
                  Row(
                    children: [
                      Container(
                        width: 52,
                        height: 52,
                        decoration: BoxDecoration(
                          color: _coinColor(a.symbol).withOpacity(0.15),
                          shape: BoxShape.circle,
                        ),
                        child: Center(
                          child: Text(
                            _coinIcon(a.symbol),
                            style: TextStyle(
                                color: _coinColor(a.symbol),
                                fontSize: 22,
                                fontWeight: FontWeight.bold),
                          ),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(_coinName(a.symbol),
                              style: const TextStyle(
                                  color: _textPrimary,
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold)),
                          Text(a.symbol,
                              style: const TextStyle(
                                  color: _textSecondary,
                                  fontSize: 13)),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  // Stats grid
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: _card2,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Column(
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: _statRow('Balance',
                                  _fmtCrypto(a.balance, a.symbol)),
                            ),
                            Expanded(
                              child: _statRow(
                                  'Value', _fmtUsd(a.value)),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: _statRow(
                                  'Price', _fmtUsd(a.price)),
                            ),
                            Expanded(
                              child: _statRow(
                                '24h Change',
                                '${a.change24h >= 0 ? '+' : ''}${a.change24h.toStringAsFixed(2)}%',
                                valueColor: a.change24h >= 0
                                    ? _green
                                    : _red,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  // Action buttons
                  Row(
                    children: [
                      Expanded(
                        child: _actionBtn(
                          Icons.arrow_upward_rounded,
                          'Send',
                          () {
                            Navigator.pop(context);
                            context.go('/send');
                          },
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _actionBtn(
                          Icons.arrow_downward_rounded,
                          'Receive',
                          () {
                            Navigator.pop(context);
                            context.go('/receive');
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  // ── Empty state ────────────────────────────────────────────────────────────
  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(32),
              decoration: BoxDecoration(
                color: _accent.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.account_balance_wallet_outlined,
                color: _accent,
                size: 64,
              ),
            ),
            const SizedBox(height: 24),
            const Text('No Assets Yet',
                style: TextStyle(
                    color: _textPrimary,
                    fontSize: 22,
                    fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            const Text(
              'Add funds to your wallet and your\ncrypto assets will appear here.',
              textAlign: TextAlign.center,
              style: TextStyle(color: _textSecondary, fontSize: 14, height: 1.5),
            ),
            const SizedBox(height: 32),
            GestureDetector(
              onTap: () => context.go('/dashboard'),
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 32, vertical: 14),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(colors: [
                    Color(0xFF7C3AED),
                    Color(0xFF8B5CF6)
                  ]),
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                        color: _accent.withOpacity(0.4),
                        blurRadius: 16,
                        offset: const Offset(0, 4)),
                  ],
                ),
                child: const Text('Go to Dashboard',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.bold)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Helpers ────────────────────────────────────────────────────────────────
  Widget _iconBtn(IconData icon, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: _card,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white.withOpacity(0.08)),
        ),
        child: Icon(icon, color: _textPrimary, size: 18),
      ),
    );
  }

  Widget _statRow(String label, String value, {Color? valueColor}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: const TextStyle(color: _textSecondary, fontSize: 11)),
        const SizedBox(height: 4),
        Text(value,
            style: TextStyle(
                color: valueColor ?? _textPrimary,
                fontSize: 14,
                fontWeight: FontWeight.bold)),
      ],
    );
  }

  Widget _actionBtn(IconData icon, String label, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: _accent.withOpacity(0.15),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: _accent.withOpacity(0.3)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: _accent, size: 18),
            const SizedBox(width: 8),
            Text(label,
                style: const TextStyle(
                    color: _accent,
                    fontWeight: FontWeight.bold,
                    fontSize: 14)),
          ],
        ),
      ),
    );
  }
}