import 'package:flutter/material.dart';

import '../../../app/theme/app_colors.dart';
import '../../../shared/widgets/app_logo.dart';

/// Settings tab — profile, appearance, workspace preferences and about.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  String _slideFormat = '16:9';
  bool _autosave = true;
  bool _snapToGrid = true;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      bottom: false,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 10, 20, 32),
        children: [
          const Text(
            'Settings',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w600,
              letterSpacing: -0.5,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 20),
          _ProfileCard(),
          const SizedBox(height: 26),
          const _SectionLabel('APPEARANCE'),
          _Card(
            children: [
              const _SettingsRow(
                title: 'Dark',
                trailing: _CheckIcon(visible: true),
              ),
              _SettingsRow(
                title: 'Light',
                onTap: _notifySingleTheme,
              ),
              _SettingsRow(
                title: 'System',
                onTap: _notifySingleTheme,
                showDivider: false,
              ),
            ],
          ),
          const SizedBox(height: 26),
          const _SectionLabel('WORKSPACE'),
          _Card(
            children: [
              _SettingsRow(
                title: 'Default slide format',
                value: _slideFormat,
                onTap: _chooseSlideFormat,
              ),
              _SettingsRow(
                title: 'Autosave drafts',
                showDivider: false,
                trailingWidget: Switch(
                  value: _autosave,
                  onChanged: (value) => setState(() => _autosave = value),
                ),
              ),
              _SettingsRow(
                title: 'Snap to grid',
                showDivider: false,
                trailingWidget: Switch(
                  value: _snapToGrid,
                  onChanged: (value) => setState(() => _snapToGrid = value),
                ),
              ),
            ],
          ),
          const SizedBox(height: 26),
          const _SectionLabel('ABOUT'),
          _Card(
            children: [
              const _SettingsRow(title: 'Version', value: '0.1.0'),
              _SettingsRow(
                title: 'View open-source licenses',
                showDivider: false,
                trailing: const Icon(
                  Icons.chevron_right_rounded,
                  size: 18,
                  color: AppColors.textTertiary,
                ),
                onTap: () => showLicensePage(
                  context: context,
                  applicationName: 'DreamTX',
                  applicationVersion: '0.1.0',
                  applicationIcon: const Padding(
                    padding: EdgeInsets.all(10),
                    child: AppLogo(size: 36),
                  ),
                  applicationLegalese: '© 2026 DreamTX',
                ),
              ),
            ],
          ),
          const SizedBox(height: 26),
          Center(
            child: Text(
              'Crafted for storytellers · DreamTX 2026',
              style: TextStyle(
                fontSize: 11,
                letterSpacing: 0.3,
                color: AppColors.textTertiary.withOpacity(0.7),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _notifySingleTheme() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content:
            Text('Dark is the DreamTX identity for now — more themes later.'),
      ),
    );
  }

  Future<void> _chooseSlideFormat() async {
    final choice = await showDialog<String>(
      context: context,
      builder: (dialogContext) => SimpleDialog(
        title: const Text('Default slide format'),
        children: [
          for (final format in const ['16:9', '4:3'])
            SimpleDialogOption(
              onPressed: () => Navigator.of(dialogContext).pop(format),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Text(
                  format,
                  style: TextStyle(
                    fontSize: 14.5,
                    color: format == _slideFormat
                        ? AppColors.violet
                        : AppColors.textPrimary,
                    fontWeight: format == _slideFormat
                        ? FontWeight.w600
                        : FontWeight.w400,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
    if (choice != null && choice != _slideFormat) {
      setState(() => _slideFormat = choice);
    }
  }
}

class _ProfileCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: AppColors.violet.withOpacity(0.16),
              shape: BoxShape.circle,
              border: Border.all(color: AppColors.violet.withOpacity(0.3)),
            ),
            child: const Center(
              child: Text(
                'AR',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: AppColors.violet,
                ),
              ),
            ),
          ),
          const SizedBox(width: 14),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Alex Rivera',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    letterSpacing: -0.1,
                    color: AppColors.textPrimary,
                  ),
                ),
                SizedBox(height: 3),
                Text(
                  'Personal workspace · Local only',
                  style: TextStyle(
                    fontSize: 12,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          _CompactIconButton(
            icon: Icons.edit_outlined,
            onTap: () => ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Profile editing arrives with accounts.'),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CompactIconButton extends StatelessWidget {
  const _CompactIconButton({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: AppColors.background,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppColors.border),
        ),
        child: Icon(icon, size: 17, color: AppColors.textSecondary),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 10),
      child: Text(
        label,
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          letterSpacing: 1,
          color: AppColors.textTertiary,
        ),
      ),
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Column(children: children),
      ),
    );
  }
}

class _SettingsRow extends StatelessWidget {
  const _SettingsRow({
    required this.title,
    this.value,
    this.trailing,
    this.trailingWidget,
    this.onTap,
    this.showDivider = true,
  });

  final String title;
  final String? value;
  final Widget? trailing;
  final Widget? trailingWidget;
  final VoidCallback? onTap;
  final bool showDivider;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(
                      fontSize: 13.5,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ),
                if (value != null) ...[
                  Text(
                    value!,
                    style: const TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: AppColors.violet,
                    ),
                  ),
                ],
                if (trailingWidget != null) trailingWidget!,
                if (trailing != null) trailing!,
              ],
            ),
          ),
          if (showDivider) const Divider(indent: 16, endIndent: 16),
        ],
      ),
    );
  }
}

class _CheckIcon extends StatelessWidget {
  const _CheckIcon({required this.visible});

  final bool visible;

  @override
  Widget build(BuildContext context) {
    if (!visible) return const SizedBox(width: 18);
    return const Icon(Icons.check_rounded, size: 17, color: AppColors.violet);
  }
}
