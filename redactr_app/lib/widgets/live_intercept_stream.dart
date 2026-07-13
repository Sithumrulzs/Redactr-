import 'dart:math' as math;
import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import '../theme/app_theme.dart';

// ── Constants ─────────────────────────────────────────────────────────────────
const int    _kNodeCount            = 13;
const double _kSensitiveProbability = 0.18;
const int    _kSensitiveCap         = 2;
const double _kApproachZone         = 140.0; // px below logo bottom where attraction begins
const double _kAttractionFactor     = 0.12;  // per-tick lerp strength at full approach depth

// ─────────────────────────────────────────────────────────────────────────────
// LiveInterceptStream
//
// Ambient background canvas: data nodes float upward in straight lines.
// Sensitive nodes bend toward the logo membrane as they approach and are
// absorbed at its edge — triggering the dashboard's sonar ping.
// Safe nodes never deviate.
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
  bool   isSensitive;
  String rawText;
  final double xFrac; // 0..1 seed — only used to initialize x
  double x;           // live canvas x, mutable for attraction
  final double speed;
  final double fontSize;
  double y;
  bool   intercepted = false;
  double flashT      = 0.0; // 1→0 post-intercept flash timer

  // TextPainter cache: rebuilt only when layout-affecting state changes
  TextPainter? _tp;
  String _tpKey        = '';   // '${rawText}:${intercepted}:${fontSize}'
  double _tpLastFlashT = -1.0; // last flashT used for color; updated on >0.01 delta

  _Node({
    required this.isSensitive,
    required this.rawText,
    required this.xFrac,
    required this.x,
    required this.speed,
    required this.fontSize,
    required this.y,
  });
}

// ── Repaint notifier — canvas ticks without rebuilding the widget tree ─────────

class _StreamRepaint extends ChangeNotifier {
  void tick() => notifyListeners();
}

// ── State ─────────────────────────────────────────────────────────────────────

