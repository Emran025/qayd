# Qayd compatibility patch for `flutter_contacts`

This directory vendors the runtime source of `flutter_contacts` version `1.1.9+2` from pub.dev. The upstream MIT license is preserved in `LICENSE`.

The iOS plugin previously force-unwrapped `UIApplication.shared.delegate!.window!!.rootViewController!` during registration. Qayd registers plugins through `FlutterImplicitEngineDelegate` and uses the UIScene lifecycle, where the app-delegate window may be nil at that point; the force unwrap terminated `Runner` with `EXC_BREAKPOINT` before Flutter could expose its VM Service.

The local iOS change uses the engine-specific `registrar.viewController` and safely skips registration when there is no Flutter view controller. The Dart API, package version, and SDK constraints remain unchanged. The root app's `dependency_overrides` points to this directory so local builds and CI use the same patched source.

Keep this compatibility copy until an upstream version provides UIScene-safe registration. Before upgrading or removing the override, verify the plugin's controller lookup and rerun the iOS E2EE integration test. Do not patch the user's pub cache or apply a CI-only source rewrite.
