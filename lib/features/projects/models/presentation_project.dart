/// A persisted presentation project — the single source of truth for the
/// library, the dashboard and (later) the editor.
library;

import 'slide_size.dart';

/// How the project came into existence.
enum ProjectSource {
  blank,
  imported,
  externalAi;

  String get label => switch (this) {
        ProjectSource.blank => 'Blank project',
        ProjectSource.imported => 'Imported file',
        ProjectSource.externalAi => 'AI assistant',
      };
}

/// Lifecycle state of a project.
///
/// [importPending] marks projects created from a picked file whose content
/// has not been converted yet — the conversion engine ships separately.
enum ProjectStatus {
  active,
  importPending;

  String get label => switch (this) {
        ProjectStatus.active => 'Ready',
        ProjectStatus.importPending => 'Import pending',
      };
}

class PresentationProject {
  const PresentationProject({
    required this.id,
    required this.name,
    required this.createdAt,
    required this.modifiedAt,
    required this.slideWidthEmu,
    required this.slideHeightEmu,
    required this.slides,
    required this.source,
    required this.status,
    required this.filePath,
    this.sourceUri,
  });

  /// Marker written into every document so future versions can migrate.
  static const String formatIdentifier = 'dreamtx.project/1';

  final String id;
  final String name;
  final DateTime createdAt;
  final DateTime modifiedAt;

  /// Slide width in EMU (914400 per inch) — never a display label.
  final int slideWidthEmu;

  /// Slide height in EMU (914400 per inch).
  final int slideHeightEmu;

  /// The slide collection. Empty until the editor ships; the future editor
  /// appends slide records here.
  final List<String> slides;

  final ProjectSource source;
  final ProjectStatus status;

  /// Absolute path of the `.dreamtx` document on this device.
  final String filePath;

  /// URI of the original document for imported projects, until conversion.
  final String? sourceUri;

  int get slideCount => slides.length;

  String get slideCountLabel =>
      slideCount == 1 ? '1 slide' : '$slideCount slides';

  String get sourceLabel => source.label;
  String get statusLabel => status.label;

  double get aspectRatio => slideHeightEmu == 0
      ? 16 / 9
      : slideWidthEmu / slideHeightEmu;

  SlideSize get slideSize =>
      SlideSize.fromEmu(slideWidthEmu, slideHeightEmu);

  PresentationProject copyWith({
    String? name,
    DateTime? modifiedAt,
    List<String>? slides,
    ProjectStatus? status,
  }) {
    return PresentationProject(
      id: id,
      name: name ?? this.name,
      createdAt: createdAt,
      modifiedAt: modifiedAt ?? this.modifiedAt,
      slideWidthEmu: slideWidthEmu,
      slideHeightEmu: slideHeightEmu,
      slides: slides ?? this.slides,
      source: source,
      status: status ?? this.status,
      filePath: filePath,
      sourceUri: sourceUri,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'format': formatIdentifier,
        'id': id,
        'name': name,
        'createdAt': createdAt.toUtc().toIso8601String(),
        'modifiedAt': modifiedAt.toUtc().toIso8601String(),
        'slideWidth': slideWidthEmu,
        'slideHeight': slideHeightEmu,
        'slides': slides,
        'source': source.name,
        'status': status.name,
        'sourceUri': sourceUri,
      };

  /// Restores a project from persisted JSON. The [filePath] is the location
  /// the document was read from — it is not stored inside the document.
  ///
  /// Malformed documents raise [FormatException] so callers (the
  /// repository) can skip them instead of crashing.
  static PresentationProject fromJson(
    Map<String, dynamic> json, {
    required String filePath,
  }) {
    try {
      return _fromJsonUnchecked(json, filePath: filePath);
    } on TypeError {
      throw const FormatException('Malformed project document');
    } on ArgumentError {
      throw const FormatException('Unknown enum value in project document');
    }
  }

  static PresentationProject _fromJsonUnchecked(
    Map<String, dynamic> json, {
    required String filePath,
  }) {
    if (json['format'] != formatIdentifier) {
      throw const FormatException('Unknown project document format');
    }
    final id = json['id'] as String?;
    final name = json['name'] as String?;
    if (id == null || id.isEmpty || name == null) {
      throw const FormatException('Project document missing id or name');
    }
    final slides = (json['slides'] as List<dynamic>? ?? const <dynamic>[])
        .whereType<String>()
        .toList(growable: false);
    return PresentationProject(
      id: id,
      name: name,
      createdAt: DateTime.parse(json['createdAt'] as String),
      modifiedAt: DateTime.parse(json['modifiedAt'] as String),
      slideWidthEmu: json['slideWidth'] as int,
      slideHeightEmu: json['slideHeight'] as int,
      slides: slides,
      source: ProjectSource.values
          .byName((json['source'] as String?) ?? 'blank'),
      status: ProjectStatus.values
          .byName((json['status'] as String?) ?? 'active'),
      filePath: filePath,
      sourceUri: json['sourceUri'] as String?,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is PresentationProject && other.id == id);

  @override
  int get hashCode => id.hashCode;
}
