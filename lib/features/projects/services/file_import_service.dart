import '../../../shared/services/file_picker_service.dart';

/// The document kinds DreamTX can stage for import.
enum ImportFileKind { powerpoint, pdf, word, unsupported }

/// A picked file together with its validated import metadata.
class ImportCandidate {
  const ImportCandidate._({
    required this.file,
    required this.kind,
    required this.extension,
  });

  final PickedFile file;
  final ImportFileKind kind;

  /// Lowercase extension without the dot, e.g. `pptx`.
  final String extension;

  bool get isSupported => kind != ImportFileKind.unsupported;

  String get typeLabel => switch (kind) {
        ImportFileKind.powerpoint => 'PowerPoint presentation',
        ImportFileKind.pdf => 'PDF document',
        ImportFileKind.word => 'Word document',
        ImportFileKind.unsupported => 'File',
      };

  /// Project name suggested from the file name (extension stripped).
  /// Empty when the file name is nothing but its extension.
  String get suggestedName {
    final name = file.name.trim();
    final lower = name.toLowerCase();
    if (lower.endsWith('.$extension') && name.length > extension.length + 1) {
      return name.substring(0, name.length - extension.length - 1).trim();
    }
    if (lower == '.$extension' || lower == extension) return '';
    return name;
  }

  /// Friendly explanation for rejected files, tailored to common legacy
  /// Office formats.
  String get unsupportedHint {
    switch (extension) {
      case 'doc':
        return 'Older Word documents (.doc) are not supported yet — '
            're-save the file as .docx and try again.';
      case 'ppt':
        return 'Older PowerPoint decks (.ppt) are not supported yet — '
            're-save the file as .pptx and try again.';
      default:
        return 'DreamTX can import PPTX, PDF and DOCX files. '
            'Pick one of those formats to continue.';
    }
  }

  /// Validates a picked file purely from its name/extension.
  factory ImportCandidate.fromPickedFile(PickedFile file) {
    final name = file.name.trim();
    final dot = name.lastIndexOf('.');
    var extension = '';
    if (dot >= 0 && dot < name.length - 1) {
      extension = name.substring(dot + 1).toLowerCase();
    }
    final ImportFileKind kind = switch (extension) {
      'pptx' => ImportFileKind.powerpoint,
      'pdf' => ImportFileKind.pdf,
      'docx' => ImportFileKind.word,
      _ => ImportFileKind.unsupported,
    };
    return ImportCandidate._(
      file: file,
      kind: kind,
      extension: extension.isEmpty ? 'file' : extension,
    );
  }
}

/// Bridges the native Android file picker and the import validation layer.
///
/// Deliberately kept separate from the (future) document conversion
/// engine: this service only picks and validates; conversion will be its
/// own module behind the same boundary.
class FileImportService {
  const FileImportService({FilePickerService? picker})
      : _picker = picker ?? const FilePickerService();

  final FilePickerService _picker;

  /// Opens the native document picker. Returns `null` when the user
  /// cancels; throws [FilePickerUnsupportedException] off-Android.
  Future<ImportCandidate?> pickFile() async {
    final file = await _picker.pickDocument();
    if (file == null) return null;
    return ImportCandidate.fromPickedFile(file);
  }
}
