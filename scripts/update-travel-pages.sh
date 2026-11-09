#!/usr/bin/env bash

set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SOURCE_DIR="${TRAVEL_SOURCE_DIR:-/Users/eric/Desktop/AI/travel}"
CONFIG_FILE="$PROJECT_ROOT/.deploy.env"
MODE="sync-and-deploy"
LOCAL_ROOT="$PROJECT_ROOT/html-pages/travel"
REMOTE_HELPER="$SCRIPT_DIR/update-travel-pages-remote.sh"

usage() {
  cat <<'USAGE'
用法：
  ./scripts/update-travel-pages.sh [选项]

默认从 travel 源目录更新仓库内页面，然后上传到 VPS；页面更新不需要
重新构建或重启网站。

选项：
  --source DIR      travel 源目录
  --config FILE     部署配置文件，默认使用 .deploy.env
  --local-only      只更新仓库内 html-pages/travel
  --deploy-only     只将仓库内现有页面上传到 VPS
  -h, --help        显示帮助
USAGE
}

while (($# > 0)); do
  case "$1" in
    --source)
      SOURCE_DIR="${2:?--source 需要目录路径}"
      shift 2
      ;;
    --config)
      CONFIG_FILE="${2:?--config 需要文件路径}"
      shift 2
      ;;
    --local-only)
      MODE="local-only"
      shift
      ;;
    --deploy-only)
      MODE="deploy-only"
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "未知参数：$1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

require_command() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "本机缺少命令：$1" >&2
    exit 1
  fi
}

validate_page_assets() {
  local html_file="$1"
  local page_dir
  local reference
  local asset_path
  page_dir="$(dirname "$html_file")"

  while IFS= read -r reference; do
    case "$reference" in
      http://*|https://*|data:*|//*|'')
        continue
        ;;
    esac
    asset_path="${reference%%\?*}"
    asset_path="${asset_path%%\#*}"
    if [[ ! -f "$page_dir/$asset_path" ]]; then
      echo "页面资源缺失：$page_dir/$asset_path" >&2
      exit 1
    fi
  done < <(grep -Eo '(src|data-src)="[^"]+"' "$html_file" | cut -d '"' -f 2)
}

sync_local_pages() {
  require_command rsync

  local dumbbell_html="$SOURCE_DIR/dumbbell-workout-gif-guide.html"
  local dumbbell_assets="$SOURCE_DIR/dumbbell-workout-assets"
  local gym_html="$SOURCE_DIR/gym-5-day-cardio-strength-plan.html"
  local gym_assets="$SOURCE_DIR/exercise-gifs"

  for required_path in \
    "$dumbbell_html" "$dumbbell_assets" "$gym_html" "$gym_assets"; do
    if [[ ! -e "$required_path" ]]; then
      echo "travel 源内容不存在：$required_path" >&2
      exit 1
    fi
  done

  mkdir -p \
    "$LOCAL_ROOT/dumbbell-workout/dumbbell-workout-assets" \
    "$LOCAL_ROOT/gym-5-day-plan/exercise-gifs"

  rsync -a "$dumbbell_html" "$LOCAL_ROOT/dumbbell-workout/index.html"
  rsync -a --delete \
    "$dumbbell_assets/" \
    "$LOCAL_ROOT/dumbbell-workout/dumbbell-workout-assets/"
  rsync -a "$gym_html" "$LOCAL_ROOT/gym-5-day-plan/index.html"
  rsync -a --delete \
    "$gym_assets/" \
    "$LOCAL_ROOT/gym-5-day-plan/exercise-gifs/"

  validate_page_assets "$LOCAL_ROOT/dumbbell-workout/index.html"
  validate_page_assets "$LOCAL_ROOT/gym-5-day-plan/index.html"
  echo "已更新仓库内的两个 travel 页面及其本地资源。"
}

validate_deploy_value() {
  local name="$1"
  local value="$2"
  local pattern="$3"
  if [[ ! "$value" =~ $pattern ]]; then
    echo "部署配置 $name 格式不正确：$value" >&2
    exit 1
  fi
}

