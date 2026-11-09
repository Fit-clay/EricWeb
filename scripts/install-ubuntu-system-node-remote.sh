#!/usr/bin/env bash

set -Eeuo pipefail

NODE_MAJOR="${1:-24}"
APP_USER="${2:-pixiu}"

case "$NODE_MAJOR" in
  22|24) ;;
  *)
    echo "Unsupported Node.js major version: $NODE_MAJOR (allowed: 22 or 24)" >&2
    exit 1
    ;;
esac

if [[ ! "$APP_USER" =~ ^[A-Za-z_][A-Za-z0-9_-]*$ ]]; then
  echo "Invalid application user: $APP_USER" >&2
  exit 1
fi

if [[ ! -f /etc/os-release ]]; then
  echo "Cannot identify the remote operating system." >&2
  exit 1
fi

# shellcheck disable=SC1091
source /etc/os-release
if [[ "${ID:-}" != "ubuntu" && "${ID_LIKE:-}" != *debian* ]]; then
  echo "This installer only supports Ubuntu/Debian servers (detected: ${PRETTY_NAME:-unknown})." >&2
  exit 1
fi

if ((EUID == 0)); then
  PRIVILEGED=()
else
  if ! command -v sudo >/dev/null 2>&1; then
    echo "The SSH user must be root or have sudo installed." >&2
    exit 1
  fi
  if ! sudo -v; then
    echo "The SSH user could not obtain sudo privileges." >&2
    exit 1
  fi
  PRIVILEGED=(sudo)
fi

ARCHITECTURE="$(dpkg --print-architecture)"
case "$ARCHITECTURE" in
  amd64|arm64) ;;
  *)
    echo "Unsupported CPU architecture: $ARCHITECTURE (allowed: amd64 or arm64)" >&2
    exit 1
    ;;
esac

TEMP_DIR="$(mktemp -d)"
cleanup() {
  rm -rf -- "$TEMP_DIR"
}
trap cleanup EXIT

echo "Installing prerequisites on ${PRETTY_NAME:-Ubuntu}..."
"${PRIVILEGED[@]}" apt-get update
"${PRIVILEGED[@]}" env DEBIAN_FRONTEND=noninteractive \
  apt-get install -y build-essential ca-certificates curl gnupg python3 rsync

echo "Configuring the NodeSource Node.js ${NODE_MAJOR}.x repository..."
curl --fail --silent --show-error --location \
  https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key \
  --output "$TEMP_DIR/nodesource.asc"
gpg --batch --yes --dearmor \
  --output "$TEMP_DIR/nodesource.gpg" "$TEMP_DIR/nodesource.asc"

cat >"$TEMP_DIR/nodesource.sources" <<EOF
Types: deb
URIs: https://deb.nodesource.com/node_${NODE_MAJOR}.x
Suites: nodistro
Components: main
Architectures: ${ARCHITECTURE}
Signed-By: /usr/share/keyrings/nodesource.gpg
EOF

cat >"$TEMP_DIR/nodejs-preferences" <<'EOF'
Package: nodejs
Pin: origin deb.nodesource.com
Pin-Priority: 600
EOF

"${PRIVILEGED[@]}" install -d -m 0755 \
  /usr/share/keyrings /etc/apt/sources.list.d /etc/apt/preferences.d
"${PRIVILEGED[@]}" install -m 0644 \
  "$TEMP_DIR/nodesource.gpg" /usr/share/keyrings/nodesource.gpg
"${PRIVILEGED[@]}" install -m 0644 \
  "$TEMP_DIR/nodesource.sources" /etc/apt/sources.list.d/nodesource.sources
"${PRIVILEGED[@]}" install -m 0644 \
  "$TEMP_DIR/nodejs-preferences" /etc/apt/preferences.d/nodejs

# Remove the obsolete one-line NodeSource entry if a previous installer created it.
"${PRIVILEGED[@]}" rm -f /etc/apt/sources.list.d/nodesource.list

echo "Installing system-wide Node.js ${NODE_MAJOR}.x..."
"${PRIVILEGED[@]}" apt-get update
"${PRIVILEGED[@]}" env DEBIAN_FRONTEND=noninteractive \
  apt-get install -y nodejs

if [[ ! -x /usr/bin/node || ! -x /usr/bin/npm ]]; then
  echo "Installation finished, but /usr/bin/node or /usr/bin/npm is missing." >&2
  exit 1
fi

INSTALLED_MAJOR="$(/usr/bin/node -p 'process.versions.node.split(".")[0]')"
if [[ "$INSTALLED_MAJOR" != "$NODE_MAJOR" ]]; then
  echo "Expected Node.js ${NODE_MAJOR}.x, but /usr/bin/node reports $(/usr/bin/node --version)." >&2
  exit 1
fi

echo "System Node.js: $(/usr/bin/node --version) (/usr/bin/node)"
echo "System npm:     $(/usr/bin/npm --version) (/usr/bin/npm)"

if id "$APP_USER" >/dev/null 2>&1; then
  if [[ "$(id -un)" == "$APP_USER" ]]; then
    /usr/bin/node --version >/dev/null
    /usr/bin/npm --version >/dev/null
  elif ((EUID == 0)); then
    if ! command -v runuser >/dev/null 2>&1; then
      echo "Cannot verify $APP_USER because runuser is unavailable." >&2
      exit 1
    fi
    runuser -u "$APP_USER" -- /usr/bin/node --version >/dev/null
    runuser -u "$APP_USER" -- /usr/bin/npm --version >/dev/null
  else
    sudo -u "$APP_USER" -- /usr/bin/node --version >/dev/null
    sudo -u "$APP_USER" -- /usr/bin/npm --version >/dev/null
  fi
  echo "Application user '$APP_USER' can execute the system Node.js and npm."
else
  echo "Application user '$APP_USER' does not exist yet; skipping that permission check."
fi

echo "System-wide Node.js installation completed successfully."
echo "An existing NVM installation was left unchanged."
