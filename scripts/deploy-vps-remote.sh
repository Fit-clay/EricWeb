#!/usr/bin/env bash

set -Eeuo pipefail

STAGE_DIR="${1:?缺少临时目录}"
BASE_DIR="${2:?缺少部署目录}"
APP_USER="${3:?缺少服务用户}"
APP_GROUP="${4:?缺少服务用户组}"
SERVICE_NAME="${5:?缺少 systemd 服务名}"
HEALTHCHECK_URL="${6:?缺少健康检查地址}"
DATA_DIR="${7:?缺少数据目录}"
ENV_FILE="${8:?缺少生产环境文件}"
RELEASE_ID="${9:?缺少版本号}"

RELEASES_DIR="$BASE_DIR/releases"
RELEASE_DIR="$RELEASES_DIR/$RELEASE_ID"
CURRENT_LINK="$BASE_DIR/current"
TEMPORARY_SECRET_FILE=""
PROFILE_BACKUP=""

cleanup_temporary_secret_file() {
  if [[ -n "$TEMPORARY_SECRET_FILE" ]]; then
    rm -f "$TEMPORARY_SECRET_FILE"
  fi
  [[ -z "$PROFILE_BACKUP" ]] || rm -f "$PROFILE_BACKUP"
  [[ ! -L "$BASE_DIR/.current-$RELEASE_ID" ]] || "${PRIVILEGED[@]}" rm -f "$BASE_DIR/.current-$RELEASE_ID"
}

trap cleanup_temporary_secret_file EXIT

if ((EUID == 0)); then
  PRIVILEGED=()
else
  if ! command -v sudo >/dev/null 2>&1; then
    echo "当前 SSH 用户不是 root，服务器也未安装 sudo。"
    exit 1
  fi
  PRIVILEGED=(sudo)
fi

for command_name in curl systemctl getent grep install mktemp python3; do
  if ! command -v "$command_name" >/dev/null 2>&1; then
    echo "服务器缺少命令：$command_name"
    exit 1
  fi
done

NODE_BIN="$STAGE_DIR/runtime/node"
# Reject source-only and wrong-platform packages before changing the running service.
python3 - "$STAGE_DIR" <<'PY'
import json, pathlib, platform, sys
root = pathlib.Path(sys.argv[1])
manifest = json.loads((root / 'manifest.json').read_text())
arch = {'x86_64': 'x64', 'aarch64': 'arm64'}.get(platform.machine())
if manifest.get('format') != 1 or manifest.get('platform') != 'linux' or manifest.get('arch') != arch or manifest.get('tested') is not True:
    raise SystemExit('Release platform/architecture or local test manifest is invalid.')
for item in ['runtime/node', '.next/standalone/server.js', 'scripts/publish-html-remote.py']:
    if not (root / item).is_file():
        raise SystemExit('Missing runtime artifact: ' + item)
PY
chmod u+x "$NODE_BIN"
"$NODE_BIN" --version || { echo "预构建运行时无法启动；请检查服务器 glibc/系统兼容性。"; exit 1; }
(
  cd "$STAGE_DIR/.next/standalone"
  "$NODE_BIN" --max-old-space-size=192 --max-semi-space-size=4 -e \
    'const D=require("better-sqlite3"); const d=new D(":memory:"); d.prepare("select 1").get(); d.close()'
)
APP_PORT="${HEALTHCHECK_URL#http://127.0.0.1:}"
APP_PORT="${APP_PORT%%/*}"

echo "检查服务器首次初始化状态……"

if ! getent group "$APP_GROUP" >/dev/null 2>&1; then
  if ! command -v groupadd >/dev/null 2>&1; then
    echo "服务器缺少 groupadd，无法创建服务用户组。"
    exit 1
  fi
  "${PRIVILEGED[@]}" groupadd --system "$APP_GROUP"
  echo "已创建服务用户组：$APP_GROUP"
fi

