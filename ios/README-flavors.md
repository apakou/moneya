# iOS flavors (one-time Xcode setup)

Android `productFlavors` are fully declared in `android/app/build.gradle.kts`
and require zero per-machine setup. iOS is more invasive because `.xcconfig`
wiring lives inside `Runner.xcodeproj/project.pbxproj`, which is fragile
to edit by hand. Each engineer (or CI image) needs to do this once.

## One-time setup in Xcode

1. Open `ios/Runner.xcworkspace`.
2. In the project navigator, select **Runner** → **Info** → **Configurations**.
3. For each of the three configs Flutter knows about
   (`Debug`, `Release`, `Profile`), duplicate it three times so you end
   up with:
   - `Debug-dev`, `Debug-staging`, `Debug-prod`
   - `Release-dev`, `Release-staging`, `Release-prod`
   - `Profile-dev`, `Profile-staging`, `Profile-prod`
4. For each new configuration, set the **Runner** target's xcconfig file:
   - `*-dev`     → `Flutter/Dev.xcconfig`
   - `*-staging` → `Flutter/Staging.xcconfig`
   - `*-prod`    → `Flutter/Prod.xcconfig`
5. Open the scheme manager (**Product → Scheme → Manage Schemes…**) and
   duplicate `Runner` into `Runner-dev`, `Runner-staging`, `Runner-prod`.
6. For each new scheme, edit Run/Test/Profile/Archive to point at the
   matching configuration (e.g. `Runner-dev`'s **Run** uses `Debug-dev`).
7. In **Build Settings** for the Runner target, set the
   **Product Bundle Identifier** to `$(PRODUCT_BUNDLE_IDENTIFIER)` and
   the **Display Name** (`INFOPLIST_KEY_CFBundleDisplayName`) to
   `$(APP_DISPLAY_NAME)` so the xcconfig values are honoured.

Once that's done, `flutter run --flavor dev` and
`scripts/run_dev.sh` work end-to-end on iOS.

## CI

CI should commit the resulting `project.pbxproj` once the scheme/config
matrix is in place. From that point on, `flutter build ios --flavor=prod`
is enough for App Store Connect uploads.
