#!/usr/bin/env bash
# Runtime-only server entry point shared by Windows and Unix uploaders.
set -Eeuo pipefail
STAGE_ROOT="${1:?Missing upload directory}"
MODE="${2:?Missing mode}"
BASE_DIR="${3:?Missing base directory}"
APP_USER="${4:?Missing user}"
APP_GROUP="${5:?Missing group}"
SERVICE_NAME="${6:?Missing service}"
HEALTH_URL="${7:?Missing health URL}"
DATA_DIR="${8:?Missing data directory}"
ENV_FILE="${9:?Missing environment file}"
RELEASE_ID="${10:?Missing release ID}"
[[ "$MODE" == Full || "$MODE" == Html ]]
[[ "$SERVICE_NAME" =~ ^[A-Za-z0-9_][A-Za-z0-9_.@-]*$ ]]
if ((EUID != 0)); then exec sudo bash "$0" "$@"; fi
# Serialize full and HTML updates, including updates launched by another local window.
exec 9>"/run/lock/pixiu-${SERVICE_NAME%.service}-publish.lock"
flock -n 9 || { echo 'Another publish task is running on this server.'; exit 1; }
cd "$STAGE_ROOT"
if [[ "$MODE" == Full ]]; then ARCHIVE=release.tar.gz; else ARCHIVE=html-pages.zip; fi
trap 'rm -f -- "$STAGE_ROOT/$ARCHIVE" "$STAGE_ROOT/checksum.sha256" "$STAGE_ROOT/publish-html-remote.py" "$STAGE_ROOT/activate-upload-remote.sh"; rmdir "$STAGE_ROOT" 2>/dev/null || true' EXIT
sha256sum -c checksum.sha256
command -v python3 >/dev/null || { echo 'Install Python 3 before deploying.'; exit 1; }
if [[ "$MODE" == Full ]]; then
  mkdir payload
  tar --no-same-owner -xzf "$ARCHIVE" -C payload
  bash "$STAGE_ROOT/payload/scripts/deploy-vps-remote.sh" "$STAGE_ROOT/payload" "$BASE_DIR" "$APP_USER" "$APP_GROUP" "$SERVICE_NAME" "$HEALTH_URL" "$DATA_DIR" "$ENV_FILE" "$RELEASE_ID"
else
  python3 "$STAGE_ROOT/publish-html-remote.py" "$STAGE_ROOT/$ARCHIVE" "$DATA_DIR" "$APP_USER" "$APP_GROUP"
fi
