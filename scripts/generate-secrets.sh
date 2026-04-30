#!/usr/bin/env bash
# Reads .env and writes Sources/Generated/Secrets.swift.
# Runs both standalone and as an Xcode pre-build phase (uses $SRCROOT when available).

set -euo pipefail

if [ -n "${SRCROOT:-}" ]; then
    PROJECT_ROOT="${SRCROOT}"
else
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
fi

ENV_FILE="${PROJECT_ROOT}/.env"
OUT_DIR="${PROJECT_ROOT}/Sources/Generated"
OUT_FILE="${OUT_DIR}/Secrets.swift"

mkdir -p "${OUT_DIR}"

CALLY_GOOGLE_CLIENT_ID=""

if [ -f "${ENV_FILE}" ]; then
    while IFS='=' read -r key value || [ -n "${key}" ]; do
        case "${key}" in
            ''|\#*) continue ;;
        esac
        key="$(printf '%s' "${key}" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
        value="$(printf '%s' "${value}" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
        value="${value%\"}"; value="${value#\"}"
        value="${value%\'}"; value="${value#\'}"
        case "${key}" in
            CALLY_GOOGLE_CLIENT_ID) CALLY_GOOGLE_CLIENT_ID="${value}" ;;
        esac
    done < "${ENV_FILE}"
fi

NEW_CONTENT="// Auto-generated from .env by scripts/generate-secrets.sh — do not edit.
enum Secrets {
    static let googleClientID = \"${CALLY_GOOGLE_CLIENT_ID}\"
}
"

# Only rewrite if changed, so Xcode doesn't rebuild unnecessarily.
if [ ! -f "${OUT_FILE}" ] || [ "$(cat "${OUT_FILE}")" != "${NEW_CONTENT}" ]; then
    printf '%s' "${NEW_CONTENT}" > "${OUT_FILE}"
fi

echo "✓ ${OUT_FILE}"
