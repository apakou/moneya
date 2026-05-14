# MoneyA run scripts

Thin wrappers around `flutter run` that supply the `--flavor` and
`--dart-define` matrix expected by `lib/core/config/env.dart`. Each
flavor ships with its own Android `applicationId` (so dev / staging /
prod can coexist on one device) and, after the one-time Xcode setup
in `ios/README-flavors.md`, its own iOS bundle ID.

| Script               | Flavor   | API_BASE_URL default       | BYPASS_ONBOARDING |
| -------------------- | -------- | -------------------------- | ----------------- |
| `run_dev.sh`         | dev      | api.dev.moneya.app         | true (debug only) |
| `run_staging.sh`     | staging  | api.staging.moneya.app     | false             |
| `run_prod.sh`        | prod     | api.moneya.app             | always ignored    |

## Overriding

```sh
API_BASE_URL=http://10.0.2.2:4000 ./scripts/run_dev.sh
BYPASS_ONBOARDING=false ./scripts/run_dev.sh
./scripts/run_dev.sh -d <device-id>            # extra flags pass through
```

`BYPASS_ONBOARDING` is triple-guarded inside `Env.bypassOnboarding`:
- must be a debug build (`kDebugMode`),
- flavor must not be `prod`,
- the dart-define must be `true`.

Production builds therefore can **never** be tricked into skipping
KYC, even if a dart-define leaks in.

## openapi codegen

`openapi_nullable_fix.py` patches `docs/backend/openapi.yaml` for the
client codegen pipeline; unrelated to flavors.
