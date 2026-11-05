/// A presentation project as shown across the dashboard and library.
class Project {
  const Project({
    required this.id,
    required this.title,
    required this.slideCount,
    required this.modifiedAt,
  });

  final String id;
  final String title;
  final int slideCount;
  final DateTime modifiedAt;

  String get slideCountLabel => slideCount == 1 ? '1 slide' : '$slideCount slides';

  Project copyWith({
    String? title,
    int? slideCount,
    DateTime? modifiedAt,
  }) {
    return Project(
      id: id,
      title: title ?? this.title,
      slideCount: slideCount ?? this.slideCount,
      modifiedAt: modifiedAt ?? this.modifiedAt,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) || (other is Project && other.id == id);

  @override
  int get hashCode => id.hashCode;
}
