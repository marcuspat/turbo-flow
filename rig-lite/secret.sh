#!/usr/bin/env bash
# rig-lite secrets — encrypted at rest on every platform, zero mandatory deps.
#
# Why not hashes: hashes are one-way. Secrets a kit must USE (API keys,
# tokens) must be recoverable, so they get ENCRYPTED storage. (Hashing is for
# verifying things at login, not storing usable credentials.)
#
# Backends, auto-detected in order (first available wins):
#   keychain  — macOS, built-in `security` CLI. Zero install.
#   libsecret — Linux desktops (GNOME Keyring/KWallet) via `secret-tool`.
#   age       — anywhere with the single static `age` binary (recommended on
#               headless servers/VPS: `apt install age` / `brew install age`).
#               Key file chmod 600; secrets stored per-name, encrypted.
#   file      — last resort, LOUDLY WARNED plaintext (chmod 600).
#
# Containers/CI: if the value already exists as an env var, scripts should
# just use it — `secret.sh` is for the persistent-plane case. In Codespaces,
# prefer GitHub Codespace Secrets (arrive as env vars; nothing stored).
#
# Names are identifiers — letters, digits, dot, underscore, dash only — they
# feed sed patterns and file paths, so anything fancier is refused outright.
#
# Usage:
#   secret.sh set NAME    # value via hidden prompt or stdin
#   secret.sh get NAME    # prints value
#   secret.sh rm NAME
#   secret.sh list        # names only, never values
#   secret.sh backend     # active backend
#
# Test/CI knobs (also let tests run hermetically, never touching a real
# keychain): RIG_LITE_SECRET_BACKEND forces a backend; RIG_LITE_SECRET_HOME
# relocates the whole config root (default ~/.config/rig-lite).
#
# Sourceable: `. secret.sh` exposes kit_secret_get / kit_secret_set.
set -uo pipefail
SVC="rig-lite"
CFG="${RIG_LITE_SECRET_HOME:-$HOME}/.config/rig-lite"
AGE_DIR="$CFG/secrets.d"
AGE_KEY="$CFG/secret.key"
AGE_PUB="$CFG/secret.pub"
FILE_STORE="$CFG/secrets.env"
# names-only index (not secret) — Apple's dump-keychain format isn't stably
# parseable, so keychain/libsecret `list` reads this instead. age/file list natively.
INDEX="$CFG/secret-names.txt"
NAME_RE='^[A-Za-z0-9][A-Za-z0-9_.-]*$'

valid_name() { [[ "$1" =~ $NAME_RE ]]; }

_backend() {
  if [[ -n "${RIG_LITE_SECRET_BACKEND:-}" ]]; then
    case "$RIG_LITE_SECRET_BACKEND" in keychain|libsecret|age|file) echo "$RIG_LITE_SECRET_BACKEND"; return 0;; esac
    echo "secret: unknown RIG_LITE_SECRET_BACKEND '$RIG_LITE_SECRET_BACKEND' (known: keychain, libsecret, age, file)" >&2
    return 1
  fi
  if [[ "$(uname)" == "Darwin" ]] && command -v security >/dev/null 2>&1; then echo "keychain"
  elif command -v secret-tool >/dev/null 2>&1 && \
       (command -v gnome-keyring-daemon >/dev/null 2>&1 || command -v kwalletd5 >/dev/null 2>&1 || \
        [[ -n "${DBUS_SESSION_BUS_ADDRESS:-}" ]]); then echo "libsecret"
  elif command -v age >/dev/null 2>&1 && command -v age-keygen >/dev/null 2>&1; then echo "age"
  else echo "file"; fi
}

_warn_file() {
  echo "WARNING: no encrypted secret store available — using a chmod-600 PLAINTEXT file at $FILE_STORE." >&2
  echo "  macOS: Keychain is built in ('security').  Linux desktop: install secret-tool (libsecret)." >&2
  echo "  Headless server: install age ('apt install age' — one static binary) for an encrypted store." >&2
  echo "  Codespaces/CI: use GitHub environment secrets (env vars) — nothing to store here." >&2
}

_age_ensure() {
  # both key AND pub must exist; a missing pub with an intact key is
  # regenerated, never short-circuited (a missing recipient would truncate
  # the store target to zero bytes via the output redirect)
  if [ ! -f "$AGE_KEY" ]; then
    mkdir -p "$CFG" "$AGE_DIR" && chmod 700 "$CFG" "$AGE_DIR" 2>/dev/null
    age-keygen -o "$AGE_KEY" 2>/dev/null && chmod 600 "$AGE_KEY" || return 1
  fi
  if [ ! -s "$AGE_PUB" ]; then
    age-keygen -y "$AGE_KEY" > "$AGE_PUB" 2>/dev/null
  fi
  [ -s "$AGE_PUB" ]
}

_index_add() { mkdir -p "$CFG" 2>/dev/null; touch "$INDEX"; chmod 600 "$INDEX"; grep -qxF "$1" "$INDEX" || printf '%s\n' "$1" >> "$INDEX"; }
_index_del() { [ -f "$INDEX" ] && sed -i.bak "\|^$1$|d" "$INDEX" && rm -f "$INDEX.bak"; return 0; }

