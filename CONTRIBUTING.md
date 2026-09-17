# Contributing

The app is a beta I build for my own use, so I may not get to issues or pull requests quickly.

## Requirements

- macOS 26 or later, Xcode 26 or later
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) and the other tools in the `Brewfile` (`Scripts/bootstrap.sh` installs them)

## Getting started

```bash
Scripts/bootstrap.sh     # brew bundle + xcodegen generate
Scripts/run-debug.sh     # build and launch the Debug app
Scripts/test.sh          # package unit tests (add --ui for UI tests)
Scripts/lint.sh          # swift-format, SwiftLint, module rules
```

The Xcode project is generated from `project.yml` and isn't committed.

## Layout

| Path | Contents |
|---|---|
| `App/` | The app target: composition root, routing, root view, commands |
| `Packages/ADHKit/Sources` | One module per feature and per infrastructure piece |
| `Packages/ADHKit/Tests` | Swift Testing suites, fixtures (real catalog and AVD files) and shared fakes |
| `UITests/` | XCUITest suites |
| `Scripts/` | Development scripts |

Features only depend on the domain modules (`SDKDomain`, `DeviceDomain`) and shared UI modules;
`App/Sources/Composition/AppComposition.swift` is the only place concrete implementations are created.
`Scripts/check-deps.sh` enforces this.

## Useful scripts

- `Scripts/generate-hardware-profiles.py` refreshes the bundled device definitions from the Android SDK.
- `ADH_INTEGRATION=1 swift test --filter GoogleToolsCompatibility` checks that Google's `sdkmanager`
  accepts the `package.xml` files the app writes (needs cmdline-tools and Java; development only).
- `Scripts/snapshot.sh` asks a running Debug build to save PNGs of its windows.
- `swift Scripts/generate-app-icon.swift` redraws the app icon.
- `python3 Scripts/generate-notices.py` rebuilds `App/Resources/ThirdPartyNotices.md` from the resolved packages.

## Live tests (need a running emulator)

```bash
cd Packages/ADHKit
ADH_LIVE=1 swift test --filter "LiveEmulatorTests|LiveADBTests|LiveInspectorTests|LiveAPKLabelTests"
ADH_LIVE=1 ADH_LIVE_SLOW=1 swift test --filter LiveSlowInspectorTests
```

UI tests that drive the app (they take over the mouse and keyboard):

```bash
TEST_RUNNER_ADH_UI_SDK=/path/to/sdk xcodebuild test -project AndroidDeviceHub.xcodeproj -scheme AndroidDeviceHub \
  -destination 'platform=macOS' -only-testing:AndroidDeviceHubUITests/SetupFlowUITests
```

## Releases

Every push to `main` runs `.github/workflows/release.yml`. It lints, tests, builds a signed and notarized
app, and publishes it as a GitHub pre-release. Pull requests run `.github/workflows/ci.yml`.

The version is worked out during the build, and nothing is committed back:

- `MAJOR.MINOR` comes from `MARKETING_VERSION` in `project.yml`. Change it there to start a new series.
- The patch number is one more than the newest matching `v` tag.
- The build number is the number of commits on `main`.
