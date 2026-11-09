#!/usr/bin/env bash

set -Eeuo pipefail

SOURCE_DIR="${1:?缺少服务器临时页面目录}"
DATA_DIR="${2:?缺少持久化数据目录}"
APP_USER="${3:?缺少服务用户}"
APP_GROUP="${4:?缺少服务用户组}"
TARGET_DIR="$DATA_DIR/html/travel"

if [[ ! -d "$SOURCE_DIR" ]]; then
  echo "服务器临时页面目录不存在：$SOURCE_DIR" >&2
  exit 1
fi
if [[ "$DATA_DIR" != /* || "$DATA_DIR" == "/" || "$DATA_DIR" == */ || \
  "$DATA_DIR" == *"/../"* || "$DATA_DIR" == */.. ]]; then
  echo "持久化数据目录不安全：$DATA_DIR" >&2
  exit 1
fi
if [[ ! "$APP_USER" =~ ^[A-Za-z_][A-Za-z0-9_-]*$ || \
  ! "$APP_GROUP" =~ ^[A-Za-z_][A-Za-z0-9_-]*$ ]]; then
  echo "服务用户或用户组格式不正确。" >&2
  exit 1
fi
if ! command -v rsync >/dev/null 2>&1; then
  echo "服务器缺少命令：rsync" >&2
  exit 1
fi

if ((EUID == 0)); then
  PRIVILEGED=()
else
  if ! command -v sudo >/dev/null 2>&1; then
    echo "当前 SSH 用户不是 root，服务器也未安装 sudo。" >&2
    exit 1
  fi
  PRIVILEGED=(sudo)
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMP_PAGES="$(mktemp -d)"
trap 'rm -rf -- "$TEMP_PAGES"' EXIT
mkdir "$TEMP_PAGES/travel"
cp -a "$SOURCE_DIR/." "$TEMP_PAGES/travel/"
"${PRIVILEGED[@]}" python3 "$SCRIPT_DIR/publish-html-remote.py" "$TEMP_PAGES" "$DATA_DIR" "$APP_USER" "$APP_GROUP"

echo "已更新服务器页面目录：$TARGET_DIR"
