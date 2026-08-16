#!/usr/bin/env bash
# PR gate — checks that a PR is open and not merged.
set -euo pipefail

BRANCH="${SPEC_ID:-}"
if [ -z "$BRANCH" ]; then
  echo "pr-open: no SPEC_ID set"
  exit 1
fi

# Check for an open PR from this branch
PR_URL=$(gh pr list --head "lg/$BRANCH" --json url -q '.[0].url' 2>/dev/null || true)

if [ -z "$PR_URL" ]; then
  echo "pr-open: no open PR found for lg/$BRANCH"
  exit 1
fi

# Check it's not merged
MERGED=$(gh pr list --head "lg/$BRANCH" --json state -q '.[0].state' 2>/dev/null || echo "")
if [ "$MERGED" = "MERGED" ]; then
  echo "pr-open: PR was merged (the harness should never merge)"
  exit 1
fi

echo "pr-open: $PR_URL"
exit 0