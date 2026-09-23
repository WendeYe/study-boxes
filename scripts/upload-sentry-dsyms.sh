#!/bin/zsh
set -euo pipefail

: "${SENTRY_AUTH_TOKEN:?Missing SENTRY_AUTH_TOKEN. Store it in your shell or CI secrets, not in source.}"
: "${SENTRY_ORG:=study-box}"
: "${SENTRY_PROJECT:=study-macos}"

if ! command -v sentry-cli >/dev/null 2>&1; then
  echo "sentry-cli is required. Install it with: brew install getsentry/tools/sentry-cli" >&2
  exit 1
fi

ARCHIVE_PATH="${ARCHIVE_PATH:-}"
DSYM_PATH="${DSYM_PATH:-}"

if [[ -z "$DSYM_PATH" ]]; then
  if [[ -z "$ARCHIVE_PATH" ]]; then
    echo "Set ARCHIVE_PATH to a .xcarchive, or DSYM_PATH to a dSYM folder/dSYMs directory." >&2
    exit 1
  fi

  DSYM_PATH="$ARCHIVE_PATH/dSYMs"
fi

if [[ ! -d "$DSYM_PATH" ]]; then
  echo "dSYM path does not exist: $DSYM_PATH" >&2
  exit 1
fi

sentry-cli debug-files upload \
  --org "$SENTRY_ORG" \
  --project "$SENTRY_PROJECT" \
  --wait \
  "$DSYM_PATH"
