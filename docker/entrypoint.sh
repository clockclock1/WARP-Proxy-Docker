#!/usr/bin/env bash
set -euo pipefail

STATE_DIR="${STATE_DIR:-/var/lib/warp}"
WIREPROXY_CONFIG="${WIREPROXY_CONFIG:-/etc/wireproxy/config.conf}"
WIREPROXY_CONFIG_DIR="$(dirname "${WIREPROXY_CONFIG}")"

WARP_MODE="${WARP_MODE:-d}"
WARP_SCRIPT_SOURCE="${WARP_SCRIPT_SOURCE:-local}"
WARP_SCRIPT_LOCAL_PATH="${WARP_SCRIPT_LOCAL_PATH:-/opt/warp/warp.sh}"

ENABLE_HTTP_PROXY="${ENABLE_HTTP_PROXY:-true}"
ENABLE_SOCKS5_PROXY="${ENABLE_SOCKS5_PROXY:-true}"
HTTP_BIND_ADDR="${HTTP_BIND_ADDR:-0.0.0.0}"
SOCKS5_BIND_ADDR="${SOCKS5_BIND_ADDR:-0.0.0.0}"
HTTP_PROXY_PORT="${HTTP_PROXY_PORT:-8080}"
SOCKS5_PROXY_PORT="${SOCKS5_PROXY_PORT:-1080}"

PROFILE_FILE=""

is_true() {
  case "${1:-}" in
    1|true|TRUE|yes|YES|on|ON) return 0 ;;
    *) return 1 ;;
  esac
}

read_values() {
  local section="$1"
  local key="$2"
  awk -F ' *= *' -v target_section="${section}" -v target_key="${key}" '
    /^\[/ {
      current=$0
      gsub(/\[|\]/, "", current)
      next
    }
    current == target_section && $1 == target_key {
      print $2
    }
  ' "${PROFILE_FILE}"
}

read_first_value() {
  read_values "$1" "$2" | head -n 1
}

run_warp_script() {
  case "${WARP_MODE}" in
    d|4|6) ;;
    *)
      echo "Invalid WARP_MODE: ${WARP_MODE}. Allowed: d, 4, 6" >&2
      exit 1
      ;;
  esac

  echo "Starting warp.sh with mode '${WARP_MODE}'..."
  if [ "${WARP_SCRIPT_SOURCE}" = "remote" ]; then
    bash <(curl -fsSL git.io/warp.sh) "${WARP_MODE}"
  else
    bash "${WARP_SCRIPT_LOCAL_PATH}" "${WARP_MODE}"
  fi
}

find_profile() {
  local candidates=(
    "${STATE_DIR}/wgcf-profile.conf"
    "/etc/warp/wgcf-profile.conf"
    "/root/wgcf-profile.conf"
    "/wgcf-profile.conf"
  )

  local c
  for c in "${candidates[@]}"; do
    if [ -s "${c}" ]; then
      PROFILE_FILE="${c}"
      return 0
    fi
  done

  return 1
}

mkdir -p "${STATE_DIR}" "${WIREPROXY_CONFIG_DIR}" /etc/wireguard /etc/warp
cd "${STATE_DIR}"

run_warp_script

if [ -s "/etc/warp/wgcf-profile.conf" ]; then
  cp -f "/etc/warp/wgcf-profile.conf" "${STATE_DIR}/wgcf-profile.conf"
fi

if [ -s "/etc/warp/wgcf-account.toml" ]; then
  cp -f "/etc/warp/wgcf-account.toml" "${STATE_DIR}/wgcf-account.toml"
fi

if ! find_profile; then
  echo "wgcf profile not found after running warp.sh." >&2
  exit 1
fi

if ! is_true "${ENABLE_HTTP_PROXY}" && ! is_true "${ENABLE_SOCKS5_PROXY}"; then
  echo "Both ENABLE_HTTP_PROXY and ENABLE_SOCKS5_PROXY are disabled." >&2
  exit 1
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

  while IFS= read -r address; do
    [ -n "${address}" ] && echo "Address = ${address}"
  done < <(read_values Interface Address)

  while IFS= read -r dns; do
    [ -n "${dns}" ] && echo "DNS = ${dns}"
  done < <(read_values Interface DNS)

  MTU="$(read_first_value Interface MTU)"
  [ -n "${MTU}" ] && echo "MTU = ${MTU}"

  echo
  echo "[Peer]"
  echo "PublicKey = ${PUBLIC_KEY}"
  echo "Endpoint = ${ENDPOINT}"

  while IFS= read -r allowed; do
    [ -n "${allowed}" ] && echo "AllowedIPs = ${allowed}"
  done < <(read_values Peer AllowedIPs)

  PRESHARED_KEY="$(read_first_value Peer PreSharedKey)"
  [ -n "${PRESHARED_KEY}" ] && echo "PreSharedKey = ${PRESHARED_KEY}"
} > "${WIREPROXY_CONFIG}"

if is_true "${ENABLE_SOCKS5_PROXY}"; then
  {
    echo
    echo "[Socks5]"
    echo "BindAddress = ${SOCKS5_BIND_ADDR}:${SOCKS5_PROXY_PORT}"
    [ -n "${SOCKS5_USERNAME:-}" ] && echo "Username = ${SOCKS5_USERNAME}"
    [ -n "${SOCKS5_PASSWORD:-}" ] && echo "Password = ${SOCKS5_PASSWORD}"
  } >> "${WIREPROXY_CONFIG}"
fi

if is_true "${ENABLE_HTTP_PROXY}"; then
  {
    echo
    echo "[HTTP]"
    echo "BindAddress = ${HTTP_BIND_ADDR}:${HTTP_PROXY_PORT}"
    [ -n "${HTTP_USERNAME:-}" ] && echo "Username = ${HTTP_USERNAME}"
    [ -n "${HTTP_PASSWORD:-}" ] && echo "Password = ${HTTP_PASSWORD}"
  } >> "${WIREPROXY_CONFIG}"
fi

echo "Starting wireproxy..."
exec wireproxy -c "${WIREPROXY_CONFIG}"
