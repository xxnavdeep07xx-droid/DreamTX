import 'dart:io' show exit;

/// Self-heal for the one process state that cannot be repaired in place.
///
/// When an APK is installed over a still-alive DreamTX process (sideloading
/// the new release over the running app), the process keeps executing the
/// old Dart AOT code — the engine and AOT snapshot load from native code,
/// not from dex — but its Java classloader now points at dex files that were
/// just replaced on disk. The first Java class a plugin lazily loads dies
/// with `ClassNotFoundException` mentioning `DexPathList`, which is exactly
/// what the deck store's path_provider call hits. No in-process code can
/// repair a stale classloader, so the app kills itself once (`exit(0)`) and
/// the user's next launch is a healthy cold start of the new build — decks
/// untouched on disk, nothing lost.
class StaleProcessRestart {
  StaleProcessRestart._();

  /// The kill action. A static seam so widget tests can observe the exit
  /// instead of dying with the test runner; production never touches it.
  static void Function() kill = _exit;

  static void _exit() => exit(0);

  /// Latched by the first stale-classloader detection: guarantees exactly
  /// one self-heal per process. A (practically impossible) second detection
  /// falls back to the manual restart card instead of looping.
  static bool armed = false;
}
