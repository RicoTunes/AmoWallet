import 'package:flutter/material.dart';

/// Animates a numeric value by smoothly counting from the old value to the
/// new one — just like the Exodus wallet or YouTube live subscriber counter.
///
/// Two variants are exposed:
///  • [AnimatedNumber]  — smooth tween count-up/count-down for any double.
///  • [RollingDigitText] — per-character slot-machine roll (digits slide up
///    or down when a digit value changes), perfect for prices.
///
/// Usage:
///   AnimatedNumber(
///     value: _totalPortfolioValue,
///     formatter: (v) => '\$${v.toStringAsFixed(2)}',
///     style: TextStyle(fontSize: 48, fontWeight: FontWeight.bold),
///   )

// ─────────────────────────────────────────────────────────────────────────────
// 1.  AnimatedNumber  (smooth numeric tween — great for big totals)
// ─────────────────────────────────────────────────────────────────────────────

class AnimatedNumber extends StatefulWidget {
  const AnimatedNumber({
    super.key,
    required this.value,
    required this.formatter,
    required this.style,
    this.duration = const Duration(milliseconds: 700),
    this.curve = Curves.easeOutCubic,
    this.textAlign,
  });

  final double value;
  final String Function(double) formatter;
  final TextStyle style;
  final Duration duration;
  final Curve curve;
  final TextAlign? textAlign;

  @override
  State<AnimatedNumber> createState() => _AnimatedNumberState();
}

