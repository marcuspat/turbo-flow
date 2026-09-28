# Spec: <short-name>

- **Date:** YYYY-MM-DD
- **Status:** draft | approved | shipped
- **Repo / path:** <where the work lands>
- **Builder:** <the CLI that wrote it (claude, codex, …) | human>
- **Reviewer:** must be a different model family than the builder (Law 1)

## Why
One paragraph. What breaks or blocks without this.

## Delta — what changes (and only what changes)
- **BEHAVIOR:** today X happens → after this, Y happens.
- **DATA:** schema/state changes, migrations.
- **INTERFACE:** API/CLI/UI surface changes.
- **NON-goals:** explicitly out of scope (guards against scope creep by agents).

## Tasks
- [ ] ...

## Verification
How we prove it works — exact commands and expected output. Written BEFORE implementation.
This section is what "verified" means; `gate.sh` gates the diff that claims it.
If the change is deployable, also copy `uat.md` (same dir) into the PR — behavior gets
verified against the preview URL after deploy.

## Open questions
`[NEEDS CLARIFICATION]` markers resolve before implementation starts.
