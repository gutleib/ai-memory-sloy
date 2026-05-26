# AI Memory Layer — Полный стек русской AI-памяти

> OB1 (knowledge base) + Honcho (user model) + общие PostgreSQL и эмбеддер.
> Всё в одном `docker compose up`. Минимум app-логики — только оркестрация.

## Что внутри

| Сервис | Порт | Назначение |
|---|---|---|
| **caddy** | `0.0.0.0:80` | Reverse proxy. `/ob1` → OB1, `/honcho` → Honcho. По умолчанию HTTP, TLS — опционально |
| **ob1-server** | внутренний | OB1 MCP: knowledge base, research cache, agent memory |
| **honcho-api** | внутренний | Honcho API: модель пользователя, диалектика |
| **postgres** | `127.0.0.1:5432` | PostgreSQL 17 + pgvector — единый |
| **embedding** | `127.0.0.1:7997` | Infinity + deepvk/USER-bge-m3 (1024-dim) |
| **honcho-redis** | `127.0.0.1:6379` | Redis — кеш Honcho |
| **db-init** | — | One-shot: создаёт пользователей, базы, включает pgvector |

Один PostgreSQL, один эмбеддер, один прокси. По умолчанию HTTP; TLS — опционально (см. «Настройка TLS»).

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
curl http://localhost/health       # Caddy
curl http://localhost/ob1/health   # OB1
curl http://localhost/honcho/health # Honcho

# Hermes (если Hermes на той же машине)
hermes mcp add ob1 --url "http://localhost/ob1/mcp?key=***"
# honcho.json: "baseUrl": "http://localhost/honcho"
```

### Сценарий 2: Локальная сеть (по IP или ai.local)

```bash
# .env: DOMAIN=<IP-сервера>  или  DOMAIN=ai.local
# На клиентах (для ai.local): /etc/hosts → <IP-сервера> ai.local
docker compose up -d

# Проверить с клиентской машины
curl http://<IP-сервера>/health
# или: curl http://ai.local/health

# Hermes
hermes mcp add ob1 --url "http://<IP-сервера>/ob1/mcp?key=***"
# honcho.json: "baseUrl": "http://<IP-сервера>/honcho"
```

### Сценарий 3: VPS (реальный домен)

```bash
# .env: DOMAIN=ваш-домен.com
# DNS: A-запись домена → IP VPS
docker compose up -d

# Проверить (HTTP по умолчанию)
curl http://ваш-домен.com/health

# С TLS (после настройки Let's Encrypt — см. раздел «Настройка TLS»):
# curl https://ваш-домен.com/health

# Hermes
hermes mcp add ob1 --url "https://ваш-домен.com/ob1/mcp?key=***"
# honcho.json: "baseUrl": "https://ваш-домен.com/honcho"

# Для TLS — см. раздел «Настройка TLS», вариант 3 (Let's Encrypt).
```

## Архитектура

```
              :80
         ┌─────────────────┐
         │  Caddy (HTTP)   │
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

## Настройка TLS

По умолчанию Caddy работает на **HTTP без шифрования** — подходит для локальной сети
и разработки. Три способа включить TLS:

### 1. Без TLS (по умолчанию) — локальная сеть, разработка

`docker-compose.yml` (configs — caddy_config):

```
http://{$DOMAIN} {
    handle_path /ob1/* { reverse_proxy ob1-server:7981 }
    handle_path /honcho/* { reverse_proxy honcho-api:8000 }
    respond /health 200
}
```

Подходит для:
- `localhost` (рабочая станция)
- Локальная сеть по IP (`DOMAIN=<IP-сервера>`)
- Локальная сеть с `/etc/hosts` (`DOMAIN=ai.local`)

> Трафик не шифруется — не используйте в ненадёжных сетях.

### 2. TLS internal (самоподписанный) — LAN с доменом

Заменить `http://{$DOMAIN}` на `{$DOMAIN}` и добавить `tls internal`:

```
{$DOMAIN} {
    tls internal
    handle_path /ob1/* { reverse_proxy ob1-server:7981 }
    handle_path /honcho/* { reverse_proxy honcho-api:8000 }
    respond /health 200
}
```

Добавить HTTPS-порт в `caddy` сервис:
```yaml
ports:
  - "0.0.0.0:${CADDY_HTTP_PORT:-80}:80"
  - "0.0.0.0:${CADDY_HTTPS_PORT:-443}:443"
```

И в `.env.template`:
```
CADDY_HTTP_PORT=80
CADDY_HTTPS_PORT=443
```

Caddy сгенерит самоподписанный сертификат. Чтобы curl и браузеры не ругались —
добавить корневой сертификат Caddy в доверенные на клиентах:

```bash
docker compose cp caddy:/data/caddy/pki/authorities/local/root.crt /tmp/caddy-root.crt
sudo cp /tmp/caddy-root.crt /usr/local/share/ca-certificates/caddy-root.crt
sudo update-ca-certificates    # Linux
# macOS: sudo security add-trusted-cert -d -r trustRoot -k /Library/Keychains/System.keychain /tmp/caddy-root.crt
```

### 3. TLS Let's Encrypt (настоящий сертификат) — VPS с доменом

Требуется: реальный домен с A-записью на IP сервера.

В глобальный блок `{}` добавить email:

```
{
    email ваш@email.com
}

{$DOMAIN} {
    handle_path /ob1/* { reverse_proxy ob1-server:7981 }
    handle_path /honcho/* { reverse_proxy honcho-api:8000 }
    respond /health 200
}
```

Caddy автоматически получит сертификат от Let's Encrypt. HTTPS-порт обязателен (см. вариант 2).

> При деплое на VPS — закрыть порты файрволом кроме 80/443.

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
