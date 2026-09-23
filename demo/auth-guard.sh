#!/usr/bin/env bash
# auth-guard.sh — aborts unless the claude CLI is present and reports
# loggedIn:false (parsed from its real JSON; empirically captured from an
# unauthenticated Codespace CLI). Sourced or run; exits 1 on any bad state.
set -u
if ! command -v claude >/dev/null 2>&1; then
  echo "auth-guard: claude CLI missing — the demo requires it" >&2; exit 1
fi
AUTH_JSON="$(claude auth status 2>/dev/null || true)"   # stdout only: stderr noise corrupts JSON parsing
LOGGED_IN="$(printf '%s' "$AUTH_JSON" | jq -r '.loggedIn|tostring' 2>/dev/null || true)"
case "$LOGGED_IN" in
  "false") echo "auth-guard: claude reports loggedIn:false — genuine first-run screen incoming" ;;
  "true")  echo "auth-guard: claude is AUTHENTICATED — record from a credential-free Codespace" >&2; exit 1 ;;
  *)       echo "auth-guard: auth state unparseable (got: '$LOGGED_IN') — jq or claude output changed" >&2; exit 1 ;;
esac
