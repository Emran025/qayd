# Qayd release matrix

The normal store release path is independent of Shorebird. Create a `v1.2.3` tag or run **Qayd Cross-Platform Release** manually to build the supported targets:

| Target | Runner | Artifact | Signing state |
| --- | --- | --- | --- |
| Android | Ubuntu | APK/AAB from `build-release.yml` | Release keystore injected from GitHub Actions secrets |
| Web | Ubuntu | `qayd-web-*.tar.gz` | No platform signing; deploy behind HTTPS |
| Linux | Ubuntu | `qayd-linux-*.tar.gz` | Unsigned desktop bundle; package/sign with the distribution key at delivery |
| Windows | Windows | `qayd-windows-*.tar.gz` | Unsigned desktop bundle; Authenticode signing is a delivery step |
| macOS | macOS | `qayd-macos-*.tar.gz` | Build-ready; App Store/notarized distribution requires the Apple certificate and team |
| iOS | macOS | `qayd-ios-unsigned-*.tar.gz` | Compile validation only (`--no-codesign`); App Store signing requires Apple credentials |

The Web target is part of the Flutter project under `web/`; the cross-platform workflow now builds and archives it instead of treating Android as the only release target.

## Apple identifiers and signing

The checked-in defaults are non-placeholder identifiers:

- iOS: `com.accsystem.qayd`
- macOS: `com.accsystem.qayd.macos`

Set `QAYD_IOS_BUNDLE_ID` and `QAYD_MACOS_BUNDLE_ID` as GitHub repository variables only when the identifiers registered in the Apple Developer account differ. The signed Apple pipeline must additionally provide the real Apple Team ID, distribution certificate, provisioning profile, and export options. Those values are intentionally not committed and cannot be safely invented in source control.

The unsigned iOS job is deliberate: it catches Flutter, CocoaPods, Xcode, and native-plugin regressions on every release without pretending that a release can be submitted to the App Store without the account's signing material.

## Required release configuration

Android's existing workflow validates `QAYD_API_URL`, `QAYD_ANDROID_APPLICATION_ID`, and the Android keystore secrets. The cross-platform workflow validates the API URL when supplied and rejects `com.example.*` Apple identifiers. The Laravel API deployment remains in `qayd_api/.github/workflows/deploy.yml`; it runs after a push to `main` and uses the server secrets already documented by that workflow.

Shorebird is retained only as an explicit `workflow_dispatch` OTA workflow. It is not a dependency of the normal Android, Apple, desktop, or Web release paths.
