# Миграция Honcho: существующая БД → ai-memory-sloy

## Что происходит

Существующий Honcho: PostgreSQL 15, пользователь `postgres`, база `postgres`.
Новый (ai-memory-sloy): PostgreSQL 17, пользователь `honcho`, база `honcho`.

Переносим дамп `pg_dump` → `psql`, без правки данных.

### Какие пароли сохранить, какие — новые

| Пароль | Старый | Новый | Действие |
|---|---|---|---|
| Доступ к БД | `POSTGRES_PASSWORD` (пользователь `postgres`) | `HONCHO_DB_PASSWORD` (пользователь `honcho`) | **Новый** — пользователи и базы разные |
| Redis | `REDIS_PASSWORD` | `HONCHO_REDIS_PASSWORD` | **Новый** — кеш, данных нет |
| JWT-секрет | `AUTH_JWT_SECRET` | `HONCHO_JWT_SECRET` | **Новый** — токены перевыпустятся |
| API-ключ Honcho | `HONCHO_API_KEY` | `HONCHO_API_KEY` | **Сохранить** — иначе Hermes потеряет подключение. Или сменить и обновить `~/.hermes/honcho.json` |
| Ключ LLM | `DEEPSEEK_API_KEY` / `LLM_OPENAI_API_KEY` | `LLM_API_KEY` | Тот же — внешний API-ключ |

---

## Шаг 1. Дамп существующей БД

```bash
# На хосте со старым Honcho. Замени <container> на имя твоего PostgreSQL-контейнера.
# Узнать имя: docker ps --format '{{.Names}}' | grep database
docker exec <container> \
  pg_dump -U postgres postgres --no-owner --no-acl \
  | zstd -T0 -10 -o honcho-migration-$(date +%Y%m%d).sql.zst
```

Что тут:
- `--no-owner` — не тащить пользователя `postgres` (в новом — `honcho`)
- `--no-acl` — не тащить права доступа (схема другая)
- `zstd -T0 -10` — параллельно по всем ядрам, уровень 10
- Файл: `honcho-migration-20260525.sql.zst`

Проверить размер:
```bash
ls -lh honcho-migration-*.sql.zst
```

---

## Шаг 2. Перенос файла на новый сервер

```bash
scp honcho-migration-*.sql.zst <user>@<host>:~/ai-stack/
```

---

## Шаг 3. Восстановление в новую БД (на новом сервере)

Убедись, что стек запущен и `db-init` отработал:

```bash
cd ~/ai-stack/ai-memory-sloy
docker compose ps | grep db-init
# Должен быть "Exited (0)" — значит БД созданы
```

Если нет — запусти:
```bash
docker compose up -d
# Подождать пока db-init отработает
docker compose logs db-init
# Должно быть: "Done."
```

Теперь заливка:

```bash
zstd -d -c honcho-migration-20260525.sql.zst | \
  docker compose -f ~/ai-stack/ai-memory-sloy/docker-compose.yml exec -T postgres \
  psql -U honcho -d honcho
```

Ожидаемый вывод: поток `CREATE TABLE`, `COPY`, `ALTER TABLE`, без ошибок.
В конце — количество загруженных строк.

---

## Шаг 4. Миграции Alembic (в контейнере Honcho)

После заливки данных — прогнать миграции, чтобы Alembic знал текущую версию:

```bash
docker compose exec honcho-api /app/.venv/bin/python scripts/provision_db.py
```

Это идемпотентно: `CREATE SCHEMA IF NOT EXISTS`, `CREATE EXTENSION IF NOT EXISTS vector`, `alembic upgrade head`. Alembic увидит существующие таблицы и либо применит недостающие миграции, либо подтвердит что всё на месте.

---

## Шаг 5. Проверка

```bash
# Проверить API
curl http://localhost:8000/health
# → {"status": "ok"}

# Проверить количество пиров (должно быть как было)
docker compose exec -T postgres psql -U honcho -d honcho -c "SELECT count(*) FROM peers;"
```

---

## Шаг 6. Обновить конфиг Hermes

В `~/.hermes/honcho.json` поменять `baseUrl`:

```json
{
  "baseUrl": "http://localhost:8000",
  ...
}
```

Перезапустить Hermes: `/reset`.

---

## Если что-то пошло не так

Откат — просто удалить и пересоздать базу:

```bash
docker compose exec -T postgres psql -U postgres -c "DROP DATABASE honcho;"
docker compose exec -T postgres psql -U postgres -c "CREATE DATABASE honcho OWNER honcho;"
# И заново с шага 3
```
