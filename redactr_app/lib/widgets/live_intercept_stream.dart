import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import '../theme/app_theme.dart';

// ─────────────────────────────────────────────────────────────────────────────
// LiveInterceptStream
//
// Ambient background canvas that shows data nodes floating upward.
// When a sensitive node crosses the "intercept layer" membrane it morphs
// to [REDACTED] with a brief teal flash, visually showing Redactr working.
//
// All opacity levels are intentionally very low so the content above
// stays readable — this is ambiance, not foreground UI.
// ─────────────────────────────────────────────────────────────────────────────

class LiveInterceptStream extends StatefulWidget {
  const LiveInterceptStream({
    super.key,
    required this.logoFilterRect,
    required this.onIntercept,
  });

  final Rect? logoFilterRect;
  final VoidCallback onIntercept;

  @override
  State<LiveInterceptStream> createState() => _LiveInterceptStreamState();
}

// ── Data node model ───────────────────────────────────────────────────────────

class _Node {
  bool isSensitive;
  String rawText;
  final double xFrac; // 0..1 of screen width
  final double speed; // px / second
  final double fontSize;
  double y; // current y, from top (increases upward = decreasing y)
  bool intercepted = false;
  double flashT = 0; // 1→0 flash timer

  _Node({
    required this.isSensitive,
    required this.rawText,
    required this.xFrac,
    required this.speed,
    required this.fontSize,
    required this.y,
  });
}

// ── State ─────────────────────────────────────────────────────────────────────

class _LiveInterceptStreamState extends State<LiveInterceptStream>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  final _nodes = <_Node>[];
  Duration _lastElapsed = Duration.zero;
  Size _size = Size.zero;
  bool _initialized = false;
  double _glowPhase = 0;
  Rect? _localLogoRect;
  bool _needsLogoRectUpdate = true;

  static const _safeLabels = [
    'sys_ping: 12ms',
    'auth: ok',
    'GET /api/v2',
    'tls: ok',
    'hash: a3f7..',
    'status: 200',
    'cache: hit',
    'conn: alive',
    'req: #7714',
    'worker: #3',
    'queue: 0',
    'token: valid',
    'dns: resolved',
    'latency: 4ms',
  ];

  static const _sensitiveLabels = [
    'API_KEY: 8492..',
    'SSN: 842-0..',
    'CARD: 4532..',
    'EMAIL: j.doe@',
    'AWS: AKIA..',
    'TOKEN: eyJ0..',
    'SECRET: sk-..',
    'PASSWD: ••••',
    'CVV: 392',
    'PAN: 5412..',
    'IBAN: GB29..',
    'DOB: 1987-..',
  ];

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_onTick)..start();
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  void _init() {
    final rng = math.Random();
    _nodes.clear();
    for (int i = 0; i < 22; i++) {
      _nodes.add(_makeNode(rng, initialY: rng.nextDouble() * _size.height));
    }
    _initialized = true;
  }

  _Node _makeNode(math.Random rng, {double? initialY}) {
    final sensitive = rng.nextDouble() > 0.52;
    final list = sensitive ? _sensitiveLabels : _safeLabels;
    return _Node(
      isSensitive: sensitive,
      rawText: list[rng.nextInt(list.length)],
      xFrac: 0.02 + rng.nextDouble() * 0.86,
      speed: 28 + rng.nextDouble() * 44,
      fontSize: 8.5 + rng.nextDouble() * 3.0,
      y: initialY ?? (_size.height + 20 + rng.nextDouble() * 100),
    );
  }

  Rect? _computeLocalLogoRect() {
    if (widget.logoFilterRect == null) return null;
    final render = context.findRenderObject();
    if (render is RenderBox) {
      return Rect.fromPoints(
        render.globalToLocal(widget.logoFilterRect!.topLeft),
        render.globalToLocal(widget.logoFilterRect!.bottomRight),
      );
    }
    return null;
  }

  @override
  void didUpdateWidget(covariant LiveInterceptStream oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.logoFilterRect != widget.logoFilterRect) {
      _needsLogoRectUpdate = true;
    }
  }

  void _updateLocalLogoRect() {
    final rect = _computeLocalLogoRect();
    if (rect != _localLogoRect) {
      _localLogoRect = rect;
    }
    _needsLogoRectUpdate = false;
  }

  void _onTick(Duration elapsed) {
    if (!mounted || _size == Size.zero) return;
    if (!_initialized) _init();

    final dt = (elapsed - _lastElapsed).inMilliseconds / 1000.0;
    _lastElapsed = elapsed;

    _glowPhase = (_glowPhase + dt * 0.7) % (2 * math.pi);
    final rng = math.Random();

    for (final node in _nodes) {
      node.y -= node.speed * dt;

      if (node.isSensitive && !node.intercepted && _localLogoRect != null) {
        final filterTop = _localLogoRect!.top;
        final filterBottom = _localLogoRect!.bottom;
        if (node.y <= filterBottom && node.y >= filterTop - 12) {
          node.intercepted = true;
          node.flashT = 1.0;
          widget.onIntercept();
        }
      }

      if (node.flashT > 0) {
        node.flashT = (node.flashT - dt * 2.2).clamp(0.0, 1.0);
      }

      if (node.y < -28) {
        final n2 = _makeNode(rng);
        node
          ..isSensitive = n2.isSensitive
          ..rawText = n2.rawText
          ..y = n2.y
          ..intercepted = false
          ..flashT = 0;
      }
    }

    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    if (_needsLogoRectUpdate) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _updateLocalLogoRect();
      });
    }
    return LayoutBuilder(
      builder: (ctx, constraints) {
        final newSize = Size(constraints.maxWidth, constraints.maxHeight);
        if (newSize != _size) {
          _size = newSize;
          if (!_initialized) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) setState(_init);
            });
          }
        }
        return RepaintBoundary(
          child: CustomPaint(
            painter: _StreamPainter(
              nodes: List.of(_nodes),
              glowPhase: _glowPhase,
              screenW: _size.width,
            ),
            size: _size,
          ),
        );
      },
    );
  }
}

