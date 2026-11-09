#!/usr/bin/env bash

set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REMOTE_SCRIPT="$SCRIPT_DIR/install-ubuntu-system-node-remote.sh"

SSH_TARGET=""
SSH_PORT="22"
IDENTITY_FILE=""
NODE_MAJOR="24"
APP_USER="pixiu"

usage() {
  cat <<'USAGE'
Install system-wide Node.js on an Ubuntu VPS from macOS, Linux, WSL, or Git Bash.

Usage:
  ./scripts/install-ubuntu-system-node-from-macos-linux.sh --target USER@HOST [options]

Options:
  --target USER@HOST   Required SSH destination, for example root@203.0.113.10
  --port PORT          SSH port (default: 22)
  --identity FILE      Optional SSH private key
  --node-major 22|24   Node.js major version (default: 24)
  --app-user USER      Service user to verify (default: pixiu)
  -h, --help           Show this help
USAGE
}

while (($# > 0)); do
  case "$1" in
    --target)
      SSH_TARGET="${2:?--target requires USER@HOST}"
      shift 2
      ;;
    --port)
      SSH_PORT="${2:?--port requires a value}"
      shift 2
      ;;
    --identity)
      IDENTITY_FILE="${2:?--identity requires a file path}"
      shift 2
      ;;
    --node-major)
      NODE_MAJOR="${2:?--node-major requires 22 or 24}"
      shift 2
      ;;
    --app-user)
      APP_USER="${2:?--app-user requires a user name}"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

if [[ -z "$SSH_TARGET" ]]; then
  echo "Missing required option: --target USER@HOST" >&2
  usage >&2
  exit 2
fi
if [[ ! "$SSH_TARGET" =~ ^[A-Za-z_][A-Za-z0-9_-]*@[A-Za-z0-9._:-]+$ ]]; then
  echo "Invalid SSH target: $SSH_TARGET" >&2
  exit 2
fi
if [[ ! "$SSH_PORT" =~ ^[0-9]{1,5}$ ]] || ((10#$SSH_PORT < 1 || 10#$SSH_PORT > 65535)); then
  echo "Invalid SSH port: $SSH_PORT" >&2
  exit 2
fi
if [[ "$NODE_MAJOR" != "22" && "$NODE_MAJOR" != "24" ]]; then
  echo "Node.js major version must be 22 or 24." >&2
  exit 2
fi
if [[ ! "$APP_USER" =~ ^[A-Za-z_][A-Za-z0-9_-]*$ ]]; then
  echo "Invalid application user: $APP_USER" >&2
  exit 2
fi
if [[ -n "$IDENTITY_FILE" && ! -f "$IDENTITY_FILE" ]]; then
  echo "SSH identity file does not exist: $IDENTITY_FILE" >&2
  exit 2
fi
if [[ ! -f "$REMOTE_SCRIPT" ]]; then
  echo "Missing remote installer: $REMOTE_SCRIPT" >&2
  exit 1
fi
if ! command -v ssh >/dev/null 2>&1; then
  echo "Missing local command: ssh" >&2
  exit 1
fi
if ! command -v scp >/dev/null 2>&1; then
  echo "Missing local command: scp" >&2
  exit 1
fi

SSH_OPTIONS=(
  -p "$SSH_PORT"
  -o ServerAliveInterval=15
  -o ServerAliveCountMax=4
)
if [[ -n "$IDENTITY_FILE" ]]; then
  SSH_OPTIONS+=(-i "$IDENTITY_FILE")
fi

SCP_OPTIONS=(
  -P "$SSH_PORT"
  -o ServerAliveInterval=15
  -o ServerAliveCountMax=4
)
if [[ -n "$IDENTITY_FILE" ]]; then
  SCP_OPTIONS+=(-i "$IDENTITY_FILE")
fi

REMOTE_PATH="/tmp/install-system-node-$(date +%s)-$$.sh"

echo "Uploading the installer to $SSH_TARGET..."
scp "${SCP_OPTIONS[@]}" "$REMOTE_SCRIPT" "$SSH_TARGET:$REMOTE_PATH"

echo "Installing system-wide Node.js ${NODE_MAJOR}.x on $SSH_TARGET..."
ssh -tt "${SSH_OPTIONS[@]}" "$SSH_TARGET" \
  "bash '$REMOTE_PATH' '$NODE_MAJOR' '$APP_USER'; install_status=\$?; rm -f -- '$REMOTE_PATH'; exit \$install_status"
