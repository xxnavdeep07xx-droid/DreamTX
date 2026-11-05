import '../models/design_collection.dart';

/// Contract for the design direction catalogue.
abstract class DesignRepository {
  Future<List<DesignCollection>> collections();
}

/// Mock catalogue of the launch design directions.
class MockDesignRepository implements DesignRepository {
  @override
  Future<List<DesignCollection>> collections() async {
    await Future<void>.delayed(const Duration(milliseconds: 240));
    return const [
      DesignCollection(
        direction: DesignDirection.editorial,
        name: 'Editorial',
        blurb: 'Type-led, magazine layouts',
      ),
      DesignCollection(
        direction: DesignDirection.cinematic,
        name: 'Cinematic',
        blurb: 'Moody, wide compositions',
      ),
      DesignCollection(
        direction: DesignDirection.minimal,
        name: 'Minimal',
        blurb: 'Quiet space, sharp focus',
      ),
      DesignCollection(
        direction: DesignDirection.scientific,
        name: 'Scientific',
        blurb: 'Data with clarity',
      ),
      DesignCollection(
        direction: DesignDirection.corporate,
        name: 'Corporate',
        blurb: 'Structured and confident',
      ),
      DesignCollection(
        direction: DesignDirection.experimental,
        name: 'Experimental',
        blurb: 'Playful geometry',
      ),
    ];
  }
}