class _AnimatedNumberState extends State<AnimatedNumber>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _anim;
  double _from = 0;
  double _to = 0;

  @override
  void initState() {
    super.initState();
    _from = widget.value;
    _to = widget.value;
    _ctrl = AnimationController(vsync: this, duration: widget.duration);
    _anim = Tween(begin: _from, end: _to).animate(
      CurvedAnimation(parent: _ctrl, curve: widget.curve),
    );
  }

  @override
  void didUpdateWidget(AnimatedNumber old) {
    super.didUpdateWidget(old);
    if (old.value != widget.value) {
      _from = _anim.value; // start from wherever we currently are
      _to = widget.value;
      _anim = Tween(begin: _from, end: _to).animate(
        CurvedAnimation(parent: _ctrl, curve: widget.curve),
      );
      _ctrl.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _anim,
      builder: (_, __) => Text(
        widget.formatter(_anim.value),
        style: widget.style,
        textAlign: widget.textAlign,
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 2.  RollingDigitText  (per-digit slot-machine effect — great for prices)
//     Each digit that changes slides up or down to its new value, while
//     unchanged characters stay perfectly still.
// ─────────────────────────────────────────────────────────────────────────────

class RollingDigitText extends StatefulWidget {
  const RollingDigitText({
    super.key,
    required this.text,
    required this.style,
    this.duration = const Duration(milliseconds: 450),
    this.curve = Curves.easeOutCubic,
    this.textAlign = TextAlign.end,
  });

  final String text;
  final TextStyle style;
  final Duration duration;
  final Curve curve;
  final TextAlign textAlign;

  @override
  State<RollingDigitText> createState() => _RollingDigitTextState();
}

class _RollingDigitTextState extends State<RollingDigitText> {
  String _previous = '';
  String _current = '';

  @override
  void initState() {
    super.initState();
    _previous = widget.text;
    _current = widget.text;
  }

  @override
  void didUpdateWidget(RollingDigitText old) {
    super.didUpdateWidget(old);
    if (old.text != widget.text) {
      setState(() {
        _previous = old.text;
        _current = widget.text;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    // Align by padding the shorter string on the left with spaces so indices line up.
    final prev = _previous;
    final curr = _current;
    final maxLen = curr.length > prev.length ? curr.length : prev.length;
    final paddedPrev = prev.padLeft(maxLen);
    final paddedCurr = curr.padLeft(maxLen);

    return Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: widget.textAlign == TextAlign.end
          ? MainAxisAlignment.end
          : MainAxisAlignment.start,
      children: List.generate(maxLen, (i) {
        final cPrev = i < paddedPrev.length ? paddedPrev[i] : ' ';
        final cCurr = i < paddedCurr.length ? paddedCurr[i] : ' ';
        if (cPrev == cCurr) {
          // Unchanged character — no animation
          return _StaticChar(char: cCurr, style: widget.style);
        }
        // Changed character — slide animation
        return _AnimatedChar(
          from: cPrev,
          to: cCurr,
          style: widget.style,
          duration: widget.duration,
          curve: widget.curve,
        );
      }),
    );
  }
}

// ── Unchanged character ──────────────────────────────────────────────────────

class _StaticChar extends StatelessWidget {
  const _StaticChar({required this.char, required this.style});
  final String char;
  final TextStyle style;

  @override
  Widget build(BuildContext context) {
    if (char == ' ') {
      // Invisible spacer that still occupies the same width as a zero.
      return Opacity(
        opacity: 0,
        child: Text('0', style: style),
      );
    }
    return Text(char, style: style);
  }
}

// ── Animated (changed) character ─────────────────────────────────────────────

class _AnimatedChar extends StatefulWidget {
  const _AnimatedChar({
    required this.from,
    required this.to,
    required this.style,
    required this.duration,
    required this.curve,
  });
  final String from;
  final String to;
  final TextStyle style;
  final Duration duration;
  final Curve curve;

  @override
  State<_AnimatedChar> createState() => _AnimatedCharState();
}

class _AnimatedCharState extends State<_AnimatedChar>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: widget.duration);
    _anim = CurvedAnimation(parent: _ctrl, curve: widget.curve);
    _ctrl.forward();
  }

  @override
  void didUpdateWidget(_AnimatedChar old) {
    super.didUpdateWidget(old);
    if (old.from != widget.from || old.to != widget.to) {
      _ctrl.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  /// Return true if going from a digit to a higher digit (or non-digit to digit)
  bool _isGoingUp() {
    final f = int.tryParse(widget.from) ?? -1;
    final t = int.tryParse(widget.to) ?? 10;
    return t > f;
  }

  @override
  Widget build(BuildContext context) {
    // Calculate character height from the style for proper clipping.
    final charHeight = (widget.style.fontSize ?? 16) * 1.25;
    final goingUp = _isGoingUp();

    return SizedBox(
      height: charHeight,
      child: ClipRect(
        child: AnimatedBuilder(
          animation: _anim,
          builder: (_, __) {
            final t = _anim.value;
            // "going up" = new digit slides in from bottom, old slides out top
            // "going down" = new digit slides in from top, old slides out bottom
            final outOffset = goingUp ? -t : t;
            final inOffset = goingUp ? 1.0 - t : -(1.0 - t);
            return Stack(
              children: [
                // Outgoing character
                Transform.translate(
                  offset: Offset(0, outOffset * charHeight),
                  child: Opacity(
                    opacity: (1.0 - t).clamp(0.0, 1.0),
                    child: Text(widget.from, style: widget.style),
                  ),
                ),
                // Incoming character
                Transform.translate(
                  offset: Offset(0, inOffset * charHeight),
                  child: Opacity(
                    opacity: t.clamp(0.0, 1.0),
                    child: Text(widget.to, style: widget.style),
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

// ─────────────────────────────────────────────────────────────────────────────
// 3.  AnimatedCurrencyNumber
//     Combines a smooth double tween with the rolling-digit display.
//     Best of both worlds: the formatted string updates smoothly (via tween)
//     AND each digit is animated independently.
// ─────────────────────────────────────────────────────────────────────────────

class AnimatedCurrencyNumber extends StatefulWidget {
  const AnimatedCurrencyNumber({
    super.key,
    required this.value,
    required this.formatter,
    required this.style,
    this.duration = const Duration(milliseconds: 700),
    this.curve = Curves.easeOutCubic,
    this.textAlign = TextAlign.end,
  });

  final double value;
  final String Function(double) formatter;
  final TextStyle style;
  final Duration duration;
  final Curve curve;
  final TextAlign textAlign;

  @override
  State<AnimatedCurrencyNumber> createState() =>
      _AnimatedCurrencyNumberState();
}

class _AnimatedCurrencyNumberState extends State<AnimatedCurrencyNumber>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _anim;
  double _from = 0;
  double _to = 0;

  @override
  void initState() {
    super.initState();
    _from = widget.value;
    _to = widget.value;
    _ctrl = AnimationController(vsync: this, duration: widget.duration);
    _anim = Tween(begin: _from, end: _to).animate(
      CurvedAnimation(parent: _ctrl, curve: widget.curve),
    );
  }

  @override
  void didUpdateWidget(AnimatedCurrencyNumber old) {
    super.didUpdateWidget(old);
    if (old.value != widget.value) {
      _from = _anim.value;
      _to = widget.value;
      _anim = Tween(begin: _from, end: _to).animate(
        CurvedAnimation(parent: _ctrl, curve: widget.curve),
      );
      _ctrl.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _anim,
      builder: (_, __) => RollingDigitText(
        text: widget.formatter(_anim.value),
        style: widget.style,
        duration: const Duration(milliseconds: 180),
        textAlign: widget.textAlign,
      ),
    );
  }
}
