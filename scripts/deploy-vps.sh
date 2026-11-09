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

首次部署会为 Ubuntu 自动安装缺少的 Node.js、npm、curl、rsync、
Python 和原生模块编译工具，并创建运行用户、持久化目录、环境文件
和 systemd 服务，最后提示输入管理员账号及密码。

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

for command_name in ssh scp rsync docker; do
  if ! command -v "$command_name" >/dev/null 2>&1; then
    echo "本机缺少命令：$command_name"
    exit 1
  fi
done

ARCHITECTURE="${DEPLOY_ARCH:-amd64}"
case "$ARCHITECTURE" in amd64|arm64) ;; *) echo "DEPLOY_ARCH must be amd64 or arm64"; exit 1 ;; esac
LOCAL_STAGE="$(mktemp -d)"
trap 'rm -rf -- "$LOCAL_STAGE"' EXIT
mkdir "$LOCAL_STAGE/source"
echo "[1/4] Building and testing locally in a Linux container"
rsync -a \
  --exclude '.git/' --exclude 'node_modules/' --exclude '.next/' --exclude '.release/' \
  --exclude '.agents/' --exclude '.codex/' --exclude '.aws/' --exclude '.ssh/' \
  --exclude '.npm-cache/' --exclude 'outputs/' --exclude 'work/' --exclude 'coverage/' \
  --exclude '__pycache__/' \
  --exclude 'dist/' --exclude '.env' --exclude '.env.*' --exclude '.deploy.env' \
  --exclude "$(basename "$CONFIG_FILE")" --exclude '*.sqlite*' --exclude '*.key' --exclude '*.pem' \
  --exclude 'id_*' --exclude '*.log' "$PROJECT_ROOT/" "$LOCAL_STAGE/source/"
IMAGE="pixiu-local-builder:node24-$ARCHITECTURE"
docker build --platform "linux/$ARCHITECTURE" -t "$IMAGE" -f "$LOCAL_STAGE/source/deploy/Dockerfile.builder" "$LOCAL_STAGE/source/deploy"
docker run --rm --platform "linux/$ARCHITECTURE" --mount "type=bind,source=$LOCAL_STAGE/source,target=/workspace" "$IMAGE" bash scripts/build-release-local.sh "$ARCHITECTURE"
docker run --rm --platform "linux/$ARCHITECTURE" --memory=512m --memory-swap=512m --cpus=1 \
  -e 'NODE_OPTIONS=--max-old-space-size=192 --max-semi-space-size=4' \
  -e STANDALONE_ROOT=/workspace/.release/payload/.next/standalone \
  -e STANDALONE_NODE=/workspace/.release/payload/runtime/node \
  -e HTML_SOURCE_ROOT=/workspace/.release/payload/html-pages \
  --mount "type=bind,source=$LOCAL_STAGE/source,target=/workspace" "$IMAGE" node --test tests/vps-runtime.test.mjs
cp "$LOCAL_STAGE/source/.release/release.tar.gz" "$LOCAL_STAGE/release.tar.gz"
cp "$SCRIPT_DIR/activate-upload-remote.sh" "$SCRIPT_DIR/publish-html-remote.py" "$LOCAL_STAGE/"
(cd "$LOCAL_STAGE" && if command -v sha256sum >/dev/null; then sha256sum release.tar.gz; else shasum -a 256 release.tar.gz; fi) >"$LOCAL_STAGE/checksum.sha256"
RELEASE_ID="$(date -u +%Y%m%d%H%M%S)-$RANDOM"
REMOTE_STAGE=".pixiu-upload-$RELEASE_ID"
SSH_TARGET="$VPS_SSH_USER@$VPS_HOST"
SSH_OPTIONS=(-p "$VPS_SSH_PORT" -o ServerAliveInterval=15 -o ServerAliveCountMax=4)
echo "[2/4] Creating a remote staging directory"
ssh "${SSH_OPTIONS[@]}" "$SSH_TARGET" "test ! -e ~/$REMOTE_STAGE && mkdir -p ~/$REMOTE_STAGE"
echo "[3/4] Uploading the completed Linux artifact"
scp -P "$VPS_SSH_PORT" "$LOCAL_STAGE/release.tar.gz" "$LOCAL_STAGE/checksum.sha256" \
  "$LOCAL_STAGE/activate-upload-remote.sh" "$LOCAL_STAGE/publish-html-remote.py" "$SSH_TARGET:$REMOTE_STAGE/"
echo "[4/4] Activating the artifact (no server compilation)"
ssh -tt "${SSH_OPTIONS[@]}" "$SSH_TARGET" \
  "bash ~/$REMOTE_STAGE/activate-upload-remote.sh ~/$REMOTE_STAGE Full '$VPS_BASE_DIR' '$VPS_APP_USER' '$VPS_APP_GROUP' '$VPS_SERVICE_NAME' '$VPS_HEALTHCHECK_URL' '$VPS_DATA_DIR' '$VPS_ENV_FILE' '$RELEASE_ID'"
echo "Deployment completed: $VPS_HOST ($RELEASE_ID)"
