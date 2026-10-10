# MoneyA — Claude Configuration

This folder configures Claude's behavior for the MoneyA project.

## Structure

```
.claude/
├── skills/        # Domain knowledge (loaded on-demand via trigger phrases)
│   ├── flutter-architecture/
│   ├── usdc-stablecoin-ops/
│   ├── african-payment-rails/
│   ├── voice-intent-parsing/
│   ├── fintech-security/
│   └── fintech-mobile-uiux/
│       ├── SKILL.md
│       └── checklists/
│           ├── wcag22-aa.md
│           ├── microcopy.md
│           ├── motor-a11y.md
│           ├── trust-patterns.md
│           └── review-template.md
└── agents/        # Specialized subagents (invoked via run_subagent)
    ├── flutter-feature-builder.md
    ├── payment-flow-reviewer.md
    ├── i18n-auditor.md
    ├── voice-ux-designer.md
    ├── fintech-uiux-reviewer.md
    └── fintech-uiux-implementer.md
```

## How skills work
Each `skills/<name>/SKILL.md` begins with YAML frontmatter (`name`, `description`).
The `description` tells Claude **when** to load the skill. Keep triggers explicit.

## How subagents work
Each `agents/<name>.md` begins with YAML frontmatter (`name`, `description`, `tools`).
Invoke with `run_subagent(agentName="<name>", task="...")`.

## Project context (always-true facts)
- **Stack**: Flutter (Dart 3+), Riverpod 2, go_router, freezed, dio
- **Chain**: USDC on **Stellar** (pooled custody, backend only) — see `docs/backend/stellar-mvp-plan.md`
- **Corridors**: XOF (UEMOA), XAF (CEMAC), NGN, GHS, KES
- **Mobile money partners**: Wave, Orange Money, MTN MoMo, Moov, Airtel
- **Onramp/offramp candidates**: Yellow Card, Fonbnk, Juicyway, Onafriq, Accrue
- **Locales**: `fr`, `en` (primary); plan for Wolof, Bambara, Lingala, Pidgin voice
- **Architecture**: feature-first under `lib/features/<feature>/{data,domain,presentation}`
- **UX principle (non-negotiable)**: stablecoin and blockchain are invisible to end users — local currency, "MoneyA balance" and mobile money only; fiat-only API contract

## UI/UX workflow
1. Build a screen.
2. Run `fintech-uiux-reviewer` against it → produces a structured findings report (see `skills/fintech-mobile-uiux/checklists/review-template.md`).
3. Run `fintech-uiux-implementer` against the same screen + the report → applies targeted patches and verifies with `flutter analyze`.
4. Re-run reviewer to confirm.

The reviewer is read-only. The implementer edits code but never redesigns. Both consult `skills/fintech-mobile-uiux/SKILL.md` and its bundled checklists.
