part of 'insert_sheet.dart';

class _TextQuickTools extends StatelessWidget {
  const _TextQuickTools({
    required this.controller,
    required this.actions,
    required this.palette,
    this.startTyping,
  });

  final RichEditingController controller;
  final TextActions actions;
  final List<Color> palette;
  final VoidCallback? startTyping;

  (int, int) get _sel {
    final s = controller.effectiveSelection;
    return (s.baseOffset, s.extentOffset);
  }

  @override
  Widget build(BuildContext context) {
    final (a, b) = _sel;
    final doc = controller.doc;
    final caret = (a == b) ? a : b;
    final para = doc.effectiveParaAt(caret.clamp(0, doc.text.length));
    return _PanelBody(
      children: [
        if (startTyping != null)
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              key: const ValueKey('panel_edit_text'),
              onPressed: startTyping,
              icon: const Icon(Icons.keyboard_alt_outlined, size: 16),
              label: const Text('Edit text'),
            ),
          ),
        _PanelRow(
          children: [
            _PanelIconToggle(
              icon: Icons.format_bold,
              active: doc.isFlagActive(a, b, 'bold'),
              onTap: () => actions.toggleFlag('bold'),
            ),
            _PanelIconToggle(
              icon: Icons.format_italic,
              active: doc.isFlagActive(a, b, 'italic'),
              onTap: () => actions.toggleFlag('italic'),
            ),
            _PanelIconToggle(
              icon: Icons.format_underline,
              active: doc.isFlagActive(a, b, 'underline'),
              onTap: () => actions.toggleFlag('underline'),
            ),
            _PanelIconToggle(
              icon: Icons.format_strikethrough,
              active: doc.isFlagActive(a, b, 'strike'),
              onTap: () => actions.toggleFlag('strike'),
            ),
          ],
        ),
        _PanelRow(
          children: [
            _PanelIconToggle(
              icon: Icons.format_align_left,
              active: (para?.align ?? 'left') == 'left',
              onTap: () => actions.setAlign('left'),
            ),
            _PanelIconToggle(
              icon: Icons.format_align_center,
              active: (para?.align ?? 'left') == 'center',
              onTap: () => actions.setAlign('center'),
            ),
            _PanelIconToggle(
              icon: Icons.format_align_right,
              active: (para?.align ?? 'left') == 'right',
              onTap: () => actions.setAlign('right'),
            ),
            _PanelIconToggle(
              icon: Icons.format_align_justify,
              active: (para?.align ?? 'left') == 'justify',
              onTap: () => actions.setAlign('justify'),
            ),
            const Spacer(),
            _PanelIconToggle(
              icon: Icons.format_list_bulleted,
              active: (para?.list ?? 'none') == 'bullet',
              onTap: () => actions.toggleList('bullet'),
            ),
            _PanelIconToggle(
              icon: Icons.format_list_numbered,
              active: (para?.list ?? 'none') == 'number',
              onTap: () => actions.toggleList('number'),
            ),
          ],
        ),
        DreamColorChips(
          label: 'TEXT COLOR',
          palette: palette,
          selected: _runAttr(a, b, (r) => r.color),
          onPick: actions.setColor,
        ),
        DreamColorChips(
          label: 'HIGHLIGHT — behind the text',
          palette: palette,
          selected: _runAttr(a, b, (r) => r.highlight),
          onPick: actions.setHighlight,
        ),
      ],
    );
  }

  /// The attribute at the selection — caret-aware, matching the Character
  /// group (and the typing toolbar): a collapsed caret reads its TYPING
  /// SOURCE (the pending mark at the caret, else the character before it —
  /// "affects what I type next"), a selection reads the first covered run.
  String? _runAttr(int a, int b, String? Function(RichRun) pick) {
    final doc = controller.doc;
    if (a == b) {
      final src = doc.typingSourceAt(a);
      return src == null ? null : pick(src);
    }
    for (final r in doc.runs) {
      if (r.end <= r.start) continue;
      if (r.start < b && a < r.end) return pick(r);
    }
    return null;
  }
}

class _TextCharacterTools extends StatelessWidget {
  const _TextCharacterTools({required this.controller, required this.actions});

  final RichEditingController controller;
  final TextActions actions;

  (int, int) get _sel {
    final s = controller.effectiveSelection;
    return (s.baseOffset, s.extentOffset);
  }

  double get _fontSize {
    final v = _caretAwareAttr((r) => r.fontSize);
    return v is num ? v.toDouble() : 32;
  }

  String get _family {
    final v = _caretAwareAttr((r) => r.fontFamily);
    return v is String ? v : 'sans';
  }

