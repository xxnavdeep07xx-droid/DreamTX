import 'package:material_ui/material_ui.dart';

import '../core/outline_math.dart';
import '../theme.dart';

/// Outline view: every slide in deck order, with its title and a one-line
/// body preview. Tap a row to jump to that slide; the pencil edits the
/// title. The sheet reads the deck through [slidesOf] on every build, so
/// an edit shows at once.
class OutlineSheet extends StatefulWidget {
  const OutlineSheet({
    super.key,
    required this.slidesOf,
    required this.currentIndex,
    required this.titleOf,
    required this.onOpen,
    required this.onEditTitle,
  });

  final List<Map<String, dynamic>> Function() slidesOf;
  final int currentIndex;
  final String Function(Map<String, dynamic> slide) titleOf;
  final ValueChanged<int> onOpen;
  final Future<void> Function(int index) onEditTitle;

  @override
  State<OutlineSheet> createState() => _OutlineSheetState();
}

class _OutlineSheetState extends State<OutlineSheet> {
  @override
  Widget build(BuildContext context) {
    final slides = widget.slidesOf();
    return SizedBox(
      height: MediaQuery.of(context).size.height * 0.6,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Text(
              'Outline · ${slides.length} slide${slides.length == 1 ? '' : 's'}',
              style: const TextStyle(
                  color: kText, fontSize: 16, fontWeight: FontWeight.w600),
            ),
          ),
          Expanded(
            child: slides.isEmpty
                ? const Center(
                    child: Text('No slides yet',
                        style: TextStyle(color: kText2)))
                : ListView.builder(
                    key: const ValueKey('outline_list'),
                    itemCount: slides.length,
                    itemBuilder: (context, i) {
                      final slide = slides[i];
                      final content = slide['content'];
                      final preview = content is Map
                          ? outlineBodyPreview(content)
                          : '';
                      return ListTile(
                        key: ValueKey('outline_row_$i'),
                        selected: i == widget.currentIndex,
                        leading: Text('${i + 1}',
                            style: const TextStyle(color: kText2)),
                        title: Text(
                          widget.titleOf(slide),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: kText),
                        ),
                        subtitle: preview.isEmpty
                            ? null
                            : Text(
                                preview,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(color: kText2),
                              ),
                        trailing: IconButton(
                          tooltip: 'Edit title',
                          icon: const Icon(Icons.edit_outlined,
                              size: 20, color: kText2),
                          onPressed: () async {
                            await widget.onEditTitle(i);
                            if (mounted) setState(() {});
                          },
                        ),
                        onTap: () => widget.onOpen(i),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
