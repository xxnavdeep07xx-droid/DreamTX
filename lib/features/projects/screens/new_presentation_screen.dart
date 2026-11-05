import 'package:flutter/material.dart';

import '../../../app/theme/app_colors.dart';
import '../../../shared/services/services.dart';
import '../../../shared/widgets/pressable_card.dart';

/// New project creation flow.
///
/// Creates a real entry in the (mock) project repository — the editor itself
/// is the next milestone.
class NewPresentationScreen extends StatefulWidget {
  const NewPresentationScreen({super.key});

  @override
  State<NewPresentationScreen> createState() => _NewPresentationScreenState();
}

class _NewPresentationScreenState extends State<NewPresentationScreen> {
  final TextEditingController _nameController = TextEditingController();
  String _aspectRatio = '16:9';
  bool _blankStart = true;

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    final name = _nameController.text.trim().isEmpty
        ? 'Untitled presentation'
        : _nameController.text.trim();

    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);

    await projectRepository.create(title: name);

    navigator.pop();
    messenger.showSnackBar(
      SnackBar(content: Text('"$name" created — the editor is on the way.')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('New Presentation')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(24, 10, 24, 32),
        children: [
          const _FieldLabel('Project name'),
          const SizedBox(height: 10),
          TextField(
            controller: _nameController,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _create(),
            decoration: const InputDecoration(hintText: 'Untitled presentation'),
          ),
          const SizedBox(height: 26),
          const _FieldLabel('Aspect ratio'),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _AspectOption(
                  value: '16:9',
                  detail: 'Widescreen',
                  selected: _aspectRatio == '16:9',
                  onTap: () => setState(() => _aspectRatio = '16:9'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _AspectOption(
                  value: '4:3',
                  detail: 'Classic',
                  selected: _aspectRatio == '4:3',
                  onTap: () => setState(() => _aspectRatio = '4:3'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 26),
          const _FieldLabel('Starting point'),
          const SizedBox(height: 10),
          _StartOption(
            icon: Icons.crop_free_rounded,
            title: 'Blank canvas',
            detail: 'An empty deck, ready to shape',
            selected: _blankStart,
            onTap: () => setState(() => _blankStart = true),
          ),
          const SizedBox(height: 10),
          _StartOption(
            icon: Icons.auto_awesome_outlined,
            title: 'AI draft',
            detail: 'Generated with the DreamTX engine',
            selected: false,
            onTap: () => ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('AI drafting arrives with the design engine.'),
              ),
            ),
            badge: 'Coming soon',
          ),
          const SizedBox(height: 34),
          FilledButton(
            onPressed: _create,
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(52),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            child: const Text('Create presentation'),
          ),
        ],
      ),
    );
  }
}

class _FieldLabel extends StatelessWidget {
  const _FieldLabel(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: const TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.9,
        color: AppColors.textTertiary,
      ),
    );
  }
}

class _AspectOption extends StatelessWidget {
  const _AspectOption({
    required this.value,
    required this.detail,
    required this.selected,
    required this.onTap,
  });

  final String value;
  final String detail;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return PressableCard(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: selected
              ? AppColors.violet.withOpacity(0.07)
              : AppColors.card,
          borderRadius: BorderRadius.circular(15),
          border: Border.all(
            color:
                selected ? AppColors.violet.withOpacity(0.45) : AppColors.border,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 15,
              height: 15,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: selected
                    ? AppColors.violet
                    : Colors.transparent,
                border: Border.all(
                  color: selected ? AppColors.violet : AppColors.border,
                  width: selected ? 4.5 : 1.6,
                ),
              ),
            ),
            const SizedBox(width: 11),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  value,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  detail,
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _StartOption extends StatelessWidget {
  const _StartOption({
    required this.icon,
    required this.title,
    required this.detail,
    required this.selected,
    required this.onTap,
    this.badge,
  });

  final IconData icon;
  final String title;
  final String detail;
  final bool selected;
  final VoidCallback onTap;
  final String? badge;

  @override
  Widget build(BuildContext context) {
    return PressableCard(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: selected ? AppColors.violet.withOpacity(0.07) : AppColors.card,
          borderRadius: BorderRadius.circular(15),
          border: Border.all(
            color: selected
                ? AppColors.violet.withOpacity(0.45)
                : AppColors.border,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: AppColors.violet.withOpacity(0.1),
                borderRadius: BorderRadius.circular(11),
              ),
              child: Icon(icon, size: 18, color: AppColors.violet),
            ),
            const SizedBox(width: 13),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: AppColors.textPrimary,
                          ),
                        ),
                      ),
                      if (badge != null) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(999),
                            border: Border.all(color: AppColors.border),
                          ),
                          child: Text(
                            badge!,
                            style: const TextStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.w600,
                              letterSpacing: 0.8,
                              color: AppColors.textTertiary,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(
                    detail,
                    style: const TextStyle(
                      fontSize: 11.5,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
