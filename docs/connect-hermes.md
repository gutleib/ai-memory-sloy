# Подключение Hermes Agent к ai-memory-sloy

Как подключить [Hermes Agent](https://github.com/NousResearch/hermes-agent) к стеку
**Honcho** (память/модель пользователя) + **OB1** (knowledge base) за 5 минут.

## Что ты получишь

После подключения Hermes будет:

- **Помнить** тебя между сессиями — факты, предпочтения, контекст (Honcho)
- **Искать** инженерные решения в knowledge base (OB1)
- **Сохранять** новые инженерные инсайты через `capture_thought` (OB1)
- **Писать** выводы о пользователе через `honcho_conclude` (Honcho)

## Шаг 0. До запуска

Убедись, что стек ai-memory-sloy запущен:

```bash
docker compose ps
# Должны быть: postgres, embedding, ob1-server, honcho-api, honcho-deriver, honcho-redis, caddy
```

Проверь доступность эндпоинтов:

```bash
curl -s http://<IP-сервера>/health             # → "ok"
curl -s http://<IP-сервера>/ob1/health         # → {"status":"ok"}
curl -s http://<IP-сервера>/honcho/health      # → {"status":"ok"}
```

---

## Шаг 1. Подключение Honcho (память пользователя)

### 1.1. SDK

```bash
pip install 'honcho-ai>=2.0.1'
```

### 1.2. Сгенерируй JWT-токен

Нужен **подписанный JWT**, не raw-секрет. Секрет — значение `AUTH_JWT_SECRET`
из файла `.env` на сервере.

```bash
python3 -c "
import jwt
secret = '$(grep HONCHO_JWT_SECRET .env | cut -d= -f2)'
token = jwt.encode({'w': 'hermes', 't': ''}, secret, algorithm='HS256')
print(f'HONCHO_API_KEY={token}')
"
```

### 1.3. Создай `~/.hermes/honcho.json`

```json
{
  "baseUrl": "http://<IP-сервера>/honcho",
  "apiKey": "<JWT-токен из шага 1.2>",
  "hosts": {
    "hermes": {
      "workspace": "hermes",
      "peerName": "<твой peer, например gutleib>",
      "aiPeer": "hermes",
      "enabled": true,
      "observationMode": "directional",
      "writeFrequency": "async",
      "recallMode": "hybrid"
    }
  }
}
```

Значения:
- `baseUrl` — `http://<IP-сервера>:8080/honcho` (через Caddy)
- `workspace` — `hermes` (задано в compose.yml, менять не нужно)
- `peerName` — твой идентификатор (любая строка)
- `aiPeer` — имя AI-пира (любая строка, по умолчанию `hermes`)
- `recallMode` — `hybrid` (автоинжект контекста + инструменты)

### 1.4. Провайдер памяти

```bash
# В config.yaml
hermes config set memory.provider honcho
```

### 1.5. API-ключ в `.env`

```bash
echo "HONCHO_API_KEY=<JWT-токен из шага 1.2>" >> ~/.hermes/.env
```

> Важно: `.env` защищён от `write_file`/`patch`. Используй `sed` или `tee -a`.

### 1.6. Инструменты Honcho в toolsets

```bash
hermes config set toolsets '["hermes-cli", "ob1", "honcho"]'
```

### 1.7. Проверка

```bash
hermes honcho status
```

Ожидаемый вывод: `Enabled: True`, `Connection... OK`.

> После первой сессии статус может показать «No peer data yet» — это нормально,
> данные накапливаются по ходу диалога.

---

## Шаг 2. Подключение OB1 (knowledge base)

### 2.1. MCP-сервер в config.yaml

```bash
hermes config set mcp_servers.ob1.url "http://<IP-сервера>/ob1/mcp/"
hermes config set mcp_servers.ob1.headers.x-brain-key '${OB1_BRAIN_KEY}'
hermes config set mcp_servers.ob1.enabled true
```

Переменная `${OB1_BRAIN_KEY}` раскрывается из `~/.hermes/.env`.

### 2.2. Ключ в `.env`

```bash
# Значение OB1_MCP_ACCESS_KEY из .env на сервере
echo "OB1_BRAIN_KEY=<ключ>" >> ~/.hermes/.env
```

### 2.3. OB1 в toolsets

```bash
hermes config set toolsets '["hermes-cli", "ob1", "honcho"]'
```

### 2.4. Проверка

```bash
hermes mcp test ob1
```

Ожидаемый вывод: `✓ Connected`, `✓ Tools discovered: 6`.

---

## Шаг 3. Финальный штрих

Перезапусти Hermes (выйди и зайди, или `/reset` в чате).

После перезапуска в сессии будут доступны:

**Инструменты Honcho (5 шт.):**
- `honcho_profile` — карточка пользователя (быстрые факты)
- `honcho_search` — семантический поиск по памяти
- `honcho_context` — сырой контекст пира
- `honcho_reasoning` — синтезированный ответ через dialiectic
- `honcho_conclude` — запись вывода о пользователе

**Инструменты OB1 (6 шт.):**
- `mcp_ob1_capture_thought` — сохранить мысль
- `mcp_ob1_search` — поиск по смыслу
- `mcp_ob1_search_thoughts` — поиск с фильтрами
- `mcp_ob1_fetch` — загрузить мысль по ID
- `mcp_ob1_list_thoughts` — список недавних мыслей
- `mcp_ob1_thought_stats` — статистика

---

## Рабочий пример сессии

```
User: Что ты знаешь обо мне?

Agent: [honcho_profile()] → карточка с фактами
Agent: [honcho_search("предпочтения")] → релевантные факты

User: Как мы настраивали Graylog?

Agent: [mcp_ob1_search("Graylog deployment")] → инженерный инсайт из OB1

User: Сохрани, что я предпочитаю Ansible для деплоя.

Agent: [honcho_conclude(conclusion="Предпочитает Ansible...")] → сохранено
Agent: [mcp_ob1_capture_thought(content="Ansible — предпочтительный...")]
```

---

## Если что-то не работает

### Honcho: «No peer data yet»

Нормально для новой сессии. Проверь реальные данные:

```bash
docker compose exec postgres psql -U honcho -d honcho \
  -c "SELECT observer, observed, COUNT(*) FROM documents WHERE deleted_at IS NULL GROUP BY 1, 2;"
```

### Honcho: 401 Unauthorized

JWT-токен невалиден. Проверь, что `AUTH_JWT_SECRET` на сервере совпадает
с тем, которым подписан токен.

### OB1: tools not discovered

Убедись, что `ob1` есть в `toolsets` в config.yaml:

```bash
hermes config show toolsets  # должно быть: ["hermes-cli", "ob1", "honcho"]
```

### Инструменты не появились после настройки

Нужен `/reset` (новая сессия). Конфигурация toolsets подхватывается
при старте сессии.

---

## Использованные переменные

| Где | Переменная | Значение |
|-----|-----------|----------|
| `~/.hermes/.env` | `HONCHO_API_KEY` | JWT-токен (из шага 1.2) |
| `~/.hermes/.env` | `OB1_BRAIN_KEY` | `OB1_MCP_ACCESS_KEY` из серверного `.env` |
| `~/.hermes/config.yaml` | `memory.provider` | `honcho` |
| `~/.hermes/config.yaml` | `toolsets` | `["hermes-cli", "ob1", "honcho"]` |
| `~/.hermes/config.yaml` | `mcp_servers.ob1.url` | `http://<IP>/ob1/mcp/` |
| `~/.hermes/config.yaml` | `mcp_servers.ob1.headers.x-brain-key` | `${OB1_BRAIN_KEY}` |
| `~/.hermes/honcho.json` | `baseUrl` | `http://<IP>/honcho` |
| `~/.hermes/honcho.json` | `apiKey` | JWT-токен |
