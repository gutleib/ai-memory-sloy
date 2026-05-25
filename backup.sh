#!/bin/bash
# AI Memory Layer — резервное копирование баз данных
# Единый PostgreSQL, базы ob1 и honcho.
#
# Использование: ./backup.sh
# Результат: backups/ob1-YYYYMMDD-HHMM.sql.zst
#            backups/honcho-YYYYMMDD-HHMM.sql.zst

set -euo pipefail

BACKUP_DIR="$(dirname "$0")/backups"
mkdir -p "$BACKUP_DIR"
DATE=$(date +%Y%m%d-%H%M)

echo "=== OB1 ==="
docker compose exec -T postgres pg_dump -U postgres ob1 \
  | zstd -T0 -8 -o "$BACKUP_DIR/ob1-${DATE}.sql.zst"
echo "  → $BACKUP_DIR/ob1-${DATE}.sql.zst ($(wc -c < "$BACKUP_DIR/ob1-${DATE}.sql.zst") bytes)"

echo "=== Honcho ==="
docker compose exec -T postgres pg_dump -U postgres honcho \
  | zstd -T0 -8 -o "$BACKUP_DIR/honcho-${DATE}.sql.zst"
echo "  → $BACKUP_DIR/honcho-${DATE}.sql.zst ($(wc -c < "$BACKUP_DIR/honcho-${DATE}.sql.zst") bytes)"

echo "Done."