deploy_pages() {
  require_command ssh
  require_command scp
  require_command rsync

  if [[ ! -f "$CONFIG_FILE" ]]; then
    echo "缺少部署配置：$CONFIG_FILE" >&2
    echo "可复制 .deploy.env.example 为 .deploy.env 后填写服务器信息。" >&2
    exit 1
  fi
  if [[ ! -f "$REMOTE_HELPER" ]]; then
    echo "缺少远程更新脚本：$REMOTE_HELPER" >&2
    exit 1
  fi
  if [[ ! -f "$LOCAL_ROOT/dumbbell-workout/index.html" || \
    ! -f "$LOCAL_ROOT/gym-5-day-plan/index.html" ]]; then
    echo "仓库内尚未准备好两个 travel 页面，请先执行本地同步。" >&2
    exit 1
  fi

  set -a
  # shellcheck disable=SC1090
  source "$CONFIG_FILE"
  set +a

  : "${VPS_HOST:?请在部署配置中填写 VPS_HOST}"
  : "${VPS_SSH_USER:?请在部署配置中填写 VPS_SSH_USER}"
  VPS_SSH_PORT="${VPS_SSH_PORT:-22}"
  VPS_APP_USER="${VPS_APP_USER:-pixiu}"
  VPS_APP_GROUP="${VPS_APP_GROUP:-pixiu}"
  VPS_DATA_DIR="${VPS_DATA_DIR:-/var/lib/pixiu-library}"

  validate_deploy_value "VPS_HOST" "$VPS_HOST" '^[A-Za-z0-9._-]+$'
  validate_deploy_value "VPS_SSH_USER" "$VPS_SSH_USER" '^[A-Za-z_][A-Za-z0-9_-]*$'
  validate_deploy_value "VPS_SSH_PORT" "$VPS_SSH_PORT" '^[0-9]{1,5}$'
  validate_deploy_value "VPS_APP_USER" "$VPS_APP_USER" '^[A-Za-z_][A-Za-z0-9_-]*$'
  validate_deploy_value "VPS_APP_GROUP" "$VPS_APP_GROUP" '^[A-Za-z_][A-Za-z0-9_-]*$'
  validate_deploy_value "VPS_DATA_DIR" "$VPS_DATA_DIR" '^/[A-Za-z0-9._/-]+$'

  if ((10#$VPS_SSH_PORT < 1 || 10#$VPS_SSH_PORT > 65535)); then
    echo "部署配置 VPS_SSH_PORT 必须在 1 到 65535 之间。" >&2
    exit 1
  fi
  if [[ "$VPS_DATA_DIR" == "/" || "$VPS_DATA_DIR" == */ || \
    "$VPS_DATA_DIR" == *"/../"* || "$VPS_DATA_DIR" == */.. ]]; then
    echo "部署配置 VPS_DATA_DIR 不安全：$VPS_DATA_DIR" >&2
    exit 1
  fi

  local release_id
  local remote_stage
  local ssh_target
  local rsync_ssh
  local -a ssh_options
  release_id="$(date -u +%Y%m%d%H%M%S)"
  remote_stage=".pixiu-travel-pages-$release_id-$$"
  ssh_target="$VPS_SSH_USER@$VPS_HOST"
  ssh_options=(-p "$VPS_SSH_PORT" -o ServerAliveInterval=15 -o ServerAliveCountMax=4)
  rsync_ssh="ssh -p $VPS_SSH_PORT -o ServerAliveInterval=15 -o ServerAliveCountMax=4"

  echo "[1/3] 创建服务器页面更新临时目录"
  ssh "${ssh_options[@]}" "$ssh_target" \
    "test ! -e ~/$remote_stage && mkdir -p ~/$remote_stage/pages"

  echo "[2/3] 上传两个页面及本地资源"
  rsync -az --delete --progress \
    -e "$rsync_ssh" \
    "$LOCAL_ROOT/" "$ssh_target:~/$remote_stage/pages/"
  scp -P "$VPS_SSH_PORT" \
    -o ServerAliveInterval=15 \
    -o ServerAliveCountMax=4 \
    "$REMOTE_HELPER" "$ssh_target:~/$remote_stage/update.sh"
  scp -P "$VPS_SSH_PORT" "$SCRIPT_DIR/publish-html-remote.py" "$ssh_target:~/$remote_stage/publish-html-remote.py"

  echo "[3/3] 更新观景启窗持久化页面目录"
  ssh -tt "${ssh_options[@]}" "$ssh_target" \
    "bash ~/$remote_stage/update.sh ~/$remote_stage/pages '$VPS_DATA_DIR' '$VPS_APP_USER' '$VPS_APP_GROUP'; update_status=\$?; rm -rf -- ~/$remote_stage; exit \$update_status"

  echo "页面更新完成：${VPS_HOST}"
  echo "访问路径：/html/travel/dumbbell-workout/index.html"
  echo "访问路径：/html/travel/gym-5-day-plan/index.html"
}

case "$MODE" in
  local-only)
    sync_local_pages
    ;;
  deploy-only)
    validate_page_assets "$LOCAL_ROOT/dumbbell-workout/index.html"
    validate_page_assets "$LOCAL_ROOT/gym-5-day-plan/index.html"
    deploy_pages
    ;;
  sync-and-deploy)
    sync_local_pages
    deploy_pages
    ;;
esac
