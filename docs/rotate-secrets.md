# Ротация секретов ai-memory-sloy

Как сменить все пароли и ключи, сохранив данные и подключения агентов.
Данные живут в томах PostgreSQL (`pgdata`) — ротация секретов их не трогает.

## Что можно ротировать без потери данных

| Секрет | Где хранится | Данные затронуты? |
|--------|-------------|-------------------|
| `PG_SUPERUSER_PASSWORD` | `.env`, postgres | Нет |
| `OB1_DB_PASSWORD` | `.env`, db-init | Нет |
| `HONCHO_DB_PASSWORD` | `.env`, db-init, honcho-api, honcho-deriver | Нет |
| `HONCHO_REDIS_PASSWORD` | `.env`, honcho-redis, honcho-api, honcho-deriver | Нет |
| `LLM_API_KEY` | `.env`, honcho-api, honcho-deriver, ob1-server | Нет |
| `HONCHO_JWT_SECRET` | `.env`, honcho-api, honcho-deriver | **Да — все JWT-токены становятся невалидными** |
| `HONCHO_API_KEY` | `.env`, `~/.hermes/.env` | **Да — нужно перегенерировать** |
| `OB1_MCP_ACCESS_KEY` | `.env`, `~/.hermes/.env` | Нет |

---

## Быстрая ротация (всё кроме JWT)

### Шаг 1. Сгенерируй новые пароли

```bash
# DB-пароли и пароль Redis
openssl rand -hex 32  # повторить для каждого
```

### Шаг 2. Обнови `.env` на сервере

```bash
cd /gt-micro-omv/aux/docker/compose/ai-memory-sloy
vim .env  # или nano .env
```

Замени:
- `PG_SUPERUSER_PASSWORD`
- `OB1_DB_PASSWORD`
- `HONCHO_DB_PASSWORD`
- `HONCHO_REDIS_PASSWORD`
- `LLM_API_KEY` (если меняешь ключ DeepSeek)

### Шаг 3. Обнови пароль `honcho` в БД

Новый пароль из `.env` нужно применить к роли `honcho` внутри PostgreSQL:

```bash
docker compose exec postgres psql -U postgres -c \
  "ALTER ROLE honcho WITH PASSWORD 'новый-пароль';"
```

> Для `postgres` (суперпользователь) — аналогично: `ALTER ROLE postgres WITH PASSWORD '...';`

### Шаг 4. Примени compose

```bash
docker compose up -d --force-recreate
```

### Шаг 5. Обнови ключ OB1 на клиенте Hermes

Если менял `OB1_MCP_ACCESS_KEY`:

```bash
# В ~/.hermes/.env на машине агента
sed -i 's/^OB1_BRAIN_KEY=.*/OB1_BRAIN_KEY=<новый-ключ>/' ~/.hermes/.env
```

---

## Полная ротация (включая JWT)

Добавь к шагам выше:

### Доп. шаг A. Сгенерируй новый JWT-секрет

```bash
openssl rand -hex 32
```

Замени `HONCHO_JWT_SECRET` в `.env` на сервере.

### Доп. шаг B. Сгенерируй новый JWT-токен

```bash
python3 -c "
import jwt
secret = 'НОВЫЙ_JWT_СЕКРЕТ'
token = jwt.encode({'w': 'hermes', 't': ''}, secret, algorithm='HS256')
print(token)
"
```

### Доп. шаг C. Обнови токен везде

На сервере — `HONCHO_API_KEY` в `.env`:

```bash
sed -i 's/^HONCHO_API_KEY=.*/HONCHO_API_KEY=<новый-токен>/' .env
```

На клиенте Hermes — два места:

```bash
# ~/.hermes/.env
sed -i 's/^HONCHO_API_KEY=.*/HONCHO_API_KEY=<новый-токен>/' ~/.hermes/.env

# ~/.hermes/honcho.json
python3 -c "
import json
with open('$HOME/.hermes/honcho.json') as f:
    cfg = json.load(f)
cfg['apiKey'] = '<новый-токен>'
with open('$HOME/.hermes/honcho.json', 'w') as f:
    json.dump(cfg, f, indent=2)
print('honcho.json updated')
"
```

### Доп. шаг D. Примени compose на сервере

```bash
docker compose up -d --force-recreate
```

### Доп. шаг E. Перезапусти Hermes

Выйди из сессии и зайди заново, или `/reset`.

---

## Проверка после ротации

```bash
# Сервер: все контейнеры healthy
docker compose ps

# Сервер: Honcho принимает новый токен
curl -s http://localhost:8000/health

# Клиент: Hermes видит Honcho
hermes honcho status

# Клиент: OB1 на связи
hermes mcp test ob1
```

---

## Если что-то пошло не так

### Honcho: 401 после ротации JWT

Проверь, что `HONCHO_API_KEY` на сервере и на клиенте — **один и тот же подписанный JWT**, а не raw-секрет:

```bash
# На сервере
docker compose exec honcho-api env | grep HONCHO_API_KEY

# На клиенте
grep HONCHO_API_KEY ~/.hermes/.env
cat ~/.hermes/honcho.json | python3 -c "import json,sys; print(json.load(sys.stdin)['apiKey'])"
```

Все три значения должны совпадать.

### Postgres: password authentication failed

Новый пароль не применился к роли. Выполни шаг 3 вручную:

```bash
# Сначала со старым паролем (если контейнер ещё не пересоздан)
docker compose exec postgres psql -U postgres -c "ALTER ROLE honcho WITH PASSWORD 'новый-пароль';"
```

### Redis: NOAUTH

```bash
docker compose restart honcho-redis
```
