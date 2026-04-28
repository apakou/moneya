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
│   └── fintech-security/
└── agents/        # Specialized subagents (invoked via run_subagent)
    ├── flutter-feature-builder.md
    ├── payment-flow-reviewer.md
    ├── i18n-auditor.md
    └── voice-ux-designer.md
```

## How skills work
Each `skills/<name>/SKILL.md` begins with YAML frontmatter (`name`, `description`).
The `description` tells Claude **when** to load the skill. Keep triggers explicit.

## How subagents work
Each `agents/<name>.md` begins with YAML frontmatter (`name`, `description`, `tools`).
Invoke with `run_subagent(agentName="<name>", task="...")`.

## Project context (always-true facts)
- **Stack**: Flutter (Dart 3+), Riverpod 2, go_router, freezed, dio
- **Chain**: USDC on Solana (preferred) or Base — never Ethereum mainnet
- **Corridors**: XOF (UEMOA), XAF (CEMAC), NGN, GHS, KES
- **Mobile money partners**: Wave, Orange Money, MTN MoMo, Moov, Airtel
- **Onramp/offramp candidates**: Yellow Card, Fonbnk, Juicyway, Onafriq, Accrue
- **Locales**: `fr`, `en` (primary); plan for Wolof, Bambara, Lingala, Pidgin voice
- **Architecture**: feature-first under `lib/features/<feature>/{data,domain,presentation}`
- **UX principle**: stablecoin is invisible to end users; show local currency only
