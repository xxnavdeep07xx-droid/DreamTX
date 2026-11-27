import 'package:material_ui/material_ui.dart';

import '../core/link_math.dart';
import '../theme.dart';

/// What the link sheet returns: the new link, or null to remove it.
/// A cancelled sheet returns no LinkEdit at all.
class LinkEdit {
  const LinkEdit(this.link);
  final Map<String, dynamic>? link;
}

/// Object link (object actions → Link): none, a web address, or a slide.
/// Done commits the choice; the sheet never writes the deck itself.
class LinkSheet extends StatefulWidget {
  const LinkSheet({
    super.key,
    required this.current,
    required this.slides,
    required this.titleOf,
  });

  final Map<String, dynamic>? current;
  final List<Map<String, dynamic>> slides;
  final String Function(Map<String, dynamic> slide) titleOf;

  @override
  State<LinkSheet> createState() => _LinkSheetState();
}

enum _LinkKind { none, url, slide }

class _LinkSheetState extends State<LinkSheet> {
  late _LinkKind _kind;
  late final TextEditingController _url;
  String? _slideId;

  @override
  void initState() {
    super.initState();
    final cur = widget.current;
    final kind = cur?['kind'];
    _kind = kind == 'url'
        ? _LinkKind.url
        : kind == 'slide'
            ? _LinkKind.slide
            : _LinkKind.none;
    _url = TextEditingController(text: kind == 'url' ? cur!['target'] as String : '');
    _slideId = kind == 'slide' ? cur!['target'] as String : null;
  }

  @override
  void dispose() {
    _url.dispose();
    super.dispose();
  }

  /// The link the current inputs describe, or null when Done is not allowed.
  Map<String, dynamic>? _result() {
    switch (_kind) {
      case _LinkKind.none:
        return null;
      case _LinkKind.url:
        return urlLink(_url.text);
      case _LinkKind.slide:
        return _slideId == null ? null : slideLink(_slideId!);
    }
  }

  bool get _canDone => _kind == _LinkKind.none || _result() != null;

  void _done() {
    Navigator.pop(context, LinkEdit(_kind == _LinkKind.none ? null : _result()));
  }

  @override
  Widget build(BuildContext context) {
    final hasUrlText = _url.text.trim().isNotEmpty;
    return Padding(
      padding: EdgeInsets.only(
          left: 16,
          right: 16,
          top: 16,
          bottom: MediaQuery.of(context).viewInsets.bottom + 16),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Link', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              children: [
                _kindChip(_LinkKind.none, 'None', 'link_kind_none'),
                _kindChip(_LinkKind.url, 'Web address', 'link_kind_url'),
                _kindChip(_LinkKind.slide, 'Slide', 'link_kind_slide'),
              ],
            ),
            const SizedBox(height: 12),
            if (_kind == _LinkKind.url) ...[
              TextField(
                key: const Key('link_url'),
                controller: _url,
                keyboardType: TextInputType.url,
                autocorrect: false,
                style: const TextStyle(color: kText, fontSize: 14),
                cursorColor: kPurple,
                decoration: darkInput(hint: 'https://…').copyWith(
                  errorText: hasUrlText && urlLink(_url.text) == null
                      ? 'Use an https, http, or mailto link, with no spaces'
                      : null,
                ),
                onChanged: (_) => setState(() {}),
              ),
            ],
            if (_kind == _LinkKind.slide) ...[
              if (widget.slides.isEmpty)
                const Text('This deck has no slides.')
              else
                SizedBox(
                  height: 240,
                  child: ListView.builder(
                    itemCount: widget.slides.length,
                    itemBuilder: (context, i) {
                      final slide = widget.slides[i];
                      final id = slide['id'] as String;
                      final picked = id == _slideId;
                      return ListTile(
                        key: Key('link_slide_$i'),
                        dense: true,
                        selected: picked,
                        leading: Text('${i + 1}'),
                        title: Text(
                          widget.titleOf(slide),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        trailing: picked ? const Icon(Icons.check, size: 18) : null,
                        onTap: () => setState(() => _slideId = id),
                      );
                    },
                  ),
                ),
            ],
            const SizedBox(height: 12),
            Row(
              children: [
                TextButton(
                  key: const Key('link_remove'),
                  onPressed: widget.current == null
                      ? null
                      : () => Navigator.pop(context, const LinkEdit(null)),
                  child: const Text('Remove link'),
                ),
                const Spacer(),
                FilledButton(
                  key: const Key('link_done'),
                  onPressed: _canDone ? _done : null,
                  child: const Text('Done'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _kindChip(_LinkKind kind, String label, String keyName) {
    return ChoiceChip(
      key: Key(keyName),
      label: Text(label),
      selected: _kind == kind,
      onSelected: (_) => setState(() => _kind = kind),
    );
  }
}
