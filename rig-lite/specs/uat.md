# UAT contract: <feature-name>

- **PR:** #<n>
- **Preview URL:** <railway/vercel preview or deployed URL>
- **Status:** `PENDING | PASS | FAIL`
- **Verified by:** <agent/human + date>

> Copy into the PR (body or comment). The verifier consumes this contract as structured
> input — no "go check the app" prompts. The diff gate and this UAT are separate stages:
> gate verifies the code, this verifies the behavior.

## Objective
One sentence: what this change must achieve for a real user of the running app.

## Acceptance criteria
- [ ] <criterion 1 — observable in the deployed app>
- [ ] <criterion 2>
- [ ] <criterion 3>

## Test cases
### 1. <short name>
- **Steps:** step → step → step
- **Expected:** <exactly what should happen>

### 2. <short name>
- **Steps:** …
- **Expected:** …

## Result
- **Status:** PENDING
- **Defects:** _(numbered; each with repro steps, expected vs actual, severity)_
- **Notes:** _(environment quirks, flaky behavior, anything the builder should know)_

## Integration pass (merging 2+ PRs in one session)
A PR preview carries only its own change — the **combined** state of several PRs
first exists on production *after* they merge. Before a multi-PR merge session:

1. Merge the first PR (human order, as always).
2. `gh pr update-branch <next-pr>` → the preview rebuilds **with everything
   already merged** plus this PR's change.
3. Re-run the UAT pass against that updated preview.
4. Only then merge the next PR (human order). Repeat per PR.

Skip the rebuild only when the PRs are provably disjoint (different files, no
shared layout surface) — and say so in the PR comment when you skip it.
The post-merge production pass is the backstop, never the plan.

**Ordering note:** merge dependency-first (the PR that fixes the shared surface
before the one that depends on it), and remember PR preview environments are
**removed on merge** — post-merge verification always runs against production.