if ! id "$APP_USER" >/dev/null 2>&1; then
  if ! command -v useradd >/dev/null 2>&1; then
    echo "服务器缺少 useradd，无法创建服务用户。"
    exit 1
  fi
  NOLOGIN_SHELL="$(command -v nologin || true)"
  NOLOGIN_SHELL="${NOLOGIN_SHELL:-/usr/sbin/nologin}"
  "${PRIVILEGED[@]}" useradd \
    --system \
    --gid "$APP_GROUP" \
    --home-dir "$BASE_DIR" \
    --shell "$NOLOGIN_SHELL" \
    "$APP_USER"
  echo "已创建服务用户：$APP_USER"
fi

"${PRIVILEGED[@]}" mkdir -p \
  "$BASE_DIR" "$RELEASES_DIR" "$DATA_DIR/html"
"${PRIVILEGED[@]}" chown "$APP_USER:$APP_GROUP" \
  "$BASE_DIR" "$RELEASES_DIR" "$DATA_DIR" "$DATA_DIR/html"

if ! "${PRIVILEGED[@]}" test -e "$ENV_FILE"; then
  echo "首次部署：创建生产环境文件 $ENV_FILE"

  while true; do
    if ! read -r -p "管理员用户名 [Eric]: " ADMIN_USER_VALUE; then
      echo
      echo "无法读取管理员用户名，请在交互式终端中重新运行部署。"
      exit 1
    fi
    ADMIN_USER_VALUE="${ADMIN_USER_VALUE:-Eric}"
    if [[ "$ADMIN_USER_VALUE" =~ ^[A-Za-z0-9_.@-]{1,64}$ ]]; then
      break
    fi
    echo "管理员用户名只能包含字母、数字、点、下划线、@ 和连字符。"
  done

  while true; do
    if ! read -r -s -p "管理员密码（至少 12 位）: " ADMIN_PASSWORD_VALUE; then
      echo
      echo "无法读取管理员密码，请在交互式终端中重新运行部署。"
      exit 1
    fi
    echo
    if [[ ! "$ADMIN_PASSWORD_VALUE" =~ ^[A-Za-z0-9_.@%+=:,/-]{12,128}$ ]]; then
      echo "密码需为 12～128 位，且只能包含字母、数字和 ._@%+=:,/-。"
      continue
    fi
    if ! read -r -s -p "再次输入管理员密码: " ADMIN_PASSWORD_CONFIRM; then
      echo
      echo "无法读取确认密码，请重新运行部署。"
      exit 1
    fi
    echo
    if [[ "$ADMIN_PASSWORD_VALUE" == "$ADMIN_PASSWORD_CONFIRM" ]]; then
      break
    fi
    echo "两次输入的密码不一致，请重试。"
  done

  ADMIN_SESSION_SECRET="$("$NODE_BIN" -e \
    "process.stdout.write(require('node:crypto').randomBytes(32).toString('hex'))")"
  TEMPORARY_SECRET_FILE="$(mktemp)"
  chmod 600 "$TEMPORARY_SECRET_FILE"
  printf '%s\n' \
    'HOSTNAME=127.0.0.1' \
    "PORT=$APP_PORT" \
    "DATABASE_PATH=$DATA_DIR/pixiu.sqlite" \
    "HTML_PAGES_PATH=$DATA_DIR/html" \
    "ADMIN_USER=$ADMIN_USER_VALUE" \
    "ADMIN_PASSWORD=$ADMIN_PASSWORD_VALUE" \
    "ADMIN_SESSION_SECRET=$ADMIN_SESSION_SECRET" \
    >"$TEMPORARY_SECRET_FILE"

  "${PRIVILEGED[@]}" mkdir -p "$(dirname "$ENV_FILE")"
  "${PRIVILEGED[@]}" install \
    -o root -g "$APP_GROUP" -m 640 \
    "$TEMPORARY_SECRET_FILE" "$ENV_FILE"
  rm -f "$TEMPORARY_SECRET_FILE"
  TEMPORARY_SECRET_FILE=""
  unset ADMIN_PASSWORD_VALUE ADMIN_PASSWORD_CONFIRM ADMIN_SESSION_SECRET
  echo "已创建生产环境文件。"
