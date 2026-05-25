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

**Требования:** Docker Engine ≥ 24, Docker Compose ≥ 2.23.0, git.

```bash
# 1. Клонировать
mkdir ~/ai-stack && cd ~/ai-stack
git clone https://github.com/gutleib/ai-memory-sloy.git
cd ai-memory-sloy

# 2. Настроить
cp .env.template .env
# Заполнить: LLM_API_KEY, пароли, JWT.
# Выбрать DOMAIN — см. три сценария ниже.

# 3. Собрать образы
./setup.sh

# 4. Запустить
docker compose up -d
```

### Сценарий 1: Рабочая станция (localhost)

```bash
# .env: DOMAIN=localhost (уже по умолчанию)
docker compose up -d

# Проверить
curl -k https://localhost/health       # Caddy
curl -k https://localhost/ob1/health   # OB1
curl -k https://localhost/honcho/health # Honcho

# Hermes
hermes mcp add ob1 --url "https://localhost/ob1/mcp?key=..."
# honcho.json: "baseUrl": "https://localhost/honcho"
```

### Сценарий 2: Локальная сеть (ai.local)

```bash
# .env: DOMAIN=ai.local
# На клиентах: /etc/hosts → <IP-сервера> ai.local
docker compose up -d

# Проверить с клиентской машины (или с сервера)
curl -k https://ai.local/health

# Доверить сертификат Caddy на клиентах (см. раздел «Caddy и TLS»)
# После этого curl без -k.

# Hermes
hermes mcp add ob1 --url "https://ai.local/ob1/mcp?key=..."
# honcho.json: "baseUrl": "https://ai.local/honcho"
```

### Сценарий 3: VPS (реальный домен)

```bash
# .env: DOMAIN=ваш-домен.com
# DNS: A-запись домена → IP VPS
docker compose up -d

# Проверить
curl https://ваш-домен.com/health

# Для реального TLS (не self-signed) — заменить 'tls internal' на email в блоке {}:
#       {
#           email ваш@email.com
#       }
# Caddy автоматически получит сертификат от Let's Encrypt.

# Hermes
hermes mcp add ob1 --url "https://ваш-домен.com/ob1/mcp?key=..."
# honcho.json: "baseUrl": "https://ваш-домен.com/honcho"
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

> При деплое на VPS — закрыть порты 80/443 файрволом.
> Для реального TLS от Let's Encrypt — добавить `email ваш@email.com` в блок `{}` секции `configs: caddy_config:` в docker-compose.yml.

Caddy генерит TLS-сертификаты автоматически. Без email — внутренний CA (подходит для localhost/LAN).
Чтобы curl и браузеры не ругались на самоподписанный сертификат — добавить корневой сертификат Caddy в доверенные на клиентах:

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

Для пересборки образов (после обновления кода в GitHub):

```bash
./setup.sh                  # пересобрать образы
docker compose up -d        # перезапустить приложения
```

## Лицензия

MIT
