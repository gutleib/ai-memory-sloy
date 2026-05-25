#!/bin/bash
# AI Memory Layer — резервное копирование баз данных
# Единый PostgreSQL, базы ob1 и honcho.
#
# Использование: ./backup.sh
# Результат: backups/ob1-YYYYMMDD-HHMM.sql.gz
#            backups/honcho-YYYYMMDD-HHMM.sql.gz

set -euo pipefail

BACKUP_DIR="$(dirname "$0")/backups"
mkdir -p "$BACKUP_DIR"
DATE=$(date +%Y%m%d-%H%M)

echo "=== OB1 ==="
docker compose exec -T postgres pg_dump -U postgres ob1 | gzip > "$BACKUP_DIR/ob1-${DATE}.sql.gz"
echo "  → $BACKUP_DIR/ob1-${DATE}.sql.gz ($(wc -c < "$BACKUP_DIR/ob1-${DATE}.sql.gz") bytes)"

echo "=== Honcho ==="
docker compose exec -T postgres pg_dump -U postgres honcho | gzip > "$BACKUP_DIR/honcho-${DATE}.sql.gz"
echo "  → $BACKUP_DIR/honcho-${DATE}.sql.gz ($(wc -c < "$BACKUP_DIR/honcho-${DATE}.sql.gz") bytes)"

echo "Done."
