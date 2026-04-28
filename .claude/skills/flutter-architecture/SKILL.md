---
name: flutter-architecture
description: MoneyA Flutter project conventions — feature-first folder layout, Riverpod 2 state management, go_router navigation, freezed models, dio HTTP client, and dependency injection patterns. USE WHEN the user asks to add a feature, screen, provider, route, model, or repository; or mentions "scaffold", "structure", "where should I put", "Riverpod", "go_router", "freezed". DO NOT USE FOR pure UI styling questions or platform-specific (iOS/Android) native code.
---

# MoneyA Flutter Architecture

Feature-first Clean Architecture. Each feature is self-contained and depends only on `core/` and `shared/`.

## Folder layout

```
lib/
├── main.dart                       # bootstraps ProviderScope + MoneyaApp
├── app.dart                        # MaterialApp.router, theme, locale
├── core/
│   ├── router/app_router.dart      # go_router config, auth guard
│   ├── theme/                      # colors, typography, spacing tokens
│   ├── network/dio_client.dart     # interceptors: auth, idempotency, retry
│   ├── storage/secure_storage.dart # flutter_secure_storage wrapper
│   ├── errors/                     # AppFailure sealed class
│   └── utils/                      # formatters (currency, phone E.164)
├── features/
│   └── <feature>/
│       ├── data/
│       │   ├── dto/                # JSON ⇄ freezed DTOs
│       │   ├── datasources/        # remote (dio) + local (secure storage)
│       │   └── repositories/       # impl of domain repository
│       ├── domain/
│       │   ├── entities/           # pure freezed models, no JSON
│       │   ├── repositories/       # abstract interfaces
│       │   └── usecases/           # one class per action (SendMoney, Quote…)
│       └── presentation/
│           ├── providers/          # Riverpod providers + Notifiers
│           ├── screens/            # Page widgets, wired to router
│           └── widgets/            # feature-local reusable widgets
├── shared/widgets/                 # cross-feature widgets (AmountField, SwipeToConfirm)
└── l10n/                           # arb files: app_en.arb, app_fr.arb
```

## Feature list (MVP)

| Feature | Purpose |
|---|---|
| `auth` | Phone OTP, passcode, biometrics, KYC tiers |
| `wallet` | Balance display (local currency), tx history |
| `transfer` | Send money: quote → confirm → process |
| `voice` | STT capture, intent parsing, confirmation form prefill |
| `contacts` | Phone contact lookup, E.164 normalization |
| `onramp` | Mobile money → USDC top-up |
| `offramp` | USDC → mobile money cash-out |
| `escrow` | Unclaimed transfers, SMS invite, claim flow |
| `kyc` | Document upload, liveness, tier progression |

## State management (Riverpod 2)

- **Prefer `@riverpod` code-gen** (`riverpod_generator`) over manual providers.
- Stateful screens use `AsyncNotifier` / `Notifier`; never `StatefulWidget` for business state.
- Naming: `fooProvider` (value), `fooControllerProvider` (notifier), `fooRepositoryProvider`.
- Keep UI widgets `ConsumerWidget`; call `ref.watch` in `build`, `ref.read` in callbacks.

## Routing (go_router)

- Single `GoRouter` in `core/router/app_router.dart`.
- Auth guard via `redirect:` reading `authStateProvider`.
- Typed routes: use `TypedGoRoute` with `go_router_builder` when practical.
- Deep links: `/claim/:token` for escrow claim-by-SMS; configured in `AndroidManifest.xml` + `Info.plist`.

## Models (freezed + json_serializable)

- **Domain entities**: freezed only, no JSON annotations — pure app types.
- **DTOs** (in `data/dto/`): freezed + `@JsonSerializable`, with `toEntity()` / `fromEntity()`.
- Never expose DTOs to `presentation/`.
- Money: always `Money { int minorUnits; Currency currency; }` — never `double`.

## HTTP (dio)

- Single `Dio` instance in `coreNetworkModule`, with interceptors:
  1. **Auth**: attaches bearer token; refreshes on 401.
  2. **Idempotency**: adds `Idempotency-Key: <uuid>` for POST /transfers, /onramp, /offramp.
  3. **Retry**: exponential backoff on 5xx and network errors; never retry non-idempotent 4xx.
  4. **Logging**: redact `Authorization`, `passcode`, `pan`, `otp`.

## Code-gen workflow

```bash
dart run build_runner watch --delete-conflicting-outputs
```

Generated files (`*.g.dart`, `*.freezed.dart`) are **committed** so CI doesn't need codegen to compile.

## Checklist when adding a feature

- [ ] Create `lib/features/<feature>/{data,domain,presentation}/` skeleton
- [ ] Define domain entities (freezed) and repository interface
- [ ] Implement data DTO, datasource, repository impl
- [ ] Register providers via `@riverpod` code-gen
- [ ] Add screen(s) + route entry in `app_router.dart`
- [ ] Add l10n keys to both `app_en.arb` and `app_fr.arb`
- [ ] Widget test for happy path; unit test for usecase
