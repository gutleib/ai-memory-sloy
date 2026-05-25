#!/bin/sh
# ai-memory-sloy — подготовка стека: сборка образов OB1 и Honcho
# Клонирует из GitHub, собирает Docker-образы, чистит.
# Также подтягивает внешние образы, чтобы Compose не ходил в registry.
#
# Использование: ./setup.sh

set -e

command -v git >/dev/null 2>&1 || { echo "ERROR: git not found"; exit 1; }
command -v docker >/dev/null 2>&1 || { echo "ERROR: docker not found"; exit 1; }

REPO_OB1="${OB1_REPO:-https://github.com/gutleib/OB1.git}"
REPO_HONCHO="${HONCHO_REPO:-https://github.com/gutleib/honcho.git}"
BRANCH="${BRANCH:-selfhosted-ru}"
BUILD_DIR="$(mktemp -d)"
trap 'rm -rf "$BUILD_DIR"' EXIT

echo "=== Pulling external images ==="
docker pull "${IMAGE_PGVECTOR:-pgvector/pgvector:pg17}"
docker pull "${IMAGE_REDIS:-redis:8.2}"
docker pull "${IMAGE_INFINITY:-michaelf34/infinity:0.0.77-cpu}"
docker pull "${IMAGE_CADDY:-caddy:2-alpine}"

echo "=== Building OB1 ==="
git clone --depth 1 --branch "$BRANCH" "$REPO_OB1" "$BUILD_DIR/OB1"
docker build -t ai-memory-sloy/ob1-server:latest "$BUILD_DIR/OB1/server-python"

echo "=== Building Honcho ==="
git clone --depth 1 --branch "$BRANCH" "$REPO_HONCHO" "$BUILD_DIR/honcho"
docker build -t ai-memory-sloy/honcho-api:latest "$BUILD_DIR/honcho"

echo "Done."
