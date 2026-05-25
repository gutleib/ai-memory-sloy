# AI Memory Layer — Полный стек русской AI-памяти

> OB1 (knowledge base) + Honcho (user model) + общие PostgreSQL и эмбеддер.
> Всё в одном `docker compose up`. Минимум app-логики — только оркестрация.

## Что внутри

| Сервис | Порт | Назначение |
|---|---|---|
| **postgres** | `127.0.0.1:5432` | PostgreSQL 17 + pgvector — единый, базы `ob1` и `honcho` |
| **db-init** | — | One-shot: создаёт пользователей, базы, включает pgvector |
| **embedding** | `127.0.0.1:7997` | Infinity + deepvk/USER-bge-m3 (1024-dim) — общий |
| **ob1-server** | `127.0.0.1:7981` | OB1 MCP: knowledge base, research cache, agent memory |
| **honcho-api** | `127.0.0.1:8000` | Honcho API: модель пользователя, диалектика |
| **honcho-redis** | `127.0.0.1:6379` | Redis — кеш Honcho |

Один PostgreSQL (pg17), один эмбеддер (~6.6 GB RAM), один DeepSeek API-ключ на весь стек.

## Быстрый старт

```bash
# 1. Клонировать все три репозитория рядом
mkdir ~/ai-stack && cd ~/ai-stack
git clone https://github.com/gutleib/ai-memory-sloy.git
git clone https://github.com/gutleib/OB1.git
git clone https://github.com/gutleib/honcho.git

# 2. Настроить переменные
cd ai-memory-sloy
cp .env.template .env
# Заполнить: DEEPSEEK_API_KEY, пароли, JWT

# 3. Запустить
docker compose up -d

# 4. Проверить
curl http://localhost:7997/models   # Infinity
curl http://localhost:7981/health   # OB1
curl http://localhost:8000/health   # Honcho
```

## Архитектура

```
┌─────────────────────────────────────────────┐
│                 DeepSeek API                 │
│         (LLM — deriver, dialectic,          │
│          metadata extraction)               │
└──────┬──────────────────────┬───────────────┘
       │                      │
┌──────▼──────┐       ┌───────▼──────┐
│  OB1 Server │       │ Honcho API   │
│  (MCP:7981) │       │  (API:8000)  │
│  knowledge  │       │  user model  │
│  base       │       │  dialectic   │
└──────┬──────┘       └───┬─────┬────┘
       │                  │     │
       │           ┌──────▼──┐  │
       │           │ Redis   │  │
       │           │ :6379   │  │
       │           └─────────┘  │
       │                  │     │
┌──────▼──────────────────▼─────▼──────┐
│           PostgreSQL 17 + pgvector   │
│         ┌──────┐    ┌─────────┐      │
│         │ ob1  │    │ honcho  │      │
│         └──────┘    └─────────┘      │
│              :5432                   │
└──────────────────────────────────────┘
                      │
       ┌──────────────┴──────────────┐
       │       Infinity :7997        │
       │   USER-bge-m3, 1024-dim     │
       │      (общий эмбеддер)       │
       └─────────────────────────────┘
```

## Системные требования

| Ресурс | Минимум | Рекомендуется |
|---|---|---|
| RAM | 11 GB | 14+ GB |
| CPU | 4 ядра | 8 ядер |
| Диск | 25 GB | 40+ GB |

Раскладка по памяти:
- Infinity + bge-m3: ~7 GB
- PostgreSQL (единый): ~500 MB
- Honcho API + deriver: ~800 MB
- OB1 server: ~200 MB
- Redis: ~10 MB

## Переменные (единый .env)

| Переменная | Кто использует |
|---|---|
| `DEEPSEEK_API_KEY` | OB1 (метаданные) + Honcho (все LLM) |
| `DEEPSEEK_URL`, `DEEPSEEK_MODEL` | Оба |
| `EMBEDDING_MODEL` | Оба (общий Infinity) |
| `PG_SUPERUSER_PASSWORD` | PostgreSQL |
| `OB1_DB_PASSWORD` | OB1 |
| `HONCHO_DB_PASSWORD` | Honcho |
| `OB1_MCP_ACCESS_KEY` | OB1 |
| `HONCHO_REDIS_PASSWORD` | Honcho |
| `HONCHO_JWT_SECRET`, `HONCHO_API_KEY` | Honcho |

## Обслуживание

### Миграция существующего Honcho

См. [docs/migration-honcho.md](docs/migration-honcho.md).

### Резервное копирование

```bash
./backup.sh
```

Создаст `backups/ob1-*.sql.gz` и `backups/honcho-*.sql.gz`.

```bash
# Ежедневно в 3:00
0 3 * * * cd ~/ai-stack/ai-memory-sloy && ./backup.sh
```

### Статус

```bash
docker compose ps
```

Все сервисы имеют healthcheck. `ob1-server` и `honcho-api` ждут завершения `db-init` и готовности `embedding`.

## Самостоятельный запуск проектов

Каждый проект можно запустить отдельно (со своим PostgreSQL):

```bash
# Только OB1
cd ../OB1 && docker compose up -d

# Только Honcho
cd ../honcho && docker compose -f docker-compose.selfhosted.yml up -d
```

## Лицензия

MIT
