#!/usr/bin/env bash
set -euo pipefail
cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.."
if [[ ${EUID} -ne 0 ]]; then echo '请使用 sudo bash scripts/install.sh'; exit 1; fi
source /etc/os-release
case "${ID}" in ubuntu|debian) ;; *) echo '仅支持 Ubuntu/Debian'; exit 1;; esac
if [[ $(uname -m) != aarch64 ]]; then echo '本配置仅验证 ARM64/aarch64'; exit 1; fi
if ! command -v docker >/dev/null || ! docker compose version >/dev/null 2>&1; then
  # Official signed Docker apt repository, not a third-party curl|sh installer.
  apt-get update
  apt-get install -y ca-certificates curl gnupg python3 openssl
  install -m 0755 -d /etc/apt/keyrings
  if [[ ! -f /etc/apt/keyrings/docker.asc ]]; then
    curl --fail --show-error --silent --location "https://download.docker.com/linux/${ID}/gpg" -o /etc/apt/keyrings/docker.asc
    chmod a+r /etc/apt/keyrings/docker.asc
  fi
  if [[ ! -f /etc/apt/sources.list.d/docker-cloudplay.list ]]; then
    printf 'deb [arch=%s signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/%s %s stable\n' \
      "$(dpkg --print-architecture)" "$ID" "${VERSION_CODENAME}" > /etc/apt/sources.list.d/docker-cloudplay.list
  fi
  apt-get update
  if command -v docker >/dev/null; then
    # An existing engine may serve other applications; only add its CLI plugins.
    apt-get install -y docker-buildx-plugin docker-compose-plugin
  else
    apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
    systemctl enable --now docker
  fi
fi
for tool in python3 openssl curl; do
  if ! command -v "$tool" >/dev/null; then apt-get update; apt-get install -y python3 openssl curl; break; fi
done
exec python3 scripts/install.py "$@"
