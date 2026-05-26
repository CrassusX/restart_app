# restart_app example

Demonstrates how to use `restart_app`.

The example app shows:

- `Restart.restartApp()` with structured success/error handling
- path URL strategy on web
- an advanced opt-in iOS Flutter engine restart setup in `ios/Runner/AppDelegate.swift`
- a small Flutter package check panel that re-runs after restart

## Running

```bash
flutter pub get
flutter run
```

Use **Restart app** to dirty Dart-only state, restart, and confirm
the app returns with clean Dart state while common Flutter packages still work.

The checks cover shared preferences, package info, connectivity, URL launcher,
HTTP, cache/image loading, SVG rendering, file storage, SQLite, device info,
and WebView where the current platform supports them.

On iOS, the example intentionally configures a custom `FlutterEngine` factory
so it can prove that engine replacement works. Do not copy the example
`AppDelegate.swift` into a normal app unless you also own that custom engine
setup.

For normal Flutter apps, including Flutter 3.41+ UIScene apps whose delegate
conforms to `FlutterImplicitEngineDelegate`, use the setup in the root
[README](../README.md#ios). The example does not use the legacy notification
fallback unless the **iOS notification fallback** button is pressed explicitly.
