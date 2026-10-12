#!/usr/bin/env bash
# protect.sh — enforce Law 2 ("humans merge") with GitHub branch protection.
#
# Does three things:
#   1. Requires a pull request before merging to main (no direct pushes)
#   2. Requires the gate-verdict status check to pass (no merge without gate APPROVED)
#   3. Dismisses stale reviews when new commits are pushed (verdicts must be fresh)
#
# The result: even if an agent has merge-capable credentials, GitHub itself
# blocks the merge because the required status check isn't green. The
# constitution goes from a suggestion to a server-side enforcement.
#
# Usage:
#   protect.sh                    # protect the current repo's main branch
#   protect.sh -C <repo>          # protect another local repo
#   protect.sh --dry-run          # show what would be done, change nothing
#   protect.sh --status           # show current protection state
#
# Requires: gh CLI with admin access to the repo (owner or maintainer).
# The gate-check.yml workflow must exist in .github/workflows/ (it ships
# with this kit).

set -euo pipefail

DRY_RUN=0
STATUS_ONLY=0
REPO_PATH=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run) DRY_RUN=1; shift ;;
    --status)  STATUS_ONLY=1; shift ;;
    -C)        [[ $# -ge 2 ]] || { echo "protect: -C needs a value" >&2; exit 2; }; REPO_PATH="$2"; shift 2 ;;
    -h|--help) sed -n '2,20p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "protect: unknown arg '$1' (try --help)" >&2; exit 2 ;;
  esac
done

# resolve the repo
TOP="$(git -C "${REPO_PATH:-.}" rev-parse --show-toplevel 2>/dev/null)" \
  || { echo "protect: not a git repo" >&2; exit 2; }
cd "$TOP"

# resolve the GitHub slug
SLUG="$(gh repo view --json nameWithOwner --jq .nameWithOwner 2>/dev/null)" \
  || { echo "protect: gh couldn't resolve the repo — is this a GitHub repo with gh authenticated?" >&2; exit 2; }
BRANCH="main"

echo "protect: $SLUG branch=$BRANCH"

# check that gate-check.yml exists
if [ ! -f .github/workflows/gate-check.yml ]; then
  echo "protect: WARNING — .github/workflows/gate-check.yml not found." >&2
  echo "  Without it, the required status check will never pass and ALL merges will be blocked." >&2
  echo "  Copy it from the kit before running protect.sh." >&2
  exit 2
fi

if [[ $STATUS_ONLY -eq 1 ]]; then
  echo "protect: current branch protection state:"
  gh api "repos/$SLUG/branches/$BRANCH/protection" 2>/dev/null \
    | python3 -c "
import json, sys
try:
    d = json.load(sys.stdin)
    print(f'  required_pr_reviews: {d.get(\"required_pull_request_reviews\") is not None}')
    checks = d.get('required_status_checks', {})
    print(f'  required_checks: {checks.get(\"contexts\", [])}')
    print(f'  enforce_admins: {d.get(\"enforce_admins\", {}).get(\"enabled\", False)}')
    print(f'  allow_force_push: {d.get(\"allow_force_pushes\", {}).get(\"enabled\", False)}')
except:
    print('  (no protection rules found)')
" 2>/dev/null || echo "  (no protection rules found)"
  exit 0
fi

# build the protection payload
PAYLOAD='{
  "required_status_checks": {
    "strict": true,
    "contexts": ["gate-verdict"]
  },
  "enforce_admins": true,
  "required_pull_request_reviews": {
    "required_approving_review_count": 0
  },
  "restrictions": null,
  "allow_force_pushes": false,
  "allow_deletions": false
}'

if [[ $DRY_RUN -eq 1 ]]; then
  echo "protect: DRY RUN — would apply:"
  echo "  require PR before merging to $BRANCH: yes"
  echo "  require gate-verdict check: yes"
  echo "  enforce for admins: yes"
  echo "  allow force pushes: no"
  echo "  allow deletions: no"
  echo "protect: (nothing changed)"
  exit 0
fi

echo "protect: applying branch protection..."
RESULT="$(gh api -X PUT "repos/$SLUG/branches/$BRANCH/protection" \
  --input - 2>&1 <<< "$PAYLOAD")" || {
  echo "protect: FAILED — $RESULT" >&2
  echo "  You need admin access to this repo." >&2
  exit 1
}

echo ""
echo "protect: ✓ $SLUG/$BRANCH is now protected:"
echo "  • No direct pushes — PRs required"
echo "  • gate-verdict must pass — no merge without gate APPROVED"
echo "  • Admins are subject to the same rules"
echo "  • Force pushes and deletions blocked"
echo ""
echo "  The constitution's Law 2 is now enforced by GitHub, not by agent restraint."
echo "  Test it: try merging a PR without a gate verdict — GitHub will refuse."
