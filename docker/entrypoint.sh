#!/bin/sh
set -eu

STATE_DIR="${STATE_DIR:-/var/lib/warp}"
WIREPROXY_CONFIG="${WIREPROXY_CONFIG:-/etc/wireproxy/config.conf}"
WGCF_ACCOUNT_FILE="${STATE_DIR}/wgcf-account.toml"
WGCF_PROFILE_FILE="${STATE_DIR}/wgcf-profile.conf"
WIREPROXY_CONFIG_DIR="$(dirname "${WIREPROXY_CONFIG}")"

ENABLE_HTTP_PROXY="${ENABLE_HTTP_PROXY:-true}"
ENABLE_SOCKS5_PROXY="${ENABLE_SOCKS5_PROXY:-true}"
HTTP_BIND_ADDR="${HTTP_BIND_ADDR:-0.0.0.0}"
SOCKS5_BIND_ADDR="${SOCKS5_BIND_ADDR:-0.0.0.0}"
HTTP_PROXY_PORT="${HTTP_PROXY_PORT:-8080}"
SOCKS5_PROXY_PORT="${SOCKS5_PROXY_PORT:-1080}"
WGCF_RETRIES="${WGCF_RETRIES:-0}"
WGCF_RETRY_DELAY="${WGCF_RETRY_DELAY:-5}"

if [ "$(id -u)" = "0" ]; then
  mkdir -p "${STATE_DIR}" "${WIREPROXY_CONFIG_DIR}"
  chown -R warp:warp "${STATE_DIR}" "${WIREPROXY_CONFIG_DIR}" 2>/dev/null || true
  if su-exec warp sh -c "touch '${STATE_DIR}/.warp-write-test' && rm -f '${STATE_DIR}/.warp-write-test'" >/dev/null 2>&1; then
    exec su-exec warp "$0" "$@"
  fi
  echo "Warning: cannot write mounted directory as user 'warp', fallback to root runtime." >&2
fi

to_bool() {
  case "$1" in
    1|true|TRUE|yes|YES|on|ON) echo "true" ;;
    *) echo "false" ;;
  esac
}

