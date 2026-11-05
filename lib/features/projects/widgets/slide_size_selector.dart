import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../app/theme/app_colors.dart';
import '../models/slide_size.dart';

/// Selectable slide size: three presets plus a custom width/height entry.
///
/// The widget owns its selection state and reports the resulting
/// [SlideSize] through [onChanged] on every relevant edit. A `null` value
/// means the current custom input is incomplete or invalid — the parent
/// should disable creation in that case.
class SlideSizeSelector extends StatefulWidget {
  const SlideSizeSelector({super.key, required this.onChanged});

  final ValueChanged<SlideSize?> onChanged;

  @override
  State<SlideSizeSelector> createState() => _SlideSizeSelectorState();
}

class _SlideSizeSelectorState extends State<SlideSizeSelector> {
  SlideSizePreset _preset = SlideSizePreset.widescreen;
  bool _metric = false;
  bool _customDirty = false;

  final TextEditingController _widthController = TextEditingController();
  final TextEditingController _heightController = TextEditingController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      widget.onChanged(_currentSize);
    });
  }

  @override
  void dispose() {
    _widthController.dispose();
    _heightController.dispose();
    super.dispose();
  }

  SlideSize? get _currentSize {
    switch (_preset) {
      case SlideSizePreset.widescreen:
        return SlideSize.widescreen;
      case SlideSizePreset.standard:
        return SlideSize.standard;
      case SlideSizePreset.portrait:
        return SlideSize.portrait;
      case SlideSizePreset.custom:
        final width = _parseField(_widthController.text);
        final height = _parseField(_heightController.text);
        if (width == null || height == null) return null;
        return SlideSize.tryCustom(
          widthInches: _metric ? width / SlideSize.cmPerInch : width,
          heightInches: _metric ? height / SlideSize.cmPerInch : height,
        );
    }
  }

  double? _parseField(String text) =>
      SlideSize.tryParseMeasurement(text);

  String? get _widthError => _errorFor(_widthController.text);
  String? get _heightError => _errorFor(_heightController.text);

  String? _errorFor(String text) {
    if (_preset != SlideSizePreset.custom || !_customDirty) return null;
    final value = _parseField(text);
    if (value == null) return 'Enter a number';
    final inches = _metric ? value / SlideSize.cmPerInch : value;
    if (inches < SlideSize.minInches || inches > SlideSize.maxInches) {
      return _metric
          ? 'Between ${(SlideSize.minInches * SlideSize.cmPerInch).toStringAsFixed(1)} and ${(SlideSize.maxInches * SlideSize.cmPerInch).toStringAsFixed(1)} cm'
          : 'Between ${SlideSize.minInches.toInt()} and ${SlideSize.maxInches.toInt()} in';
    }
    return null;
  }

  void _select(SlideSizePreset preset) {
    if (_preset == preset) return;
    setState(() {
      _preset = preset;
      if (preset != SlideSizePreset.custom) _customDirty = false;
    });
    widget.onChanged(_currentSize);
  }

  void _onCustomEdited() {
    if (!_customDirty) {
      setState(() => _customDirty = true);
    } else {
      setState(() {}); // refresh inline errors
    }
    widget.onChanged(_currentSize);
  }

  @override
  Widget build(BuildContext context) {
    final size = _currentSize;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: _PresetCard(
                label: 'Widescreen',
                caption: SlideSize.widescreen.presetCaption,
                detail: '16:9',
                glyphWidth: 30,
                glyphHeight: 17,
                selected: _preset == SlideSizePreset.widescreen,
                onTap: () => _select(SlideSizePreset.widescreen),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _PresetCard(
                label: 'Standard',
                caption: SlideSize.standard.presetCaption,
                detail: '4:3',
                glyphWidth: 26,
                glyphHeight: 20,
                selected: _preset == SlideSizePreset.standard,
                onTap: () => _select(SlideSizePreset.standard),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _PresetCard(
                label: 'Portrait',
                caption: SlideSize.portrait.presetCaption,
                detail: '9:16',
                glyphWidth: 17,
                glyphHeight: 30,
                selected: _preset == SlideSizePreset.portrait,
                onTap: () => _select(SlideSizePreset.portrait),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _PresetCard(
                label: 'Custom',
                caption: 'Set exact size',
                detail: 'Any',
                glyphWidth: 24,
                glyphHeight: 24,
                selected: _preset == SlideSizePreset.custom,
                onTap: () => _select(SlideSizePreset.custom),
              ),
            ),
          ],
        ),
        AnimatedCrossFade(
          duration: const Duration(milliseconds: 180),
          sizeCurve: Curves.easeOut,
          crossFadeState: _preset == SlideSizePreset.custom
              ? CrossFadeState.showSecond
              : CrossFadeState.showFirst,
          firstChild: const SizedBox(width: double.infinity),
          secondChild: Padding(
            padding: const EdgeInsets.only(top: 12),
            child: _CustomSizePanel(
              widthController: _widthController,
              heightController: _heightController,
              widthError: _widthError,
              heightError: _heightError,
              metric: _metric,
              onMetricChanged: (value) {
                setState(() => _metric = value);
                widget.onChanged(_currentSize);
              },
              onChanged: _onCustomEdited,
            ),
          ),
        ),
        const SizedBox(height: 14),
        Text(
          size == null
              ? (_metric
                  ? 'Enter a slide width and height in centimetres.'
                  : 'Enter a slide width and height in inches.')
              : 'Slides will measure ${size.label()} '
                  '(${size.label(metric: true)}).',
          style: TextStyle(
            fontSize: 11.5,
            height: 1.45,
            color: size == null ? AppColors.warning : AppColors.textTertiary,
          ),
        ),
      ],
    );
  }
}

