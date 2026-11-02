# Cohabit

A local-first habit tracker for macOS and Android, built with Flutter. Track positive and negative habits, log past days, and explore history through commit-style graphs. No account is required.

The roadmap includes on-device correlation analysis, import/export, platform widgets, and encrypted backups to self-hosted storage. These features are planned; see [the product spec](docs/SPEC.md).

## Run from source

Use Flutter **3.47.9** (Dart **3.13.7**) to match CI.

```sh
flutter pub get
flutter run -d macos
```

For Android, install Android Studio and its SDK, accept the SDK licences, then start an emulator or connect a phone with USB debugging enabled. Check the setup and select the device:

```sh
flutter doctor
flutter devices
flutter run -d <device-id>
```

The normal entry point starts with an empty, persistent SQLite database. Data stays on the device and survives app restarts. Uninstalling the app or clearing its storage removes that data; export and encrypted backup are still planned.

To explore generated history without writing to disk:

```sh
flutter run -t lib/main_demo.dart -d <device-id>
```

## Try the Android APK

Build an APK for local testing:

```sh
flutter build apk --debug
```

The result is `build/app/outputs/flutter-apk/app-debug.apk`. Copy it to your phone and open it, allowing installation from the app used to open the file when Android prompts. Or install over USB:

```sh
adb -s <device-id> install -r build/app/outputs/flutter-apk/app-debug.apk
```

CI also uploads a `cohabit-debug-apk` artifact for each successful Android build. Download it from the workflow run's artifacts and unzip it before installing.

The app appears as **Cohabit**, with package ID `io.github.diegohh0411.cohabit`. An older build using `com.example.cohabit` remains a separate installation and its data is not migrated. These debug builds are for testing; release distribution and signing are still to come.

## Navigation

Phones use bottom tabs for Today, History, Habits and Settings. Detail pages cover the tabs; Android Back returns to the section, then to Today. Wide and landscape Android windows use a sidebar. macOS uses a sidebar with ⌘1–4 to switch sections and ⌘N to create a habit.

## Development

```sh
flutter analyze
flutter test
flutter build apk --debug
```

Pixel-exact golden tests were generated on macOS. On other platforms, run `flutter test --exclude-tags golden`, as CI does.

Launcher icons are generated from the commit-graph motif using the Python standard library:

```sh
python3 tool/generate_launcher_icons.py
```
