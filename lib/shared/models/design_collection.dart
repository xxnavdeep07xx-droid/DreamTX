/// Visual directions the future design engine will generate compositions in.
///
/// These are directions — not finished PowerPoint templates.
enum DesignDirection {
  editorial,
  cinematic,
  minimal,
  scientific,
  corporate,
  experimental,
}

class DesignCollection {
  const DesignCollection({
    required this.direction,
    required this.name,
    required this.blurb,
  });

  final DesignDirection direction;
  final String name;
  final String blurb;
}