class _LiveInterceptStreamState extends State<LiveInterceptStream>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final Ticker _ticker;
  final _repaint = _StreamRepaint();
  final _nodes   = <_Node>[];

  Duration _lastElapsed     = Duration.zero;
  Size     _size            = Size.zero;
  bool     _initialized     = false;
  double   _glowPhase       = 0;
  Rect?    _localLogoRect;
  bool     _needsLogoRectUpdate = true;

  // Pause guards
  bool _appActive      = true;
  bool _isRouteCurrent = true;
  bool _reduceMotion   = false;
  int  _tickCount      = 0;

  // ── Labels ──────────────────────────────────────────────────────────────────

  static const _safeLabels = [
    'sys_ping: 12ms', 'auth: ok', 'GET /api/v2', 'tls: ok',
    'hash: a3f7..', 'status: 200', 'cache: hit', 'conn: alive',
    'req: #7714', 'worker: #3', 'queue: 0', 'token: valid',
    'dns: resolved', 'latency: 4ms',
  ];

  static const _sensitiveLabels = [
    'API_KEY: 8492..', 'SSN: 842-0..', 'CARD: 4532..',
    'EMAIL: j.doe@', 'AWS: AKIA..', 'TOKEN: eyJ0..',
    'SECRET: sk-..', 'PASSWD: ••••', 'CVV: 392',
    'PAN: 5412..', 'IBAN: GB29..', 'DOB: 1987-..',
  ];

  // ── Lifecycle ────────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _ticker = createTicker(_onTick);
    // Started in _updateTickerState, called from didChangeDependencies
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduceMotion   = MediaQuery.disableAnimationsOf(context);
    _isRouteCurrent = ModalRoute.of(context)?.isCurrent ?? true;
    _updateTickerState();
  }

  @override
  void didUpdateWidget(covariant LiveInterceptStream old) {
    super.didUpdateWidget(old);
    if (old.logoFilterRect != widget.logoFilterRect) {
      _needsLogoRectUpdate = true;
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _ticker.dispose();
    _repaint.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _appActive = state == AppLifecycleState.resumed;
    _updateTickerState();
  }

  void _updateTickerState() {
    final shouldRun = !_reduceMotion && _appActive && _isRouteCurrent;
    if (shouldRun && !_ticker.isActive) {
      _lastElapsed = Duration.zero; // reset dt on resume to avoid spike
      _ticker.start();
    } else if (!shouldRun && _ticker.isActive) {
      _ticker.stop();
    }
  }

  // ── Node factory ─────────────────────────────────────────────────────────────

  void _init() {
    _nodes.clear();
    final rng = math.Random();
    for (int i = 0; i < _kNodeCount; i++) {
      _nodes.add(_makeNode(rng, initialY: rng.nextDouble() * _size.height));
    }
    _initialized = true;
  }

  // Counts sensitive un-intercepted nodes, optionally excluding one being recycled.
  int _liveSensitiveCount({_Node? excluding}) => _nodes
      .where((n) => n.isSensitive && !n.intercepted && n != excluding)
      .length;

  _Node _makeNode(math.Random rng, {double? initialY}) {
    final forceSafe = _liveSensitiveCount() >= _kSensitiveCap;
    final sensitive = !forceSafe && (rng.nextDouble() < _kSensitiveProbability);
    final list      = sensitive ? _sensitiveLabels : _safeLabels;
    final xFrac     = 0.02 + rng.nextDouble() * 0.86;
    return _Node(
      isSensitive: sensitive,
      rawText:     list[rng.nextInt(list.length)],
      xFrac:       xFrac,
      x:           xFrac * _size.width,
      speed:       28 + rng.nextDouble() * 44,
      fontSize:    8.5 + rng.nextDouble() * 3.0,
      y:           initialY ?? (_size.height + 20 + rng.nextDouble() * 100),
    );
  }

  // ── Logo rect ────────────────────────────────────────────────────────────────

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

  void _updateLocalLogoRect() {
    final rect = _computeLocalLogoRect();
    if (rect != _localLogoRect) _localLogoRect = rect;
    _needsLogoRectUpdate = false;
  }

  // ── Tick ─────────────────────────────────────────────────────────────────────

  void _onTick(Duration elapsed) {
    if (!mounted || _size == Size.zero) return;
    if (!_initialized) _init();

    // Periodic route guard — ModalRoute.isCurrent changes on push/pop but
    // may not always trigger didChangeDependencies, so we double-check here.
    _tickCount++;
    if (_tickCount % 90 == 0) {
      final cur = ModalRoute.of(context)?.isCurrent ?? true;
      if (cur != _isRouteCurrent) {
        _isRouteCurrent = cur;
        if (!_isRouteCurrent) {
          _ticker.stop();
          return;
        }
      }
    }

    final dt = (elapsed - _lastElapsed).inMilliseconds / 1000.0;
    _lastElapsed = elapsed;
    // Skip bad frames (first tick, resume spike, or tab-away stall)
    if (dt <= 0 || dt > 0.1) {
      _repaint.tick();
      return;
    }

    _glowPhase = (_glowPhase + dt * 0.7) % (2 * math.pi);
    final rng  = math.Random();

    for (final node in _nodes) {
      node.y -= node.speed * dt;

      // Horizontal attraction + absorption for sensitive un-intercepted nodes
      if (node.isSensitive && !node.intercepted && _localLogoRect != null) {
        final approachStart = _localLogoRect!.bottom + _kApproachZone;

        if (node.y < approachStart) {
          final logoCenterX = _localLogoRect!.center.dx;
          // t = 0 at zone entry, 1 at logo bottom — attraction strengthens with depth
          final t = ((approachStart - node.y) / _kApproachZone).clamp(0.0, 1.0);
          node.x = lerpDouble(
            node.x,
            logoCenterX,
            Curves.easeIn.transform(t) * _kAttractionFactor,
          )!;

          // Absorb only when the node's x is within the logo's horizontal extent
          // AND y has entered the membrane band.
          final withinX = node.x >= _localLogoRect!.left &&
                          node.x <= _localLogoRect!.right;
          if (withinX &&
              node.y <= _localLogoRect!.bottom &&
              node.y >= _localLogoRect!.top - 12) {
            node.intercepted = true;
            node.flashT      = 1.0;
            node._tpKey      = ''; // force TextPainter rebuild: text+style changed
            widget.onIntercept();
          }
        }
      }

      // Decay flash timer
      if (node.flashT > 0) {
        node.flashT = (node.flashT - dt * 2.2).clamp(0.0, 1.0);
      }

      // Recycle nodes that have scrolled off the top
      if (node.y < -28) {
        final activeSensitive = _liveSensitiveCount(excluding: node);
        final forceSafe       = activeSensitive >= _kSensitiveCap;
        final sensitive       = !forceSafe && (rng.nextDouble() < _kSensitiveProbability);
        final list            = sensitive ? _sensitiveLabels : _safeLabels;
        final xFrac           = 0.02 + rng.nextDouble() * 0.86;
        node
          ..isSensitive = sensitive
          ..rawText     = list[rng.nextInt(list.length)]
          ..x           = xFrac * _size.width
          ..y           = _size.height + 20 + rng.nextDouble() * 100
          ..intercepted = false
          ..flashT      = 0.0
          .._tpKey      = ''; // invalidate: rawText changed
      }
    }

    _repaint.tick(); // only the canvas repaints — widget tree stays intact
  }

  // ── Build ────────────────────────────────────────────────────────────────────

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
          // Re-init nodes with correct x coordinates for the new width.
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) setState(_init);
          });
        } else if (!_initialized && _size != Size.zero) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted && !_initialized) setState(_init);
          });
        }

        return RepaintBoundary(
          child: CustomPaint(
            painter: _StreamPainter(
              nodes: _nodes,
              screenW: _size.width,
              repaint: _reduceMotion ? null : _repaint,
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
  // nodes is the live list reference — no copy, so the canvas always sees
  // the latest node state when repaint fires from _StreamRepaint.tick().
  final List<_Node> nodes;
  final double screenW;

  _StreamPainter({required this.nodes, required this.screenW, super.repaint});

  @override
  void paint(Canvas canvas, Size size) {
    for (final node in nodes) {
      if (node.y > -28 && node.y < size.height + 20) {
        _drawNode(canvas, node);
      }
    }
  }

  static Color _colorFor(_Node node) {
    if (node.intercepted) {
      return AppColors.primary.withValues(alpha: 0.17 + 0.38 * node.flashT);
    }
    if (node.isSensitive) {
      return AppColors.danger.withValues(alpha: 0.11);
    }
    return AppColors.textMuted.withValues(alpha: 0.08);
  }

  void _drawNode(Canvas canvas, _Node node) {
    final displayText = node.intercepted ? '[REDACTED]' : node.rawText;
    final weight      = node.intercepted ? FontWeight.w700 : FontWeight.w400;
    final color       = _colorFor(node);

    // Key covers layout-affecting properties: text content, intercepted state,
    // and font size. Color (flashT) is handled separately below.
    final tpKey = '${node.rawText}:${node.intercepted}:${node.fontSize.toStringAsFixed(1)}';

    if (node._tp == null || node._tpKey != tpKey) {
      // Full rebuild: text or intercepted state changed
      node._tpKey        = tpKey;
      node._tpLastFlashT = node.flashT;
      node._tp = TextPainter(
        text: TextSpan(
          text:  displayText,
          style: TextStyle(
            color:         color,
            fontSize:      node.fontSize,
            fontWeight:    weight,
            fontFamily:    'monospace',
            letterSpacing: node.intercepted ? 0.6 : 0.0,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: screenW * 0.45);
    } else if ((node._tpLastFlashT - node.flashT).abs() > 0.01) {
      // Color-only update during flash: in-place relayout on unchanged text
      // (text layout dimensions are stable; only alpha changes)
      node._tpLastFlashT = node.flashT;
      node._tp!.text = TextSpan(
        text:  displayText,
        style: TextStyle(
          color:         color,
          fontSize:      node.fontSize,
          fontWeight:    weight,
          fontFamily:    'monospace',
          letterSpacing: node.intercepted ? 0.6 : 0.0,
        ),
      );
      node._tp!.layout(maxWidth: screenW * 0.45);
    }

    node._tp!.paint(canvas, Offset(node.x, node.y));

    // Brief flat highlight behind freshly-intercepted text — no MaskFilter/blur
    if (node.intercepted && node.flashT > 0.05) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(
            node.x - 4,
            node.y - 2,
            node._tp!.width + 8,
            node._tp!.height + 4,
          ),
          const Radius.circular(3),
        ),
        Paint()
          ..color = AppColors.primary.withValues(alpha: 0.07 * node.flashT),
      );
    }
  }

  @override
  bool shouldRepaint(_StreamPainter old) =>
      old.screenW != screenW || !identical(old.nodes, nodes);
}