read_values() {
  section="$1"
  key="$2"
  awk -F ' *= *' -v target_section="${section}" -v target_key="${key}" '
    /^\[/ {
      current=$0
      gsub(/\[|\]/, "", current)
      next
    }
    current == target_section && $1 == target_key {
      print $2
    }
  ' "${WGCF_PROFILE_FILE}"
}

read_first_value() {
  read_values "$1" "$2" | head -n 1
}

run_with_retry() {
  retries="$1"
  delay="$2"
  shift 2
  attempt=1
  while true; do
    if "$@"; then
      return 0
    fi
    if [ "${retries}" -gt 0 ] && [ "${attempt}" -ge "${retries}" ]; then
      return 1
    fi
    if [ "${retries}" -gt 0 ]; then
      echo "Command failed, retrying in ${delay}s (${attempt}/${retries})..." >&2
    else
      echo "Command failed, retrying in ${delay}s (attempt ${attempt}, unlimited retries)..." >&2
    fi
    attempt=$((attempt + 1))
    sleep "${delay}"
  done
}

HTTP_ENABLED="$(to_bool "${ENABLE_HTTP_PROXY}")"
SOCKS5_ENABLED="$(to_bool "${ENABLE_SOCKS5_PROXY}")"

if [ "${HTTP_ENABLED}" = "false" ] && [ "${SOCKS5_ENABLED}" = "false" ]; then
  echo "Both ENABLE_HTTP_PROXY and ENABLE_SOCKS5_PROXY are disabled." >&2
  exit 1
fi

mkdir -p "${STATE_DIR}" "${WIREPROXY_CONFIG_DIR}"
cd "${STATE_DIR}"

if [ ! -s "${WGCF_ACCOUNT_FILE}" ] && [ -n "${WARP_ACCOUNT_TOML_BASE64:-}" ]; then
  echo "Importing wgcf-account.toml from WARP_ACCOUNT_TOML_BASE64..."
  printf "%s" "${WARP_ACCOUNT_TOML_BASE64}" | base64 -d > "${WGCF_ACCOUNT_FILE}"
fi

if [ ! -s "${WGCF_PROFILE_FILE}" ] && [ -n "${WARP_PROFILE_CONF_BASE64:-}" ]; then
  echo "Importing wgcf-profile.conf from WARP_PROFILE_CONF_BASE64..."
  printf "%s" "${WARP_PROFILE_CONF_BASE64}" | base64 -d > "${WGCF_PROFILE_FILE}"
fi

if [ ! -s "${WGCF_ACCOUNT_FILE}" ]; then
  echo "No WARP account found. Registering a new account..."
  run_with_retry "${WGCF_RETRIES}" "${WGCF_RETRY_DELAY}" wgcf register --accept-tos
fi

if [ -n "${WARP_LICENSE_KEY:-}" ]; then
  if [ -s "${WGCF_ACCOUNT_FILE}" ]; then
    echo "Applying WARP+ license..."
    run_with_retry "${WGCF_RETRIES}" "${WGCF_RETRY_DELAY}" wgcf update --license "${WARP_LICENSE_KEY}"
  else
    echo "Warning: WARP_LICENSE_KEY is set but wgcf-account.toml is missing; skip license update." >&2
  fi
fi

if [ ! -s "${WGCF_PROFILE_FILE}" ] || [ "${FORCE_REGENERATE_PROFILE:-false}" = "true" ]; then
  echo "Generating WARP profile..."
  run_with_retry "${WGCF_RETRIES}" "${WGCF_RETRY_DELAY}" wgcf generate
fi

PRIVATE_KEY="$(read_first_value Interface PrivateKey)"
PUBLIC_KEY="$(read_first_value Peer PublicKey)"
ENDPOINT="$(read_first_value Peer Endpoint)"

if [ -z "${PRIVATE_KEY}" ] || [ -z "${PUBLIC_KEY}" ] || [ -z "${ENDPOINT}" ]; then
  echo "Invalid wgcf profile: missing required fields." >&2
  exit 1
fi

{
  echo "[Interface]"
  echo "PrivateKey = ${PRIVATE_KEY}"

  read_values Interface Address | while IFS= read -r address; do
    if [ -n "${address}" ]; then
      echo "Address = ${address}"
    fi
  done

  read_values Interface DNS | while IFS= read -r dns; do
    if [ -n "${dns}" ]; then
      echo "DNS = ${dns}"
    fi
  done

  MTU="$(read_first_value Interface MTU)"
  if [ -n "${MTU}" ]; then
    echo "MTU = ${MTU}"
  fi

  echo
  echo "[Peer]"
  echo "PublicKey = ${PUBLIC_KEY}"
  echo "Endpoint = ${ENDPOINT}"

  read_values Peer AllowedIPs | while IFS= read -r allowed; do
    if [ -n "${allowed}" ]; then
      echo "AllowedIPs = ${allowed}"
    fi
  done

  PRESHARED_KEY="$(read_first_value Peer PreSharedKey)"
  if [ -n "${PRESHARED_KEY}" ]; then
    echo "PreSharedKey = ${PRESHARED_KEY}"
  fi
} > "${WIREPROXY_CONFIG}"

if [ "${SOCKS5_ENABLED}" = "true" ]; then
  {
    echo
    echo "[Socks5]"
    echo "BindAddress = ${SOCKS5_BIND_ADDR}:${SOCKS5_PROXY_PORT}"
    if [ -n "${SOCKS5_USERNAME:-}" ]; then
      echo "Username = ${SOCKS5_USERNAME}"
    fi
    if [ -n "${SOCKS5_PASSWORD:-}" ]; then
      echo "Password = ${SOCKS5_PASSWORD}"
    fi
  } >> "${WIREPROXY_CONFIG}"
fi

if [ "${HTTP_ENABLED}" = "true" ]; then
  {
    echo
    echo "[HTTP]"
    echo "BindAddress = ${HTTP_BIND_ADDR}:${HTTP_PROXY_PORT}"
    if [ -n "${HTTP_USERNAME:-}" ]; then
      echo "Username = ${HTTP_USERNAME}"
    fi
    if [ -n "${HTTP_PASSWORD:-}" ]; then
      echo "Password = ${HTTP_PASSWORD}"
    fi
  } >> "${WIREPROXY_CONFIG}"
fi

echo "Starting wireproxy..."
exec wireproxy -c "${WIREPROXY_CONFIG}"
