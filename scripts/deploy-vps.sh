#!/usr/bin/env bash

set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
CONFIG_FILE="${1:-$PROJECT_ROOT/.deploy.env}"

if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
  cat <<'USAGE'
用法：
  cp .deploy.env.example .deploy.env
  编辑 .deploy.env
  ./scripts/deploy-vps.sh

也可以传入其他配置文件：
  ./scripts/deploy-vps.sh /path/to/deploy.env
USAGE
  exit 0
fi

if [[ ! -f "$CONFIG_FILE" ]]; then
  echo "缺少部署配置：$CONFIG_FILE"
  echo "请先执行：cp .deploy.env.example .deploy.env"
  exit 1
fi

set -a
# shellcheck disable=SC1090
source "$CONFIG_FILE"
set +a

: "${VPS_HOST:?请在部署配置中填写 VPS_HOST}"
: "${VPS_SSH_USER:?请在部署配置中填写 VPS_SSH_USER}"

VPS_SSH_PORT="${VPS_SSH_PORT:-22}"
VPS_BASE_DIR="${VPS_BASE_DIR:-/opt/pixiu-library}"
VPS_APP_USER="${VPS_APP_USER:-pixiu}"
VPS_APP_GROUP="${VPS_APP_GROUP:-pixiu}"
VPS_SERVICE_NAME="${VPS_SERVICE_NAME:-pixiu-library}"
VPS_DATA_DIR="${VPS_DATA_DIR:-/var/lib/pixiu-library}"
VPS_ENV_FILE="${VPS_ENV_FILE:-/etc/pixiu-library.env}"
VPS_HEALTHCHECK_URL="${VPS_HEALTHCHECK_URL:-http://127.0.0.1:3000/}"

validate() {
  local name="$1"
  local value="$2"
  local pattern="$3"
  if [[ ! "$value" =~ $pattern ]]; then
    echo "部署配置 $name 格式不正确：$value"
    exit 1
  fi
}

validate_safe_directory() {
  local name="$1"
  local value="$2"

  if [[ "$value" == "/" || "$value" == */ || "$value" == *"//"* || \
    "$value" == *"/../"* || "$value" == */.. || "$value" == *"/./"* || \
    "$value" == */. ]]; then
    echo "部署配置 $name 不能使用根目录、尾随斜杠或相对路径段：$value"
    exit 1
  fi

  case "$value" in
    /bin|/boot|/dev|/etc|/home|/lib|/lib64|/opt|/proc|/root|/run|/sbin|/srv|/sys|/tmp|/usr|/var)
      echo "部署配置 $name 指向的目录范围过大：$value"
      exit 1
      ;;
  esac
}

validate "VPS_HOST" "$VPS_HOST" '^[A-Za-z0-9._-]+$'
validate "VPS_SSH_USER" "$VPS_SSH_USER" '^[A-Za-z_][A-Za-z0-9_-]*$'
validate "VPS_SSH_PORT" "$VPS_SSH_PORT" '^[0-9]{1,5}$'
validate "VPS_BASE_DIR" "$VPS_BASE_DIR" '^/[A-Za-z0-9._/-]+$'
validate "VPS_APP_USER" "$VPS_APP_USER" '^[A-Za-z_][A-Za-z0-9_-]*$'
validate "VPS_APP_GROUP" "$VPS_APP_GROUP" '^[A-Za-z_][A-Za-z0-9_-]*$'
validate "VPS_SERVICE_NAME" "$VPS_SERVICE_NAME" '^[A-Za-z0-9_.@-]+$'
validate "VPS_DATA_DIR" "$VPS_DATA_DIR" '^/[A-Za-z0-9._/-]+$'
validate "VPS_ENV_FILE" "$VPS_ENV_FILE" '^/[A-Za-z0-9._/-]+$'
validate "VPS_HEALTHCHECK_URL" "$VPS_HEALTHCHECK_URL" '^http://127\.0\.0\.1:[0-9]{1,5}/[A-Za-z0-9_./?=&%-]*$'
validate_safe_directory "VPS_BASE_DIR" "$VPS_BASE_DIR"
validate_safe_directory "VPS_DATA_DIR" "$VPS_DATA_DIR"

if ((10#$VPS_SSH_PORT < 1 || 10#$VPS_SSH_PORT > 65535)); then
  echo "部署配置 VPS_SSH_PORT 必须在 1 到 65535 之间。"
  exit 1
fi

HEALTHCHECK_PORT="${VPS_HEALTHCHECK_URL#http://127.0.0.1:}"
HEALTHCHECK_PORT="${HEALTHCHECK_PORT%%/*}"
if ((10#$HEALTHCHECK_PORT < 1 || 10#$HEALTHCHECK_PORT > 65535)); then
  echo "健康检查端口必须在 1 到 65535 之间。"
  exit 1
fi

for command_name in ssh rsync; do
  if ! command -v "$command_name" >/dev/null 2>&1; then
    echo "本机缺少命令：$command_name"
    exit 1
  fi
done

RELEASE_ID="$(date -u +%Y%m%d%H%M%S)"
REMOTE_STAGE=".pixiu-upload-$RELEASE_ID"
SSH_TARGET="$VPS_SSH_USER@$VPS_HOST"
SSH_OPTIONS=(-p "$VPS_SSH_PORT" -o ServerAliveInterval=15 -o ServerAliveCountMax=4)
RSYNC_SSH="ssh -p $VPS_SSH_PORT -o ServerAliveInterval=15 -o ServerAliveCountMax=4"

echo "[1/3] 创建服务器临时目录"
ssh "${SSH_OPTIONS[@]}" "$SSH_TARGET" \
  "test ! -e ~/$REMOTE_STAGE && mkdir -p ~/$REMOTE_STAGE"

echo "[2/3] 上传当前源码"
rsync -az --progress \
  -e "$RSYNC_SSH" \
  --exclude '.git/' \
  --exclude 'node_modules/' \
  --exclude '.next/' \
  --exclude 'dist/' \
  --exclude '.vinext/' \
  --exclude '.wrangler/' \
  --exclude '.deploy.env' \
  --include '.env.example' \
  --exclude '.env' \
  --exclude '.env.*' \
  --exclude 'yes' \
  --exclude 'yes.pub' \
  --exclude 'id_*' \
  --exclude '*.key' \
  --exclude '*.pem' \
  --exclude 'data/*.sqlite*' \
  --exclude '*.log' \
  "$PROJECT_ROOT/" "$SSH_TARGET:~/$REMOTE_STAGE/"

echo "[3/3] 构建、切换版本并检查服务"
ssh -tt "${SSH_OPTIONS[@]}" "$SSH_TARGET" \
  "bash ~/$REMOTE_STAGE/scripts/deploy-vps-remote.sh ~/$REMOTE_STAGE '$VPS_BASE_DIR' '$VPS_APP_USER' '$VPS_APP_GROUP' '$VPS_SERVICE_NAME' '$VPS_HEALTHCHECK_URL' '$VPS_DATA_DIR' '$VPS_ENV_FILE' '$RELEASE_ID'"

echo "部署完成：$VPS_HOST（版本 $RELEASE_ID）"
