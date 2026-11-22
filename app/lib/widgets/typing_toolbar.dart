import 'package:material_ui/material_ui.dart';

import 'controls.dart';
import '../theme.dart';

/// The horizontally scrollable toolbar shown directly ABOVE the keyboard
/// while the user is typing into a selected text box — the typing state's
/// whole control surface. Lives in the ROOT overlay (outside the editor's
/// keyboard-stable subtree, so it sees the real viewport and rides the
/// keyboard), and never steals the field's focus: everything here is
/// buttons and chips, no routes.
///
/// Actions take the CURRENT selection from the live controller (character
/// formatting affects the selection; alignment and lists the caret's
/// paragraphs). The color rows open in place — an expanding palette row
/// above the main row, never a modal.
class TypingToolbar extends StatefulWidget {
  const TypingToolbar({
    super.key,
    required this.docState,
    required this.palette,
    required this.onToggle,
    required this.onColor,
    required this.onHighlight,
    required this.onAlign,
    required this.onList,
    required this.onExpand,
  });

  /// A rebuildable view over the live doc + selection: invoked during
  /// build, so the toolbar's active states always track the caret.
  final TypingToolbarStateLike docState;

  /// The deck's color palette (deck colors first, then standards).
  final List<Color> palette;

  /// `onToggle('bold' | 'italic' | 'underline' | 'strike')`.
  final void Function(String flag) onToggle;

  /// `onColor(hexOrNull)` — text color; null clears.
  final void Function(String? hex) onColor;

  /// `onHighlight(hexOrNull)` — color behind the text.
  final void Function(String? hex) onHighlight;

  /// `onAlign('left' | 'center' | 'right' | 'justify')`.
  final void Function(String align) onAlign;

  /// `onList('bullet' | 'number')` — a toggle.
  final void Function(String kind) onList;

  /// The expand button: hide the keyboard, open the full panel.
  final VoidCallback onExpand;

  @override
  State<TypingToolbar> createState() => _TypingToolbarState();
}

class _TypingToolbarState extends State<TypingToolbar> {
  bool _colorChipsOpen = false;
  bool _highlightChipsOpen = false;

  void _toggleColor() =>
      setState(() { _highlightChipsOpen = false; _colorChipsOpen = !_colorChipsOpen; });
  void _toggleHighlight() =>
      setState(() { _colorChipsOpen = false; _highlightChipsOpen = !_highlightChipsOpen; });