  /// A collapsed caret reads its TYPING SOURCE (the pending mark at the
  /// caret, else the character before it) — "affects what I type next" —
  /// while a selection reads the runs it covers.
  Object? _caretAwareAttr(Object? Function(RichRun) pick) {
    final (a, b) = _sel;
    final doc = controller.doc;
    if (a == b) {
      final src = doc.typingSourceAt(a);
      if (src != null) {
        final v = pick(src);
        if (v != null) return v;
      }
      return null;
    }
    for (final r in doc.runs) {
      if (r.end <= r.start) continue;
      if (r.start < b && a < r.end) {
        final v = pick(r);
        if (v != null) return v;
      }
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final (a, b) = _sel;
    final doc = controller.doc;
    return _PanelBody(
      children: [
        const _PanelLabel('FONT FAMILY'),
        _PanelRow(
          children: [
            DreamChoiceChip(
              label: 'Sans',
              selected: _family == 'sans',
              onTap: () => actions.setFontFamily(null),
            ),
            const SizedBox(width: 8),
            DreamChoiceChip(
              label: 'Serif',
              selected: _family == 'serif',
              onTap: () => actions.setFontFamily('serif'),
            ),
            const SizedBox(width: 8),
            DreamChoiceChip(
              label: 'Mono',
              selected: _family == 'mono',
              onTap: () => actions.setFontFamily('mono'),
            ),
          ],
        ),
        const _PanelLabel('FONT SIZE'),
        _PanelRow(
          children: [
            _PanelIconToggle(
              key: const ValueKey('panel_font_minus'),
              icon: Icons.remove,
              onTap: () => actions.setFontSize(
                  (_fontSize - 4).clamp(8.0, 96.0).toDouble()),
            ),
            SizedBox(
              width: 56,
              child: Center(
                child: Text(
                  _fontSize.toStringAsFixed(0),
                  style: const TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w600, color: kText),
                ),
              ),
            ),
            _PanelIconToggle(
              key: const ValueKey('panel_font_plus'),
              icon: Icons.add,
              onTap: () => actions.setFontSize(
                  (_fontSize + 4).clamp(8.0, 96.0).toDouble()),
            ),
          ],
        ),
        const _PanelLabel('CHARACTER'),
        _PanelRow(
          children: [
            _PanelIconToggle(
              icon: Icons.format_strikethrough,
              active: doc.isFlagActive(a, b, 'strike'),
              onTap: () => actions.toggleFlag('strike'),
            ),
            _PanelIconToggle(
              icon: Icons.subscript,
              active: doc.isFlagActive(a, b, 'subscript'),
              onTap: () => actions.toggleFlag('subscript'),
            ),
            _PanelIconToggle(
              icon: Icons.superscript,
              active: doc.isFlagActive(a, b, 'superscript'),
              onTap: () => actions.toggleFlag('superscript'),
            ),
          ],
        ),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: actions.clearFormatting,
            icon: const Icon(Icons.format_clear, size: 16),
            label: const Text('Clear formatting — back to slide theme'),
          ),
        ),
      ],
    );
  }
}

class _TextParaTools extends StatelessWidget {
  const _TextParaTools({required this.controller, required this.actions});

  final RichEditingController controller;
  final TextActions actions;

  (int, int) get _sel {
    final s = controller.effectiveSelection;
    return (s.baseOffset, s.extentOffset);
  }

  @override
  Widget build(BuildContext context) {
    final (a, b) = _sel;
    final doc = controller.doc;
    final caret = (a == b) ? a : b;
    final para = doc.effectiveParaAt(caret.clamp(0, doc.text.length));
    final spacing = para?.lineSpacing ?? 1.15;
    final indent = para?.indent ?? 0;
    return _PanelBody(
      children: [
        const _PanelLabel('ALIGNMENT INSIDE THE BOX'),
        _PanelRow(
          children: [
            _PanelIconToggle(
              icon: Icons.vertical_align_top,
              active: doc.valign == 'top',
              onTap: () => actions.setValign('top'),
            ),
            _PanelIconToggle(
              icon: Icons.vertical_align_center,
              active: doc.valign == 'middle',
              onTap: () => actions.setValign('middle'),
            ),
            _PanelIconToggle(
              icon: Icons.vertical_align_bottom,
              active: doc.valign == 'bottom',
              onTap: () => actions.setValign('bottom'),
            ),
          ],
        ),
        const _PanelLabel('LINE SPACING'),
        Padding(
          padding: const EdgeInsets.only(left: 2),
          child: Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              for (final s in const [1.0, 1.15, 1.5, 2.0])
                DreamChoiceChip(
                  label: s == 1.0 ? '1.0' : s.toString(),
                  selected: (spacing - s).abs() < 0.001,
                  onTap: () => actions.setLineSpacing(s),
                ),
            ],
          ),
        ),
        const _PanelLabel('LIST INDENT'),
        _PanelRow(
          children: [
            _PanelIconToggle(
              icon: Icons.format_indent_decrease,
              onTap: () => actions.indentBy(-1),
            ),
            SizedBox(
              width: 56,
              child: Center(
                child: Text(
                  'level $indent',
                  style: const TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w600, color: kText),
                ),
              ),
            ),
            _PanelIconToggle(
              icon: Icons.format_indent_increase,
              onTap: () => actions.indentBy(1),
            ),
          ],
        ),
        const _PanelLabel('OVERFLOW'),
        Padding(
          padding: const EdgeInsets.only(left: 2),
          child: Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              DreamChoiceChip(
                label: 'Shrink text on overflow',
                selected: doc.autofit == 'shrink',
                onTap: () => actions.setAutofit('shrink'),
              ),
              DreamChoiceChip(
                label: 'No autofit',
                selected: doc.autofit == 'none',
                onTap: () => actions.setAutofit('none'),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
