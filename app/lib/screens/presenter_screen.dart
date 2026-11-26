part of 'editor_screen.dart';

/// Presenting mode — a fullscreen, chrome-free pass over the deck: each
/// slide rendered on black, swipe or tap the side zones to advance, a counter
/// at the bottom and a close button up top.
class _PresenterScreen extends StatefulWidget {
  const _PresenterScreen({required this.deck, required this.first});

  final Map<String, dynamic> deck;
  final int first;

  @override
  State<_PresenterScreen> createState() => _PresenterScreenState();
}

class _PresenterScreenState extends State<_PresenterScreen> {
  late final PageController _pages;
  late final List<Map<String, dynamic>> _slides;
  late final List<Map<String, dynamic>?> _layouts;
  int _page = 0;

  /// The deck's DNA chart palette, for charts with no series color of their own.
  List<String> _chartPalette = kChartPalette;

  /// The image-resource paths both scopes resolve to, so image objects
  /// present their real assets (loaded once on mount; the deck does not
  /// mutate while presenting).
  final Map<String, String> _resourcePaths = {};

  /// The deck's design frame + slide-theme base for content objects.
  (double, double) get _designDims =>
      deckDimsOf(widget.deck['aspect']?.toString());
  Color _baseTextColor = const Color(0xFF17181A);
  String? _baseTextFamily;

  @override
  void initState() {
    super.initState();
    _slides = ((widget.deck['slides'] as List?) ?? const [])
        .whereType<Map<String, dynamic>>()
        .toList();
    final dnaReply = Bridge.command({'op': 'resolve_dna', 'deck': widget.deck});
    if (dnaReply['ok'] == true && dnaReply['dna'] is Map) {
      _chartPalette =
          chartPaletteFrom((dnaReply['dna'] as Map)['chart_palette']);
    }
    _layouts = [for (var i = 0; i < _slides.length; i++) _layoutAt(i)];
    var first = widget.first;
    if (first < 0) first = 0;
    if (first >= _slides.length) first = _slides.length - 1;
    _pages = PageController(initialPage: first);
    _page = first;
    _loadResourceIndex();
    _resolvePalette();
  }

  Future<void> _loadResourceIndex() async {
    try {
      final store = await ResourceStore.open();
      final deckId = (widget.deck['id'] ?? '').toString();
      for (final (brand, scope) in [(false, 'deck'), (true, 'brand')]) {
        final items =
            await store.list(brand: brand, deckId: brand ? null : deckId);
        for (final e in items) {
          final path = await store.resolve(
              brand: brand, deckId: brand ? null : deckId, id: '${e['id']}');
          if (path != null) {
            _resourcePaths['$scope:${e['id']}'] = path;
          }
        }
      }
    } catch (_) {
      // Storage offline — image objects fall back to their name chip.
    }
    if (mounted) setState(() {});
  }

  /// The deck DNA's foreground + body family — the same resolve_dna read
  /// the editor performs for its content objects.
  void _resolvePalette() {
    try {
      final r = Bridge.command(
          {'op': 'resolve_dna', 'deck': widget.deck});
      if (r['ok'] == true && r['dna'] is Map) {
        final palette = r['dna']['palette'] as Map?;
        final fg = palette?['fg']?.toString();
        if (fg != null && fg.length == 6) {
          _baseTextColor = hexToColor(fg);
        }
        _baseTextFamily =
            (r['dna']['body_font'] ?? '').toString() == 'serif' ? 'serif' : null;
      }
    } catch (_) {
      // The engine offline — the default ink base renders.
    }
  }

  String? _resolveResourcePath(Map<String, dynamic> content) {
    final scope = content['brand'] == true ? 'brand' : 'deck';
    return _resourcePaths['$scope:${content['resource_id']}'];
  }

  List<Map<String, dynamic>> _objectsOf(int i) {
    if (i < 0 || i >= _slides.length) return const [];
    return ((_slides[i]['objects'] as List?) ?? const [])
        .whereType<Map>()
        .map((m) => Map<String, dynamic>.from(m))
        .toList();
  }

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  Map<String, dynamic>? _layoutAt(int i) {
    final r = Bridge.command(
        {'op': 'get_layout', 'deck': widget.deck, 'slide_index': i});
    return r['ok'] == true && r['layout'] is Map
        ? (r['layout'] as Map).cast<String, dynamic>()
        : null;
  }

