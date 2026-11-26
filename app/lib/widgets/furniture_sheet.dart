import 'package:material_ui/material_ui.dart';

import '../core/furniture_math.dart';
import '../theme.dart';

/// Slide furniture (View tab): the slide number, the date and the footer.
/// The two switches apply at once (one undo step each); the footer
/// commits on Done, so typing doesn't write a step per keystroke.
class FurnitureSheet extends StatefulWidget {
  const FurnitureSheet({
    super.key,
    required this.initial,
    required this.onChanged,
  });

  final Furniture initial;
  final ValueChanged<Furniture> onChanged;

  @override
  State<FurnitureSheet> createState() => _FurnitureSheetState();
}

class _FurnitureSheetState extends State<FurnitureSheet> {
  late Furniture _f = widget.initial;
  late final TextEditingController _footer =
      TextEditingController(text: widget.initial.footer);

  @override
  void dispose() {
    _footer.dispose();
    super.dispose();
  }

  void _set(Furniture next) {
    setState(() => _f = next);
    widget.onChanged(next);
  }

  void _commitFooter() {
    final text = _footer.text.trim();
    if (text == _f.footer) return;
    _set(Furniture(
        slideNumber: _f.slideNumber, date: _f.date, footer: text));
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Slide furniture',
              style: TextStyle(
                  color: kText, fontSize: 16, fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          const Text('Added to every slide as locked text, so it exports too.',
              style: TextStyle(color: kText2, fontSize: 12)),
          SwitchListTile(
            key: const ValueKey('furniture_number'),
            contentPadding: EdgeInsets.zero,
            title: const Text('Slide number', style: TextStyle(color: kText)),
            value: _f.slideNumber,
            onChanged: (v) => _set(Furniture(
                slideNumber: v, date: _f.date, footer: _f.footer)),
          ),
          SwitchListTile(
            key: const ValueKey('furniture_date'),
            contentPadding: EdgeInsets.zero,
            title: const Text('Date', style: TextStyle(color: kText)),
            value: _f.date,
            onChanged: (v) => _set(Furniture(
                slideNumber: _f.slideNumber, date: v, footer: _f.footer)),
          ),
          TextField(
            key: const ValueKey('furniture_footer'),
            controller: _footer,
            style: const TextStyle(color: kText),
            decoration: const InputDecoration(
              labelText: 'Footer text',
              hintText: 'Leave empty for no footer',
            ),
            onSubmitted: (_) => _commitFooter(),
          ),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: () {
                _commitFooter();
                Navigator.of(context).pop();
              },
              child: const Text('Done'),
            ),
          ),
        ],
      ),
    );
  }
}
