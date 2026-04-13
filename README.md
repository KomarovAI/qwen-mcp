# Qwen MCP Server

**Docker контейнер с Qwen CLI + qwen-mcp-tool + supergateway.**

Запускает MCP сервер (SSE transport) для подключения внешних AI-агентов (OpenClaw, Claude, и др.) к Qwen API.

---

## Что это

| Компонент | Назначение |
|-----------|-----------|
| `@qwen-code/qwen-code` | Qwen CLI (v0.14.4, OAuth) |
| `qwen-mcp-tool` | MCP обёртка — вызывает qwen CLI как subprocess |
| `supergateway` | Превращает stdio MCP в SSE HTTP endpoint |
| **Anti-detection** | Random jitter 2-8 сек между запросами |

## Архитектура

```
┌──────────────────────┐
│   AI Agent (Client)  │
│   OpenClaw, Claude   │
└──────────┬───────────┘
           │ SSE HTTP
           ▼
┌──────────────────────────────────┐
│  qwen-mcp container              │
│                                  │
│  supergateway :9988              │
│    ↓ SSE → stdio                 │
│  qwen-mcp-tool                   │
│    ↓ subprocess                  │
│  qwen CLI                        │
│    ↓ HTTP (через прокси)         │
└──────────┬───────────────────────┘
           │
    ┌──────▼──────┐
    │ HTTP_PROXY  │
    │ :8121       │
    │ SSH tunnel  │
    └──────┬──────┘
           │
    ┌──────▼──────────────┐
    │ Server 185.232.169.53│
    │ Privoxy :8120       │
    │ → прямой интернет   │
    └─────────────────────┘
```

### Маршрут запросов

```
AI Agent → SSE http://<host>:9988/sse
  → supergateway (SSE → stdio)
  → qwen-mcp-tool (MCP tools)
  → qwen CLI --prompt "..." (subprocess, ~15 сек)
  → HTTP_PROXY:8121 → SSH tunnel → сервер 185.232.169.53
  → Qwen OAuth API
```

**IP выхода:** `185.232.169.53` (Москва, Россия)

---

## Требования

1. **Docker + Docker Compose**
2. **SSH туннель** к серверу (порт 8121)
3. **Qwen OAuth** авторизация (бесплатный аккаунт)

### SSH туннель

```bash
ssh -i ~/.ssh/id_tunnel \
    -L 0.0.0.0:8121:127.0.0.1:8120 \
    -f -N root@185.232.169.53 -p 27016
```

- **Локально:** `0.0.0.0:8121`
- **Удалённо:** `127.0.0.1:8120` (Privoxy на сервере)
- **Результат:** весь HTTP трафик идёт через сервер напрямую

---

## Запуск

### 1. Создать SSH туннель

```bash
ssh -i ~/.ssh/id_tunnel -L 0.0.0.0:8121:127.0.0.1:8120 -f -N root@185.232.169.53 -p 27016
```

Проверить:
```bash
curl -x http://127.0.0.1:8121 http://ipinfo.io/ip
# → 185.232.169.53
```

### 2. Запустить контейнер

```bash
docker compose up -d --build
```

### 3. Авторизовать Qwen OAuth

```bash
docker exec -it qwen-mcp qwen auth qwen-oauth
```

Откроется ссылка → авторизовать в браузере.

### 4. Проверить

```bash
# MCP сервер работает
curl -s http://localhost:9988/sse
# → event: endpoint

# IP правильный
docker exec qwen-mcp curl -s http://ipinfo.io/ip
# → 185.232.169.53

# OAuth активен
docker exec qwen-mcp qwen auth status
```

---

## MCP Endpoints

| Endpoint | Метод | Назначение |
|----------|-------|-----------|
| `/sse` | GET (SSE) | Server-Sent Events для подписки |
| `/message` | POST | Отправка MCP запросов |

### Подключение из OpenClaw

```bash
docker exec openclaw openclaw mcp set qwen '{
  "url": "http://qwen-mcp:9988/sse",
  "transport": "sse",
  "connectionTimeoutMs": 10000
}'
```

### Подключение из другого контейнера

Если оба на одной Docker сети:
```
http://qwen-mcp:9988/sse
```

С хоста:
```
http://localhost:9988/sse
```

---

## Anti-Detection

### Что патчится

| Вектор | Проблема | Решение |
|--------|----------|---------|
| **HTTP трафик** | qwen-mcp-tool вызывает qwen CLI как subprocess | Уже идентичен qwen CLI |
| **Тайминг** | Мгновенные запросы без пауз (бот-паттерн) | **Random jitter 2-8 сек** |
| **Rate limit** | Без ограничений | ~12 req/min (лимит: 60/min) |
| **IP** | Datacenter IP | Сервер 185.232.169.53 (Москва) |

### Как работает задержка

```js
function humanDelay() {
    const minDelay = 2000;  // 2 секунды
    const maxDelay = 8000;  // 8 секунд
    const delay = Math.floor(Math.random() * (maxDelay - minDelay + 1) + minDelay);
    return new Promise(resolve => setTimeout(resolve, delay));
}
```

Каждый вызов инструмента `ask-qwen` ждёт 2-8 секунд перед отправкой.

**Результат:** Qwen API видит случайные паузы = выглядит как человек.

---

## Порты

| Порт | Назначение | Доступ |
|------|-----------|--------|
| `9988` | MCP SSE сервер | Локально + Docker сеть |

---

## Файлы

| Файл | Назначение |
|------|-----------|
| `Dockerfile` | Node.js 20 + qwen CLI + qwen-mcp-tool + supergateway + anti-detection |
| `docker-compose.yml` | Запуск контейнера с портом 9988, прокси, томами |
| `patches/apply-patch.sh` | Скрипт патча: inject humanDelay в qwen-mcp-tool |
| `patches/ask-qwen.tool.js` | Патченная версия ask-qwen инструмента |

---

## Troubleshooting

### Контейнер не запускается

```bash
docker compose logs 2>&1 | tail -20
```

### SSH туннель упал

```bash
# Проверить
ss -tlnp | grep 8121

# Пересоздать
pkill -f "ssh.*8121"
ssh -i ~/.ssh/id_tunnel -L 0.0.0.0:8121:127.0.0.1:8120 -f -N root@185.232.169.53 -p 27016
```

### Qwen OAuth истёк

```bash
docker exec -it qwen-mcp qwen auth qwen-oauth
```

### MCP сервер не отвечает

```bash
# Проверить
docker logs qwen-mcp --tail 20

# Перезапустить
docker compose restart
```

### supergateway упал

```bash
docker logs qwen-mcp 2>&1 | grep -i "error\|exit\|crash"
```

---

## Лимиты Qwen OAuth

| Параметр | Значение |
|----------|----------|
| Тариф | Free tier |
| Лимит | 100 запросов/день |
| Rate limit | 60 запросов/минуту |
| Истечение | 2026-04-15 |

Anti-detection патч держится ~12 req/min — в 5 раз ниже лимита.

---

## Интеграция с OpenClaw

Полная инструкция: [openclaw-vpn-setup](https://github.com/KomarovAI/openclaw-vpn-setup)

Кратко:
1. Оба контейнера на одной Docker сети
2. OpenClaw → `http://qwen-mcp:9988/sse`
3. MCP трафик локальный, не через интернет
4. OpenClaw идёт через VPN, qwen-mcp через сервер

### OpenClaw: максимальные права

OpenClaw агент настроен с полным доступом:
- Sandbox: `off` (без песочницы)
- Tools: `group:openclaw` (все инструменты, без deny)
- Elevated: `enabled` (из webchat, CLI, API)
- Thinking: `high`