// ── Painter ───────────────────────────────────────────────────────────────────

class _StreamPainter extends CustomPainter {
  final List<_Node> nodes;
  final double glowPhase;
  final double screenW;

  const _StreamPainter({
    required this.nodes,
    required this.glowPhase,
    required this.screenW,
  });

  @override
  void paint(Canvas canvas, Size size) {
    for (final node in nodes) {
      if (node.y > -28 && node.y < size.height + 20) {
        _drawNode(canvas, size, node);
      }
    }
  }

  void _drawNode(Canvas canvas, Size size, _Node node) {
    final String text;
    final Color color;
    final FontWeight weight;

    if (node.intercepted) {
      text = '[REDACTED]';
      weight = FontWeight.w700;
      // Bright during flash, then settles to a dim teal
      color = AppColors.primary.withValues(alpha: 0.17 + 0.38 * node.flashT);
    } else if (node.isSensitive) {
      text = node.rawText;
      weight = FontWeight.w400;
      color = AppColors.danger.withValues(alpha: 0.11);
    } else {
      text = node.rawText;
      weight = FontWeight.w400;
      color = AppColors.textMuted.withValues(alpha: 0.08);
    }

    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: color,
          fontSize: node.fontSize,
          fontWeight: weight,
          fontFamily: 'monospace',
          letterSpacing: node.intercepted ? 0.6 : 0.0,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: screenW * 0.45);

    final x = node.xFrac * screenW;
    tp.paint(canvas, Offset(x, node.y));

    // Bloom behind freshly-intercepted text
    if (node.intercepted && node.flashT > 0.05) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(x - 5, node.y - 3, tp.width + 10, tp.height + 5),
          const Radius.circular(3),
        ),
        Paint()
          ..color = AppColors.primary.withValues(alpha: 0.06 * node.flashT)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10),
      );
    }
  }

  @override
  bool shouldRepaint(_StreamPainter old) => true;
}
