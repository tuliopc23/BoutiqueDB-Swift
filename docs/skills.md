# Agent skills

BoutiqueDB ships installable agent skills through [skills.sh](https://skills.sh/). Each skill packages the knowledge from these docs for agent-assisted workflows.

## Available skills

| Skill | Install | Use |
|-------|---------|-----|
| Getting started | `npx skills add tuliopc23/BoutiqueDB-Swift@boutiquedb-getting-started` | Install, quick start, open options |
| Architecture | `npx skills add tuliopc23/BoutiqueDB-Swift@boutiquedb-architecture` | Stack, modules, concurrency, LiveQuery |
| Sync | `npx skills add tuliopc23/BoutiqueDB-Swift@boutiquedb-sync` | CloudKit, SyncAdapter, sync protocol |
| Open options | `npx skills add tuliopc23/BoutiqueDB-Swift@boutiquedb-open-options` | Experimental features, async I/O, encryption |
| Contributing | `npx skills add tuliopc23/BoutiqueDB-Swift@boutiquedb-contributing` | Build engine, packaging, SPI checklist |

## Install with Pochi / Windsurf / Devin

```bash
npx skills add tuliopc23/BoutiqueDB-Swift@boutiquedb-getting-started --agent pochi -y --copy
```

Replace `pochi` with your agent name (`devin`, `windsurf`, `claude-code`, etc.) and `--copy` with `-g --copy` for a user-level install.

## Skill source

Skill files are in the [`skills/`](https://github.com/tuliopc23/BoutiqueDB-Swift/tree/main/skills) directory of the repository.