else
  if ! "${PRIVILEGED[@]}" test -r "$ENV_FILE"; then
    echo "生产环境文件存在但不可读：$ENV_FILE"
    exit 1
  fi
  for variable_name in \
    HOSTNAME PORT DATABASE_PATH HTML_PAGES_PATH \
    ADMIN_USER ADMIN_PASSWORD ADMIN_SESSION_SECRET; do
    if ! "${PRIVILEGED[@]}" grep -q "^${variable_name}=." "$ENV_FILE"; then
      echo "生产环境文件缺少配置：$variable_name"
      echo "为保护已有配置，部署脚本不会自动覆盖 ${ENV_FILE}。"
      exit 1
    fi
  done
  "${PRIVILEGED[@]}" chown "root:$APP_GROUP" "$ENV_FILE"
  "${PRIVILEGED[@]}" chmod 640 "$ENV_FILE"
fi

if ! "${PRIVILEGED[@]}" systemctl cat "$SERVICE_NAME" >/dev/null 2>&1; then
  SERVICE_UNIT_NAME="$SERVICE_NAME"
  if [[ "$SERVICE_UNIT_NAME" != *.service ]]; then
    SERVICE_UNIT_NAME="$SERVICE_UNIT_NAME.service"
  fi
  SERVICE_UNIT_FILE="/etc/systemd/system/$SERVICE_UNIT_NAME"
  TEMPORARY_SECRET_FILE="$(mktemp)"
  chmod 600 "$TEMPORARY_SECRET_FILE"
  printf '%s\n' \
    '[Unit]' \
    'Description=Pixiu Library Next.js service' \
    'After=network.target' \
    '' \
    '[Service]' \
    'Type=simple' \
    "User=$APP_USER" \
    "Group=$APP_GROUP" \
    "WorkingDirectory=$CURRENT_LINK" \
    'Environment=NODE_ENV=production' \
    "EnvironmentFile=$ENV_FILE" \
    "ExecStart=$CURRENT_LINK/runtime/node --max-old-space-size=192 --max-semi-space-size=4 $CURRENT_LINK/.next/standalone/server.js" \
    'Restart=always' \
    'RestartSec=5' \
    'TimeoutStopSec=20' \
    'KillSignal=SIGTERM' \
    'UMask=0077' \
    'NoNewPrivileges=true' \
    'PrivateTmp=true' \
    'ProtectSystem=full' \
    "ReadWritePaths=$DATA_DIR" \
    '' \
    '[Install]' \
    'WantedBy=multi-user.target' \
    >"$TEMPORARY_SECRET_FILE"
  "${PRIVILEGED[@]}" install \
    -o root -g root -m 644 \
    "$TEMPORARY_SECRET_FILE" "$SERVICE_UNIT_FILE"
  rm -f "$TEMPORARY_SECRET_FILE"
  TEMPORARY_SECRET_FILE=""
  "${PRIVILEGED[@]}" systemctl daemon-reload
  echo "已安装 systemd 服务：$SERVICE_UNIT_NAME"
fi

"${PRIVILEGED[@]}" systemctl enable "$SERVICE_NAME" >/dev/null

if "${PRIVILEGED[@]}" test -e "$RELEASE_DIR"; then
  echo "版本目录已存在：$RELEASE_DIR"
  exit 1
fi

"${PRIVILEGED[@]}" mv "$STAGE_DIR" "$RELEASE_DIR"
"${PRIVILEGED[@]}" chown -R "$APP_USER:$APP_GROUP" "$RELEASE_DIR"

echo "预构建产物已就绪，服务器不执行依赖安装或编译。"

# Update existing installations as well as new ones; preserve the previous profile for rollback.
PROFILE_DIR="/etc/systemd/system/${SERVICE_NAME%.service}.service.d"
PROFILE_FILE="$PROFILE_DIR/50-pixiu-runtime.conf"
PROFILE_EXISTED=0
PROFILE_BACKUP="$(mktemp)"
if "${PRIVILEGED[@]}" test -f "$PROFILE_FILE"; then
  PROFILE_EXISTED=1
  "${PRIVILEGED[@]}" cat "$PROFILE_FILE" >"$PROFILE_BACKUP"
