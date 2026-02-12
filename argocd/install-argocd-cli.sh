#!/usr/bin/env bash

set -e

# Проверка запуска от root
if [[ "$EUID" -ne 0 ]]; then
  echo "Please run as root (use sudo)"
  exit 1
fi

# Проверка наличия curl
if ! command -v curl >/dev/null 2>&1; then
  echo "curl is not installed. Please install curl first."
  exit 1
fi

# Проверка установлен ли argocd
if command -v argocd >/dev/null 2>&1; then
  echo "argocd already installed: $(argocd version --client --short 2>/dev/null || echo 'version unknown')"
  exit 0
fi

echo "Installing argocd..."

TMP_FILE="/tmp/argocd-linux-amd64"

curl -sSL -o "$TMP_FILE" \
  https://github.com/argoproj/argo-cd/releases/latest/download/argocd-linux-amd64

install -m 755 "$TMP_FILE" /usr/local/bin/argocd

rm -f "$TMP_FILE"

echo "argocd successfully installed."
argocd version --client
