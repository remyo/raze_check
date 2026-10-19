# Raze Check

Standalone offline attendance application for Android and iOS, with reusable core,
local-adapter, and feature packages. The current foundation displays startup
identity; company and attendance workflows arrive in subsequent tasks.

Use Flutter 3.44.7 / Dart 3.12.2, pinned in `.fvmrc`. From the repository root:

```sh
flutter pub get
flutter run
flutter test
flutter analyze
```

Run pure Dart contracts from `packages/raze_check_core` with `dart test`.
See [the development baseline](docs/testing/development-baseline.md) for dependency
compatibility, native build commands, and outstanding verification gates.
