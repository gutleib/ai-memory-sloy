#!/bin/bash
# Memory Layer — резервное копирование баз данных
# Использование: ./backup.sh
# Результат: backups/ob1-YYYYMMDD-HHMM.sql.gz
#            backups/honcho-YYYYMMDD-HHMM.sql.gz

set -euo pipefail

BACKUP_DIR="$(dirname "$0")/backups"
mkdir -p "$BACKUP_DIR"

DATE=$(date +%Y%m%d-%H%M)

echo "=== OB1 ==="
docker compose exec -T ob1-postgres \
  pg_dump -U ob1 ob1 | gzip > "$BACKUP_DIR/ob1-${DATE}.sql.gz"
echo "  → $BACKUP_DIR/ob1-${DATE}.sql.gz ($(wc -c < "$BACKUP_DIR/ob1-${DATE}.sql.gz") bytes)"

echo "=== Honcho ==="
docker compose exec -T honcho-postgres \
  pg_dump -U postgres postgres | gzip > "$BACKUP_DIR/honcho-${DATE}.sql.gz"
echo "  → $BACKUP_DIR/honcho-${DATE}.sql.gz ($(wc -c < "$BACKUP_DIR/honcho-${DATE}.sql.gz") bytes)"

echo "Done."
