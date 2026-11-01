#!/bin/sh
# Submits a signed .zip, .dmg or .pkg to Apple's notary service and waits for the verdict.
# Exits non-zero (after printing Apple's log) unless the submission is Accepted. Staple afterwards.
#
#   ./scripts/notarize.sh build/MacOptimized-1.2.3.dmg
#
# Credentials, either:
#   NOTARY_KEY_PATH, NOTARY_KEY_ID, NOTARY_ISSUER_ID   App Store Connect API key (.p8), as in CI
#   NOTARY_KEYCHAIN_PROFILE                            a profile saved with `xcrun notarytool store-credentials`
set -eu

FILE="${1:?usage: notarize.sh <file.zip|file.dmg|file.pkg>}"

if [ -n "${NOTARY_KEYCHAIN_PROFILE:-}" ]; then
  set -- --keychain-profile "$NOTARY_KEYCHAIN_PROFILE"
else
  set -- --key "${NOTARY_KEY_PATH:?set NOTARY_KEY_PATH or NOTARY_KEYCHAIN_PROFILE}" \
    --key-id "${NOTARY_KEY_ID:?set NOTARY_KEY_ID}" --issuer "${NOTARY_ISSUER_ID:?set NOTARY_ISSUER_ID}"
fi

echo "Submitting $FILE for notarization…"
RESULT=$(xcrun notarytool submit "$FILE" "$@" --wait --timeout 30m --output-format json) || true
echo "$RESULT"
ID=$(printf '%s' "$RESULT" | plutil -extract id raw -o - - 2>/dev/null || true)
STATUS=$(printf '%s' "$RESULT" | plutil -extract status raw -o - - 2>/dev/null || true)

if [ "$STATUS" != "Accepted" ]; then
  echo "::error::Notarization of $FILE finished with status '${STATUS:-unknown}'"
  [ -n "$ID" ] && xcrun notarytool log "$ID" "$@" || true
  exit 1
fi
echo "Notarized $FILE ($ID)"