/// One selectable preset tile with a proportioned glyph.
class _PresetCard extends StatelessWidget {
  const _PresetCard({
    required this.label,
    required this.caption,
    required this.detail,
    required this.glyphWidth,
    required this.glyphHeight,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final String caption;
  final String detail;
  final double glyphWidth;
  final double glyphHeight;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(15),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          curve: Curves.easeOut,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: selected
                ? AppColors.violet.withOpacity(0.07)
                : AppColors.card,
            borderRadius: BorderRadius.circular(15),
            border: Border.all(
              color: selected
                  ? AppColors.violet.withOpacity(0.45)
                  : AppColors.border,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 140),
                    width: glyphWidth,
                    height: glyphHeight,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(3),
                      border: Border.all(
                        color:
                            selected ? AppColors.violet : AppColors.border,
                        width: selected ? 1.6 : 1.2,
                      ),
                      color: selected
                          ? AppColors.violet.withOpacity(0.16)
                          : Colors.transparent,
                    ),
                  ),
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 140),
                    width: 15,
                    height: 15,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: selected ? AppColors.violet : Colors.transparent,
                      border: Border.all(
                        color: selected ? AppColors.violet : AppColors.border,
                        width: selected ? 4.4 : 1.6,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 11),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w600,
                  letterSpacing: -0.1,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                '$detail · $caption',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 10.5,
                  color: AppColors.textTertiary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Width/height inputs with an inch/centimetre unit toggle.
class _CustomSizePanel extends StatelessWidget {
  const _CustomSizePanel({
    required this.widthController,
    required this.heightController,
    required this.widthError,
    required this.heightError,
    required this.metric,
    required this.onMetricChanged,
    required this.onChanged,
  });

  final TextEditingController widthController;
  final TextEditingController heightController;
  final String? widthError;
  final String? heightError;
  final bool metric;
  final ValueChanged<bool> onMetricChanged;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final unit = metric ? 'cm' : 'in';
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Exact dimensions',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.2,
                    color: AppColors.textSecondary,
                  ),
                ),
              ),
              _UnitToggle(metric: metric, onChanged: onMetricChanged),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: TextField(
                  key: const Key('custom-width-field'),
                  controller: widthController,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                  ],
                  onChanged: (_) => onChanged(),
                  decoration: InputDecoration(
                    labelText: 'Width',
                    suffixText: unit,
                    errorText: widthError,
                    errorMaxLines: 2,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  key: const Key('custom-height-field'),
                  controller: heightController,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                  ],
                  onChanged: (_) => onChanged(),
                  decoration: InputDecoration(
                    labelText: 'Height',
                    suffixText: unit,
                    errorText: heightError,
                    errorMaxLines: 2,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Compact in/cm segmented toggle.
class _UnitToggle extends StatelessWidget {
  const _UnitToggle({required this.metric, required this.onChanged});

  final bool metric;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _chip('in', selected: !metric, onTap: () => onChanged(false)),
          _chip('cm', selected: metric, onTap: () => onChanged(true)),
        ],
      ),
    );
  }

  Widget _chip(String label, {required bool selected, required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
        decoration: BoxDecoration(
          color: selected ? AppColors.violet.withOpacity(0.16) : Colors.transparent,
          borderRadius: BorderRadius.circular(7),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11.5,
            fontWeight: FontWeight.w600,
            color: selected ? AppColors.violet : AppColors.textTertiary,
          ),
        ),
      ),
    );
  }
}
