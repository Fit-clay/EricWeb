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

if ((EUID == 0)); then
  PRIVILEGED=()
else
  if ! command -v sudo >/dev/null 2>&1; then
    echo "当前 SSH 用户不是 root，服务器也未安装 sudo。"
    exit 1
  fi
  PRIVILEGED=(sudo)
fi

for command_name in node npm curl systemctl; do
  if ! command -v "$command_name" >/dev/null 2>&1; then
    echo "服务器缺少命令：$command_name"
    exit 1
  fi
done

if ! id "$APP_USER" >/dev/null 2>&1; then
  echo "服务器用户 $APP_USER 不存在，请先按 VPS_DEPLOY.md 完成首次初始化。"
  exit 1
fi

if [[ "$(id -un)" == "$APP_USER" ]]; then
  RUN_AS_APP=()
elif ((EUID == 0)); then
  if ! command -v runuser >/dev/null 2>&1; then
    echo "服务器缺少 runuser，无法以 $APP_USER 身份构建。"
    exit 1
  fi
  RUN_AS_APP=(runuser -u "$APP_USER" --)
else
  RUN_AS_APP=(sudo -u "$APP_USER")
fi

if ! "${PRIVILEGED[@]}" test -r "$ENV_FILE"; then
  echo "缺少生产环境文件 $ENV_FILE，请先按 VPS_DEPLOY.md 创建。"
  exit 1
fi

if ! "${PRIVILEGED[@]}" systemctl cat "$SERVICE_NAME" >/dev/null 2>&1; then
  echo "systemd 服务 $SERVICE_NAME 尚未安装，请先按 VPS_DEPLOY.md 完成首次初始化。"
  exit 1
fi

"${PRIVILEGED[@]}" mkdir -p "$RELEASES_DIR" "$DATA_DIR/html" "$DATA_DIR/.npm"
"${PRIVILEGED[@]}" chown "$APP_USER:$APP_GROUP" \
  "$BASE_DIR" "$RELEASES_DIR" "$DATA_DIR" "$DATA_DIR/html" "$DATA_DIR/.npm"

if "${PRIVILEGED[@]}" test -e "$RELEASE_DIR"; then
  echo "版本目录已存在：$RELEASE_DIR"
  exit 1
fi

"${PRIVILEGED[@]}" mv "$STAGE_DIR" "$RELEASE_DIR"
"${PRIVILEGED[@]}" chown -R "$APP_USER:$APP_GROUP" "$RELEASE_DIR"

echo "安装依赖并运行生产测试……"
NODE_BIN="$(command -v node)"
NPM_BIN="$(command -v npm)"
RUNTIME_PATH="$(dirname "$NODE_BIN"):/usr/local/bin:/usr/bin:/bin"

"${RUN_AS_APP[@]}" env HOME="$DATA_DIR" PATH="$RUNTIME_PATH" \
  "$NPM_BIN" --prefix "$RELEASE_DIR" ci
"${RUN_AS_APP[@]}" env HOME="$DATA_DIR" PATH="$RUNTIME_PATH" \
  "$NPM_BIN" --prefix "$RELEASE_DIR" test

PREVIOUS_RELEASE=""
if "${PRIVILEGED[@]}" test -L "$CURRENT_LINK"; then
  PREVIOUS_RELEASE="$("${PRIVILEGED[@]}" readlink -f "$CURRENT_LINK" || true)"
elif "${PRIVILEGED[@]}" test -e "$CURRENT_LINK"; then
  PREVIOUS_RELEASE="$RELEASES_DIR/legacy-$RELEASE_ID"
  "${PRIVILEGED[@]}" mv "$CURRENT_LINK" "$PREVIOUS_RELEASE"
fi

rollback() {
  echo "新版本检查失败，正在恢复旧版本……"
  if [[ -n "$PREVIOUS_RELEASE" ]] && "${PRIVILEGED[@]}" test -d "$PREVIOUS_RELEASE"; then
    "${PRIVILEGED[@]}" ln -sfnT "$PREVIOUS_RELEASE" "$CURRENT_LINK"
    "${PRIVILEGED[@]}" systemctl restart "$SERVICE_NAME"
  else
    "${PRIVILEGED[@]}" rm -f "$CURRENT_LINK"
    "${PRIVILEGED[@]}" systemctl stop "$SERVICE_NAME" || true
  fi
}

"${PRIVILEGED[@]}" ln -sfnT "$RELEASE_DIR" "$CURRENT_LINK"
if ! "${PRIVILEGED[@]}" systemctl restart "$SERVICE_NAME"; then
  rollback
  exit 1
fi

for attempt in $(seq 1 30); do
  if curl --noproxy '*' --fail --silent --show-error --output /dev/null "$HEALTHCHECK_URL"; then
    echo "服务健康检查通过。"
    exit 0
  fi
  sleep 1
done

rollback
echo "服务在 30 秒内未通过健康检查。"
exit 1
