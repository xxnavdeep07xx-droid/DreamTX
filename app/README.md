// DreamTX app note
//
// Platform folders (android/, ios/, ...) are NOT committed — they are
// generated, locally or in CI, with:
//
//   flutter create --org com.dreamtx --project-name dreamtx .
//
// The Rust native library is cross-compiled into
// android/app/src/main/jniLibs/<abi>/libdreamtx.so — see
// ../scripts/build-android.sh (local) or the apk workflow (CI).

For the v1 launch cut, the app is Android-only; desktop targets follow later.