  /// A tap on a linked object follows its link (a URL opens outside the
  /// deck; a slide link jumps there). Any other tap uses the tap zones:
  /// left of centre goes back, right of centre advances, and the 90 px
  /// centre gap does nothing. A link tap never also turns the page.
  void _onTap(Offset at, Size screen) {
    final design = designPointOf(
        at, screen, Size(_designDims.$1, _designDims.$2));
    if (design != null) {
      final obj = linkObjectAt(_objectsOf(_page), design);
      final link = obj == null ? null : linkOf(obj);
      if (link != null) {
        _followLink(link);
        return;
      }
    }
    if (at.dx < (screen.width - 90) / 2) {
      _go(-1);
    } else if (at.dx > (screen.width + 90) / 2) {
      _go(1);
    }
  }

  Future<void> _followLink(Map<String, dynamic> link) async {
    if (link['kind'] == 'slide') {
      final i = _slides.indexWhere((sl) => sl['id'] == link['target']);
      if (i >= 0 && i != _page) {
        _pages.animateToPage(i,
            duration: const Duration(milliseconds: 260),
            curve: Curves.easeOutCubic);
      }
      return;
    }
    final ok = await LinkOpen.openUrl(link['target'] as String);
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('This link could not be opened')));
    }
  }

  void _go(int delta) {
    var target = _page + delta;
    if (target < 0) target = 0;
    if (target >= _slides.length) target = _slides.length - 1;
    if (target == _page) return;
    _pages.animateToPage(target,
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOutCubic);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          PageView.builder(
            controller: _pages,
            itemCount: _slides.length,
            onPageChanged: (value) => setState(() => _page = value),
            itemBuilder: (context, i) {
              final layout = _layouts[i];
              return Center(
                child: AspectRatio(
                  // The deck's OWN frame ratio — a 4:3, 16:10 or 1:1 deck
                  // presents at its true shape, never stretched into the
                  // classic 16:9.
                  aspectRatio: aspectRatioOf(widget.deck['aspect']?.toString()),
                  child: layout == null
                      ? const Center(
                          child: Text('Unable to render this slide',
                              style: TextStyle(color: kText2)))
                      : SlideStage(
                          // The SAME layered stage the editor renders:
                          // every inserted/drawn object presents — text
                          // boxes, images, icons, media cards, tables and
                          // vector shapes, in the deck's true Z-order —
                          // not just the archetype layout.
                          layout: layout,
                          objects: _objectsOf(i),
                          designW: _designDims.$1,
                          designH: _designDims.$2,
                          baseColor: _baseTextColor,
                          baseFamily: _baseTextFamily,
                          baseFontSize: kTextBoxBaseSize,
                          resolveResourcePath: _resolveResourcePath,
                          // Table metadata rides the deck verbatim — merged
                          // regions and styles present exactly as edited.
                          tableMeta: (widget.deck['tables'] as Map?)
                              ?.cast<String, dynamic>(),
                          // Image metadata (shape/brightness/contrast)
                          // rides the deck the same way — present exactly
                          // as edited.
                          imageMeta: (widget.deck['imageMeta'] as Map?)
                              ?.cast<String, dynamic>(),
                          chartPalette: _chartPalette,
                          // Read-only: no selection, no gestures.
                        ),
                ),
              );
            },
          ),
          // Tap layer: link taps first, then the tap zones (right advances,
          // left goes back). Swipes still work — tap recognizers never claim
          // drags.
          LayoutBuilder(
            builder: (context, c) => GestureDetector(
              behavior: HitTestBehavior.translucent,
              onTapUp: (d) => _onTap(d.localPosition, c.biggest),
              child: const SizedBox.expand(),
            ),
          ),
          Positioned(
            top: 24,
            right: 12,
            child: IconButton(
              tooltip: 'Exit',
              icon: const Icon(Icons.close, color: Colors.white, size: 26),
              onPressed: () => Navigator.of(context).pop(),
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 18,
            child: Center(
              child: Text(
                _slides.isEmpty ? '' : '${_page + 1} / ${_slides.length}',
                style: const TextStyle(color: Colors.white70, fontSize: 12),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