# names feed sed addresses — validate at the FUNCTION boundary too, not just
# the CLI: the sourceable helpers bypass the dispatcher
_name_ok() { valid_name "$1" || { echo "secret: name must match $NAME_RE (got: '$1')" >&2; return 2; }; }
# the dot in a legal name is a regex wildcard in sed — escape it per use
_sed_name() { printf '%s' "$1" | sed 's/\./\\./g'; }

_set() { # NAME VALUE
  _name_ok "$1" || return 2
  local sn; sn="$(_sed_name "$1")"
  case "$(_backend)" in
    keychain)  security add-generic-password -U -s "$SVC" -a "$1" -w "$2" && _index_add "$1" ;;
    libsecret) printf '%s' "$2" | secret-tool store --label="rig-lite $1" service "$SVC" name "$1" && _index_add "$1" ;;
    age)       _age_ensure || { echo "age key setup failed" >&2; return 1; }
               printf '%s' "$2" | age -r "$(cat "$AGE_PUB")" > "$AGE_DIR/$1.age.tmp" \
                 && mv -f "$AGE_DIR/$1.age.tmp" "$AGE_DIR/$1.age" || { rm -f "$AGE_DIR/$1.age.tmp"; return 1; } ;;
    file)      _warn_file; mkdir -p "$CFG"; touch "$FILE_STORE"; chmod 600 "$FILE_STORE"
               sed -i.bak "\|^${sn}=|d" "$FILE_STORE" && rm -f "$FILE_STORE.bak" \
                 && printf '%s=%s\n' "$1" "$2" >> "$FILE_STORE" ;;
    *)         echo "secret: backend detection failed — nothing stored" >&2; return 1 ;;
  esac
}

_get() { # NAME
  _name_ok "$1" || return 2
  local sn; sn="$(_sed_name "$1")"
  case "$(_backend)" in
    keychain)  security find-generic-password -s "$SVC" -a "$1" -w 2>/dev/null ;;
    libsecret) secret-tool lookup service "$SVC" name "$1" 2>/dev/null ;;
    age)       [ -f "$AGE_DIR/$1.age" ] && age -d -i "$AGE_KEY" "$AGE_DIR/$1.age" 2>/dev/null ;;
    file)      sed -n "s|^${sn}=||p" "$FILE_STORE" 2>/dev/null | head -1 ;;
    *)         echo "secret: backend detection failed" >&2; return 1 ;;
  esac
}

_rm() { # NAME
  _name_ok "$1" || return 2
  local sn; sn="$(_sed_name "$1")"
  case "$(_backend)" in
    keychain)  security delete-generic-password -s "$SVC" -a "$1" >/dev/null 2>&1; _index_del "$1" ;;
    libsecret) secret-tool clear service "$SVC" name "$1" 2>/dev/null; _index_del "$1" ;;
    age)       rm -f "$AGE_DIR/$1.age" ;;
    file)      sed -i.bak "\|^${sn}=|d" "$FILE_STORE" 2>/dev/null && rm -f "$FILE_STORE.bak" ;;
    *)         echo "secret: backend detection failed" >&2; return 1 ;;
  esac
}

_list() {
  case "$(_backend)" in
    keychain|libsecret) [ -f "$INDEX" ] && cat "$INDEX" ;;
    age)       [ -d "$AGE_DIR" ] && ls "$AGE_DIR" 2>/dev/null | sed 's/\.age$//' ;;
    file)      [ -f "$FILE_STORE" ] && sed 's/=.*//' "$FILE_STORE" ;;
    *)         echo "secret: backend detection failed" >&2; return 1 ;;
  esac
}

# sourceable helpers
kit_secret_get() { _get "$1"; }
kit_secret_set() { _set "$1" "$2"; }

# CLI only when EXECUTED — sourcing must not run the dispatcher with the
# parent shell's $1 (that was a footgun in the rig original)
if [[ "${BASH_SOURCE[0]}" != "$0" ]]; then
  return 0 2>/dev/null || true
fi

case "${1:-help}" in
  set)
    NAME="${2:?usage: secret.sh set NAME}"
    valid_name "$NAME" || { echo "secret: name must match $NAME_RE (got: '$NAME')" >&2; exit 2; }
    if [ -t 0 ]; then
      printf 'value for %s: ' "$NAME" >&2; IFS= read -rs VALUE; echo >&2
    else
      VALUE="$(cat)"
    fi
    [ -n "$VALUE" ] || { echo "empty value, aborting" >&2; exit 1; }
    case "$VALUE" in *$'\n'*|*$'\r'*) echo "secret: multi-line values are not supported (would corrupt the file backend)" >&2; exit 2;; esac
    _set "$NAME" "$VALUE" && echo "stored: $NAME (backend: $(_backend))" >&2
    ;;
  get)
    [ -n "${2:-}" ] || { echo "usage: secret.sh get NAME" >&2; exit 1; }
    valid_name "$2" || { echo "secret: name must match $NAME_RE (got: '$2')" >&2; exit 2; }
    _get "$2" ;;
  rm)
    [ -n "${2:-}" ] || { echo "usage: secret.sh rm NAME" >&2; exit 1; }
    valid_name "$2" || { echo "secret: name must match $NAME_RE (got: '$2')" >&2; exit 2; }
    _rm "$2" && echo "removed: $2" >&2 ;;
  list) _list ;;
  backend) _backend || exit 2 ;;
  *)
    sed -n '2,35p' "$0"; exit 1 ;;
esac
