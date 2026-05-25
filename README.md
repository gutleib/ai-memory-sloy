# AI Memory Layer — Полный стек русской AI-памяти

> OB1 (knowledge base) + Honcho (user model) + общие PostgreSQL и эмбеддер.
> Всё в одном `docker compose up`. Минимум app-логики — только оркестрация.

## Что внутри

| Сервис | Порт | Назначение |
|---|---|---|
| **caddy** | `0.0.0.0:80`, `0.0.0.0:443` | Reverse proxy с авто-TLS. `/ob1` → OB1, `/honcho` → Honcho |
| **ob1-server** | внутренний | OB1 MCP: knowledge base, research cache, agent memory |
| **honcho-api** | внутренний | Honcho API: модель пользователя, диалектика |
| **postgres** | `127.0.0.1:5432` | PostgreSQL 17 + pgvector — единый |
| **embedding** | `127.0.0.1:7997` | Infinity + deepvk/USER-bge-m3 (1024-dim) |
| **honcho-redis** | `127.0.0.1:6379` | Redis — кеш Honcho |
| **db-init** | — | One-shot: создаёт пользователей, базы, включает pgvector |

Один PostgreSQL, один эмбеддер, один прокси. Caddy генерит TLS-сертификаты автоматически.

## Быстрый старт

```bash
# 1. Клонировать все три репозитория рядом (ветка selfhosted-ru)
mkdir ~/ai-stack && cd ~/ai-stack
git clone https://github.com/gutleib/ai-memory-sloy.git
git clone https://github.com/gutleib/OB1.git     && cd OB1     && git checkout selfhosted-ru && cd ..
git clone https://github.com/gutleib/honcho.git  && cd honcho  && git checkout selfhosted-ru && cd ..

# 2. Настроить переменные
cd ai-memory-sloy
cp .env.template .env
# Заполнить: LLM_API_KEY, пароли, JWT

# 3. Запустить
docker compose up -d

# 4. Проверить
curl https://ai.local/health       # Caddy
curl https://ai.local/ob1/health   # OB1
curl https://ai.local/honcho/health # Honcho

# Если ai.local не резолвится — добавить в /etc/hosts:
# 127.0.0.1 ai.local
```

## Архитектура

```
              :80, :443
         ┌─────────────────┐
         │  Caddy (TLS)    │
         │  /ob1  /honcho  │
         └───┬─────────┬───┘
             │         │
    ┌────────▼──┐ ┌───▼─────────┐
    │ OB1 Server│ │ Honcho API  │
    │ knowledge │ │ user model  │
    │ base      │ │ dialectic   │
    └─────┬─────┘ └──┬────┬─────┘
          │          │    │
          │    ┌─────▼──┐ │
          │    │ Redis  │ │
          │    └────────┘ │
          │          │    │
    ┌─────▼──────────▼────▼─────┐
    │   PostgreSQL 17 + pgvector│
    │   ┌──────┐  ┌─────────┐   │
    │   │ ob1  │  │ honcho  │   │
    │   └──────┘  └─────────┘   │
    └───────────────────────────┘
                   │
    ┌──────────────┴──────────┐
    │    Infinity :7997       │
    │  USER-bge-m3, 1024-dim  │
    └─────────────────────────┘
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
| `LLM_API_KEY` | OB1 (метаданные) + Honcho (все LLM) |
| `LLM_BASE_URL`, `LLM_MODEL` | Оба (по умолчанию DeepSeek, заменимо) |
| `EMBEDDING_MODEL` | Оба (общий Infinity) |
| `PG_SUPERUSER_PASSWORD` | PostgreSQL |
| `OB1_DB_PASSWORD` | OB1 |
| `HONCHO_DB_PASSWORD` | Honcho |
| `OB1_MCP_ACCESS_KEY` | OB1 |
| `HONCHO_REDIS_PASSWORD` | Honcho |
| `HONCHO_JWT_SECRET`, `HONCHO_API_KEY` | Honcho |

## Caddy и TLS

> При деплое на облачный сервер — закрыть порты 80/443 файрволом или заменить `0.0.0.0` на конкретный IP в docker-compose.

Caddy генерит TLS-сертификаты автоматически через внутренний CA.
Чтобы curl и браузеры не ругались на самоподписанный сертификат —
добавить корневой сертификат Caddy в доверенные на клиентах:

```bash
# Извлечь корневой сертификат из тома Caddy
docker compose cp caddy:/data/caddy/pki/authorities/local/root.crt /tmp/caddy-root.crt

# Linux — добавить в системное хранилище
sudo cp /tmp/caddy-root.crt /usr/local/share/ca-certificates/caddy-root.crt
sudo update-ca-certificates

# macOS
sudo security add-trusted-cert -d -r trustRoot -k /Library/Keychains/System.keychain /tmp/caddy-root.crt
```

После этого `curl https://ai.local` работает без `-k`.

## Подключение Hermes

### OB1 (MCP)

```bash
hermes mcp add ob1 --url "https://ai.local/ob1/mcp?key=YOUR_OB1_MCP_ACCESS_KEY"
hermes mcp test ob1
# После /reset появятся инструменты: search, search_thoughts, capture_thought, ...
```

### Honcho (API)

В `~/.hermes/honcho.json`:

```json
{
  "baseUrl": "https://ai.local/honcho",
  ...
}
```

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

PostgreSQL, Redis и embedding имеют healthcheck. `ob1-server` и `honcho-api` ждут завершения `db-init` и готовности `embedding`. Статус всех: `docker compose ps`.

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
