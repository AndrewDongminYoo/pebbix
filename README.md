<!-- SPDX-FileCopyrightText: 2026 kr.donminzzi -->
<!-- SPDX-License-Identifier: CC-BY-4.0 -->

# Pebbix

![coverage][coverage_badge]
[![style: very good analysis][very_good_analysis_badge]][very_good_analysis_link]

A bubble-shooter puzzle game built with [Flutter][flutter_link] and [Flame][flame_link], scaffolded from the [Very Good CLI][very_good_cli_link] `flame_game` template.

## Distribution and licensing

Pebbix is shared here as a selected, source-available snapshot with a new history.
The existing development repository and its history remain private.
Store development is winding down, and Android store distribution is planned to end after this source transition.
This repository does not certify that either store has already been withdrawn.
Feature development and ongoing support are not promised.
Visit the [Pebbix website](https://pebbix.donminzzi.kr) for distribution information, privacy information, and support.

Pebbix uses a mixed-license, source-available policy: the game is PolyForm Noncommercial 1.0.0, the five explicitly designated reusable source files and two synthesized cues are MIT, and original explanatory prose is CC BY 4.0.
Original graphics use CC BY-NC 4.0 to the extent rights are held; external audio and fonts keep their existing terms.
Read the [exact scope and exceptions](LICENSE), [third-party notices](THIRD_PARTY_NOTICES.md), and [brand guidance](BRAND_USAGE.md) before reusing material.
Small fragments of other game files do not become MIT, and independently created games using the MIT components are permitted.

Aim from the launcher at the bottom, bounce off the side walls, and land a bubble against the grid.
Three or more of the same color pop, anything left dangling from the ceiling drops with them, and the ceiling itself descends a row every six shots.
Let the grid cross the fail line and the run ends.

The puzzle is deterministic by design: the whole shot — wall reflections, contact point, and the cell it snaps into — is solved in plain Dart before anything moves on screen, so the same input on the same board always produces the same result.
Flame only animates the precomputed path.

---

## Getting Started 🚀

### Credential-free web baseline

Use the Flutter SDK version constraints in `pubspec.yaml` and the committed lockfile.
The web development entrypoint needs no publisher Firebase access, signing files, advertising account, or store credentials:

```sh
flutter pub get --enforce-lockfile
flutter gen-l10n
flutter run -d chrome --target lib/main_development.dart
```

For a static build:

```sh
flutter build web --no-web-resources-cdn --target lib/main_development.dart
python3 -m http.server 8787 --bind 127.0.0.1 --directory build/web
```

Open `http://127.0.0.1:8787` to play the built game.
Native mobile builds are optional and need their own configuration as described below.

### Native flavors

This project contains 3 flavors:

- development
- staging
- production

To run the desired flavor either use the launch configuration in VSCode/Android Studio or use the following commands:

```sh
# Development
flutter run --flavor development --target lib/main_development.dart

# Staging
flutter run --flavor staging --target lib/main_staging.dart

# Production
flutter run --flavor production --target lib/main_production.dart
```

Platform folders present in this repo: Android, iOS, macOS, and Web.

### Task runner

Common workflows are wrapped with [`merry`][merry_link]; see `merry.yaml` for the full list.

```sh
merry ls          # list every script this project defines
merry dev         # run with hot reload
merry web         # run in Chrome
merry check       # format + analyze + test — the gate to run before committing
merry format      # dart fix, import sorting, dart format
merry build apk   # release artifacts: build apk | aab | ipa | macos | web
```

---

## Running Tests 🧪

```sh
merry coverage    # flutter test --coverage --test-randomize-ordering-seed=random
```

To view the generated coverage report you can use [lcov](https://github.com/linux-test-project/lcov).

```sh
# Generate Coverage Report
genhtml coverage/lcov.info -o coverage/

# Open Coverage Report
open coverage/index.html
```

CI enforces **100% line coverage**, so every new file needs matching tests.
It also runs the test suite through `very_good test --optimization`, which merges every test file into one entrypoint — a subtly different runner from `flutter test`.
That job runs on pushes to `main` but not on pull requests, so a local run is the only check a PR gets before merge.
The store-asset tests also need ImageMagick's `magick` command on your `PATH`.
To reproduce CI exactly before pushing:

```sh
dart pub global activate very_good_cli 1.5.0
very_good test --coverage --min-coverage 100 --optimization \
  --report-on "lib" --test-randomize-ordering-seed random
```

---

## Bloc Lints 🔍

This project uses the [bloc_lint](https://pub.dev/packages/bloc_lint) package to enforce best practices using [bloc](https://pub.dev/packages/bloc).
The rule set is enabled through `analysis_options.yaml`, which includes `package:bloc_lint/recommended.yaml`.

The linter itself ships in [bloc_tools](https://pub.dev/packages/bloc_tools), which is a global CLI rather than a project dependency:

```sh
dart pub global activate bloc_tools
bloc lint .
```

You can also validate with VSCode-based IDEs using the [official bloc extension](https://marketplace.visualstudio.com/items?itemName=FelixAngelov.bloc).

To learn more, visit <https://bloclibrary.dev/lint/>

---

## Project Layout 🗂

```log
lib/
├── app/          app widget and root routing
├── loading/      PreloadCubit — audio and image preloading with a progress screen
├── title/        title screen
├── game/
│   ├── domain/       pure Dart puzzle logic — no Flame, no Flutter
│   ├── components/   the Flame layer — board, bubbles, projectile, aim, background
│   ├── cubit/        AudioCubit — volume, BGM, and effect playback
│   ├── view/         GamePage / GameView — builds the FlameGame and hosts it
│   └── widgets/      Flutter overlays stacked on the game (score HUD, game over)
├── l10n/         ARB sources and generated localizations
└── gen/          generated type-safe asset references
```

The game never reaches into the Flutter widget tree.
Localizations, audio players, and the image cache are all injected into the `BubbleShooter` constructor from `GameView`, which keeps the Flame side testable on its own.

---

## Platform Notes 📱

iOS and macOS use **Swift Package Manager** rather than CocoaPods; there are no Podfiles.
The Xcode schemes and `project.pbxproj` files are generated by `flutter_tools` — to change them, adjust the input and re-run:

```sh
flutter build ios --config-only --flavor development --target lib/main_development.dart
```

### Firebase configuration

The web baseline skips native Firebase initialization.
For an optional Android or iOS build, install the Firebase and FlutterFire CLIs, sign in to an account you control, and explicitly select your own Firebase project:

```sh
FIREBASE_PROJECT_ID=your-firebase-project-id python3 tool/configure_firebase.py
# Equivalent task-runner command:
FIREBASE_PROJECT_ID=your-firebase-project-id merry run generate firebase
```

Missing `FIREBASE_PROJECT_ID` stops before invoking FlutterFire.
The helper generates configuration for this source tree's existing application identifiers and only runs the SPM postprocessor after successful configuration.
Forks intended for distribution must also choose their own application identifiers and signing settings.
Generated `firebase.json`, `google-services.json`, `GoogleService-Info.plist`, and `firebase_options.dart` are ignored by Git.
Native production initialization reads that configuration and enables Crashlytics; use your own project and review its collection settings before distributing a native build.

The app is locked to portrait, including on iPad (`UIRequiresFullScreen`).

---

## Working with Translations 🌐

This project relies on [flutter_localizations][flutter_localizations_link] and follows the [official internationalization guide for Flutter][internationalization_link].
English (`lib/l10n/arb/app_en.arb`) and Korean (`app_ko.arb`) ship today; Korean devices get Korean, everything else falls back to English.

### Adding Strings

1. To add a new localizable string, open the `app_en.arb` file at `lib/l10n/arb/app_en.arb` and add a key with its description.

```arb
{
  "@@locale": "en",
  "helloWorld": "Hello World",
  "@helloWorld": {
    "description": "Hello World Text"
  }
}
```

2. Regenerate the localizations.

```sh
merry generate l10n    # flutter gen-l10n
```

3. Use the new string.

<!-- SPDX-SnippetBegin -->
<!-- SPDX-SnippetCopyrightText: 2022 Very Good Ventures -->
<!-- SPDX-License-Identifier: MIT -->

```dart
import 'package:bubble_shooter/l10n/l10n.dart';

@override
Widget build(BuildContext context) {
  final l10n = context.l10n;
  return Text(l10n.helloWorld);
}
```

<!-- SPDX-SnippetEnd -->

### Adding Supported Locales

Add a new ARB file per locale in `lib/l10n/arb` (for example `app_ja.arb`) with the same keys translated, then update the `CFBundleLocalizations` array in `ios/Runner/Info.plist` to include the new locale.

```xml
<key>CFBundleLocalizations</key>
<array>
    <string>en</string>
    <string>ko</string>
</array>
```

`AppLocalizations.supportedLocales` is generated in alphabetical order, and `MaterialApp` falls back to its **first** entry for any locale it cannot match.
`en` sorts first today, which is what makes English the fallback for everything except Korean.
If you add a locale that sorts before `en`, set an explicit `localeResolutionCallback` rather than relying on that ordering.

[coverage_badge]: coverage_badge.svg
[flame_link]: https://flame-engine.org
[flutter_link]: https://flutter.dev
[flutter_localizations_link]: https://api.flutter.dev/flutter/flutter_localizations/flutter_localizations-library.html
[internationalization_link]: https://flutter.dev/docs/development/accessibility-and-localization/internationalization
[merry_link]: https://pub.dev/packages/merry
[very_good_analysis_badge]: https://img.shields.io/badge/style-very_good_analysis-B22C89.svg
[very_good_analysis_link]: https://pub.dev/packages/very_good_analysis
[very_good_cli_link]: https://github.com/VeryGoodOpenSource/very_good_cli