fi
PREVIOUS_RELEASE=""
if "${PRIVILEGED[@]}" test -L "$CURRENT_LINK"; then
  PREVIOUS_RELEASE="$("${PRIVILEGED[@]}" readlink -f "$CURRENT_LINK" || true)"
elif "${PRIVILEGED[@]}" test -e "$CURRENT_LINK"; then
  PREVIOUS_RELEASE="$RELEASES_DIR/legacy-$RELEASE_ID"
  "${PRIVILEGED[@]}" mv "$CURRENT_LINK" "$PREVIOUS_RELEASE"
fi

switch_current() {
  "${PRIVILEGED[@]}" ln -sfnT "$1" "$BASE_DIR/.current-$RELEASE_ID"
  "${PRIVILEGED[@]}" mv -Tf "$BASE_DIR/.current-$RELEASE_ID" "$CURRENT_LINK"
}

rollback() {
  ROLLBACK_ARMED=0
  trap - ERR
  echo "新版本检查失败，正在恢复旧版本……"
  if ((PROFILE_EXISTED)); then
    "${PRIVILEGED[@]}" install -m 644 "$PROFILE_BACKUP" "$PROFILE_FILE"
  else
    "${PRIVILEGED[@]}" rm -f "$PROFILE_FILE"
  fi
  "${PRIVILEGED[@]}" systemctl daemon-reload
  if [[ -n "$PREVIOUS_RELEASE" ]] && "${PRIVILEGED[@]}" test -d "$PREVIOUS_RELEASE"; then
    switch_current "$PREVIOUS_RELEASE"
    "${PRIVILEGED[@]}" systemctl restart "$SERVICE_NAME"
  else
    "${PRIVILEGED[@]}" rm -f "$CURRENT_LINK"
    "${PRIVILEGED[@]}" systemctl stop "$SERVICE_NAME" || true
  fi
}

ROLLBACK_ARMED=1
trap 'result=$?; trap - ERR; if ((ROLLBACK_ARMED)); then rollback || true; fi; exit "$result"' ERR

TEMPORARY_SECRET_FILE="$(mktemp)"
printf '%s\n' '[Service]' 'ExecStart=' \
  "ExecStart=$CURRENT_LINK/runtime/node --max-old-space-size=192 --max-semi-space-size=4 $CURRENT_LINK/.next/standalone/server.js" \
  'MemoryAccounting=true' 'MemoryHigh=256M' 'MemoryMax=320M' \
  >"$TEMPORARY_SECRET_FILE"
"${PRIVILEGED[@]}" install -d "$PROFILE_DIR"
"${PRIVILEGED[@]}" install -m 644 "$TEMPORARY_SECRET_FILE" "$PROFILE_FILE"
"${PRIVILEGED[@]}" systemctl daemon-reload
rm -f "$TEMPORARY_SECRET_FILE"
TEMPORARY_SECRET_FILE=""

switch_current "$RELEASE_DIR"
if ! "${PRIVILEGED[@]}" systemctl restart "$SERVICE_NAME"; then
  rollback
  exit 1
fi

for attempt in $(seq 1 30); do
  if curl --noproxy '*' --fail --silent --output /dev/null "$HEALTHCHECK_URL"; then
    if ! "${PRIVILEGED[@]}" python3 "$RELEASE_DIR/scripts/publish-html-remote.py" \
      "$RELEASE_DIR/html-pages" "$DATA_DIR" "$APP_USER" "$APP_GROUP"; then
      rollback
      exit 1
    fi
    echo "服务健康检查通过。"
    ROLLBACK_ARMED=0
    trap - ERR
    exit 0
  fi
  sleep 1
done

curl --noproxy '*' --fail --show-error --output /dev/null "$HEALTHCHECK_URL" || true
rollback
echo "服务在 30 秒内未通过健康检查。"
exit 1