  @override
  Widget build(BuildContext context) {
    final docState = _DocStateView(widget.docState, _colorChipsOpen, _highlightChipsOpen);
    return Material(
      key: const ValueKey('typing_toolbar'),
      color: kElevated,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _PaletteRow(
            palette: widget.palette,
            docState: docState,
            onColor: (hex) {
              widget.onColor(hex);
            },
            onHighlight: (hex) {
              widget.onHighlight(hex);
            },
          ),
          Container(
            decoration: const BoxDecoration(
              border: Border(top: BorderSide(color: kHairline)),
            ),
            height: 52,
            child: Row(
              children: [
                Expanded(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: Row(
                      children: [
                        _ToolButton(
                          icon: Icons.format_bold,
                          tooltip: 'Bold',
                          active: docState.isFlagActive('bold'),
                          onTap: () => widget.onToggle('bold'),
                        ),
                        _ToolButton(
                          icon: Icons.format_italic,
                          tooltip: 'Italic',
                          active: docState.isFlagActive('italic'),
                          onTap: () => widget.onToggle('italic'),
                        ),
                        _ToolButton(
                          icon: Icons.format_underline,
                          tooltip: 'Underline',
                          active: docState.isFlagActive('underline'),
                          onTap: () => widget.onToggle('underline'),
                        ),
                        _ToolButton(
                          icon: Icons.format_strikethrough,
                          tooltip: 'Strikethrough',
                          active: docState.isFlagActive('strike'),
                          onTap: () => widget.onToggle('strike'),
                        ),
                        const _ToolDivider(),
                        _ToolButton(
                          icon: Icons.format_color_text,
                          tooltip: 'Text color',
                          active: _colorChipsOpen,
                          paletteMode: true,
                          onTap: _toggleColor,
                        ),
                        _ToolButton(
                          icon: Icons.highlight,
                          tooltip: 'Highlight',
                          active: _highlightChipsOpen,
                          paletteMode: true,
                          onTap: _toggleHighlight,
                        ),
                        const _ToolDivider(),
                        for (final (a, icon) in const [
                          ('left', Icons.format_align_left),
                          ('center', Icons.format_align_center),
                          ('right', Icons.format_align_right),
                          ('justify', Icons.format_align_justify),
                        ])
                          _ToolButton(
                            icon: icon,
                            tooltip: switch (a) {
                              'left' => 'Align left',
                              'center' => 'Align center',
                              'right' => 'Align right',
                              _ => 'Justify',
                            },
                            active: docState.align == a,
                            onTap: () => widget.onAlign(a),
                          ),
                        const _ToolDivider(),
                        _ToolButton(
                          icon: Icons.format_list_bulleted,
                          tooltip: 'Bulleted list',
                          active: docState.list == 'bullet',
                          onTap: () => widget.onList('bullet'),
                        ),
                        _ToolButton(
                          icon: Icons.format_list_numbered,
                          tooltip: 'Numbered list',
                          active: docState.list == 'number',
                          onTap: () => widget.onList('number'),
                        ),
                      ],
                    ),
                  ),
                ),
                Container(
                  decoration: const BoxDecoration(
                    border: Border(left: BorderSide(color: kHairline)),
                  ),
                  child: IconButton(
                    key: const ValueKey('typing_toolbar_expand'),
                    tooltip: 'Hide keyboard and open full panel',
                    icon: const Icon(Icons.unfold_more, color: kText),
                    iconSize: 21,
                    onPressed: widget.onExpand,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// What the toolbar needs to know about the live doc state — implemented
/// by the editor's session wrapper; invoked during build so the toolbar
/// tracks the caret live.
abstract class TypingToolbarStateLike {
  bool isFlagActive(String flag);
  String? get color;
  String? get highlight;
  String? get align;
  String? get list;
}

/// The toolbar's live view: doc reads from the session plus the toolbar's
/// own palette-open flags.
class _DocStateView implements TypingToolbarStateLike {
  _DocStateView(this._doc, this._colorOpen, this._highlightOpen);

  final TypingToolbarStateLike _doc;
  final bool _colorOpen;
  final bool _highlightOpen;

  @override
  bool isFlagActive(String flag) => _doc.isFlagActive(flag);
  @override
  String? get color => _doc.color;
  @override
  String? get highlight => _doc.highlight;
  @override
  String? get align => _doc.align;
  @override
  String? get list => _doc.list;
  bool get colorChipsOpen => _colorOpen;
  bool get highlightChipsOpen => _highlightOpen;
}

// ---------------------------------------------------------------------------

class _PaletteRow extends StatelessWidget {
  const _PaletteRow({
    required this.palette,
    required this.docState,
    required this.onColor,
    required this.onHighlight,
  });

  final List<Color> palette;
  final _DocStateView docState;
  final void Function(String?) onColor;
  final void Function(String?) onHighlight;

  static const double rowHeight = 52;

  @override
  Widget build(BuildContext context) {
    final open = docState.colorChipsOpen || docState.highlightChipsOpen;
    return AnimatedCrossFade(
      duration: const Duration(milliseconds: 150),
      crossFadeState:
          open ? CrossFadeState.showSecond : CrossFadeState.showFirst,
      firstChild: const SizedBox(height: 0, width: double.infinity),
      secondChild: SizedBox(
        height: rowHeight,
        width: double.infinity,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 0),
              child: Text(
                docState.colorChipsOpen ? 'TEXT COLOR' : 'HIGHLIGHT',
                style: const TextStyle(
                  fontSize: 9,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.1,
                  color: kText3,
                ),
              ),
            ),
            Expanded(
              // The SAME color chip row the panels use (one implementation;
              // horizontal above the keyboard, 30px chips as always).
              child: DreamColorChips(
                palette: palette,
                selected: docState.colorChipsOpen
                    ? docState.color
                    : docState.highlight,
                onPick: (hex) => docState.colorChipsOpen
                    ? onColor(hex)
                    : onHighlight(hex),
                horizontal: true,
                chipSize: 30,
                noneTooltip:
                    docState.colorChipsOpen ? 'No color' : 'No highlight',
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ToolButton extends StatelessWidget {
  const _ToolButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.active = false,
    this.paletteMode = false,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  final bool active;
  final bool paletteMode;

  @override
  Widget build(BuildContext context) {
    final color = active ? kText : kText2;
    return Tooltip(
      message: tooltip,
      waitDuration: const Duration(milliseconds: 500),
      child: SizedBox(
        width: 44,
        height: 48,
        child: IconButton(
          icon: Icon(icon, size: paletteMode ? 20 : 22, color: color),
          color: color,
          onPressed: onTap,
          visualDensity: VisualDensity.compact,
          style: IconButton.styleFrom(
            backgroundColor: active ? const Color(0x1FFFFFFF) : null,
          ),
        ),
      ),
    );
  }
}

class _ToolDivider extends StatelessWidget {
  const _ToolDivider();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 1,
      height: 22,
      margin: const EdgeInsets.symmetric(horizontal: 3),
      color: kHairline,
    );
  }
}
