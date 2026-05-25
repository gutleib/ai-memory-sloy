# Memory Layer — Полный стек русской AI-памяти

> OB1 + Honcho + общий эмбеддер. Всё в одном `docker compose up`.

## Что внутри

| Сервис | Порт | Назначение |
|---|---|---|
| **embedding** | `127.0.0.1:7997` | Infinity + deepvk/USER-bge-m3 (1024-dim) — общий для обоих |
| **ob1-server** | `127.0.0.1:7981` | OB1 MCP: knowledge base, research cache, agent memory |
| **ob1-postgres** | `127.0.0.1:5432` | PostgreSQL 16 + pgvector для OB1 |
| **honcho-api** | `127.0.0.1:8000` | Honcho API: модель пользователя, диалектика |
| **honcho-postgres** | `127.0.0.1:5433` | PostgreSQL 15 + pgvector для Honcho |
| **honcho-redis** | `127.0.0.1:6379` | Redis — кеш Honcho |

Одна модель bge-m3 (~6.6 GB RAM) обслуживает оба проекта. Один DeepSeek API-ключ на всех.

## Быстрый старт

```bash
# 1. Клонировать все три репозитория рядом
mkdir ~/ai-stack && cd ~/ai-stack
git clone https://github.com/gutleib/ai-memory-sloy.git
git clone https://github.com/gutleib/OB1.git
git clone https://github.com/gutleib/honcho.git

# 2. Настроить переменные
cd infra-memory
cp .env.template .env
# Заполнить: DEEPSEEK_API_KEY, все пароли, JWT

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
└──────┬──────┘       └───────┬──────┘
       │                      │
┌──────▼──────┐       ┌───────▼──────┐
│  OB1 PG:5432│       │Honcho PG:5433│
│  (pgvector) │       │  (pgvector)  │
└─────────────┘       └──────┬───────┘
                             │
                      ┌──────▼──────┐
                      │ Redis :6379 │
                      └─────────────┘

       ┌─────────────────────┐
       │  Infinity :7997     │
       │  USER-bge-m3, 1024d │
       │  (общий эмбеддер)   │
       └──────────┬──────────┘
                  │
       ┌──────────┴──────────┐
       │  Оба сервера        │
       │  ходят сюда         │
       └─────────────────────┘
```

## Системные требования

| Ресурс | Минимум | Рекомендуется |
|---|---|---|
| RAM | 12 GB | 16+ GB |
| CPU | 4 ядра | 8 ядер |
| Диск | 30 GB | 50+ GB |

Раскладка по памяти:
- Infinity + bge-m3: ~7 GB
- OB1 server: ~200 MB
- Honcho API + deriver: ~800 MB (пиково >1 GB)
- PostgreSQL ×2: ~300 MB
- Redis: ~10 MB

## Переменные

Все ключи — в одном `.env`. Никакого дублирования:

| Переменная | Кто использует |
|---|---|
| `DEEPSEEK_API_KEY` | OB1 (метаданные) + Honcho (все LLM) |
| `DEEPSEEK_URL` | Оба |
| `DEEPSEEK_MODEL` | Оба |
| `EMBEDDING_MODEL` | Оба (общий Infinity) |
| `OB1_DB_PASSWORD` | OB1 |
| `OB1_MCP_ACCESS_KEY` | OB1 |
| `HONCHO_DB_PASSWORD` | Honcho |
| `HONCHO_REDIS_PASSWORD` | Honcho |
| `HONCHO_JWT_SECRET` | Honcho |
| `HONCHO_API_KEY` | Honcho |

## Самостоятельный запуск проектов

Каждый проект можно запустить отдельно (без memory-layer):

```bash
# Только OB1
cd ../OB1 && docker compose up -d

# Только Honcho
cd ../honcho && docker compose -f docker-compose.selfhosted.yml up -d
```

При самостоятельном запуске каждый поднимает свой Infinity. В memory-layer — один на двоих.

## Лицензия

MIT

## Обслуживание

### Резервное копирование

```bash
./backup.sh
```

Создаст `backups/ob1-*.sql.gz` и `backups/honcho-*.sql.gz`. Рекомендуется в cron:

```bash
# Ежедневно в 3:00
0 3 * * * cd ~/ai-stack/ai-memory-sloy && ./backup.sh
```

### Healthcheck

Все сервисы имеют healthcheck в docker-compose:
- `embedding`: `curl http://localhost:7997/health`, start_period=120s (модель грузится ~2 мин)
- `ob1-server`, `honcho-api`: ждут готовности embedding перед стартом
- `*-postgres`: `pg_isready`

Статус всех сервисов: `docker compose ps`.
