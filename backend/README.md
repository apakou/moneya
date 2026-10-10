# MoneyA backend

NestJS monorepo (pnpm workspace). Design and plan: `docs/backend/stellar-mvp-plan.md`;
start here: `docs/backend/STELLAR_KICKOFF.md`.

```
apps/api               NestJS API (health endpoint + invisibility interceptor so far)
packages/chain         ChainAdapter + Stellar implementation (offline-tested; network part needs STL-00)
packages/invisibility  Stablecoin-invisibility guard + OpenAPI contract lint
```

## Commands

```bash
pnpm install
pnpm lint && pnpm typecheck && pnpm test && pnpm build
PORT=3000 node apps/api/dist/main.js     # after pnpm build
```

Node ≥ 22. Copy `.env.example` to `.env` for local work; there is deliberately no default for
`STELLAR_USDC_ISSUER` — verify it against Circle's documentation.

## Non-negotiable

Users must never learn that stablecoins are used: the public API is **fiat-only**
(`docs/backend/openapi.yaml`). Two automated checks enforce it:

- `packages/invisibility/test/contract.spec.ts` lints every response in the OpenAPI contract.
- `InvisibilityInterceptor` fails any non-production response that leaks chain/asset details.
