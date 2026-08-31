# Chatwoot self-hosted — готовый пример

[Chatwoot](https://www.chatwoot.com/) — открытая (MIT) self-hosted платформа общения с клиентами:
виджет чата на сайт, рабочее место операторов, каналы Telegram / WhatsApp / email / API,
webhooks и REST API для интеграции с собственным приложением.

Состав примера:

```
chatwoot/
├── docker-compose.yml        # rails + sidekiq + postgres(pgvector) + redis
├── .env.example              # настройки приложения (скопировать в .env)
├── site/index.html           # страница «вашего сайта» с виджетом чата
└── integration/
    ├── webhook_receiver.py   # приём событий Chatwoot в вашем приложении
    └── send_message.py       # отправка сообщений через API из вашего приложения
```

Требования: Linux-сервер с Docker и docker compose, ~2 CPU / 4 ГБ RAM.

## 1. Запуск

```bash
cd chatwoot
cp .env.example .env
# впишите в .env секрет:
sed -i "s/^SECRET_KEY_BASE=.*/SECRET_KEY_BASE=$(openssl rand -hex 64)/" .env
# при реальном развёртывании поменяйте FRONTEND_URL и пароли БД/Redis

# подготовка базы данных (однократно; также выполняет миграции при обновлениях)
docker compose run --rm rails bundle exec rails db:chatwoot_prepare

docker compose up -d
```

Откройте `http://localhost:3000` (или ваш `FRONTEND_URL`) — форма регистрации
первого аккаунта. После регистрации поставьте в `.env`
`ENABLE_ACCOUNT_SIGNUP=false` и выполните `docker compose up -d`, чтобы
закрыть свободную регистрацию.

Примечание: `GET /api` может отдавать `"data_services":"failing"` даже на
здоровой установке — проверка там опирается на `connection.active?`, который
в новых Rails ленив и до первого запроса возвращает false. Ориентируйтесь на
работу самого интерфейса.

## 2. Виджет на сайт

1. В Chatwoot: **Настройки → Входящие → Добавить входящий → Website**, укажите домен сайта.
2. На последнем шаге Chatwoot покажет готовый скрипт с `websiteToken` — тот же
   сниппет лежит в `site/index.html`: впишите туда свой `BASE_URL` и `websiteToken`.
3. Откройте страницу — в углу появится чат; переписка попадает операторам в Chatwoot
   (веб-интерфейс + мобильные приложения Chatwoot для iOS/Android).

Проверить локально: `python3 -m http.server 8080 --directory site` → http://localhost:8080

### Привязка залогиненного пользователя сайта

Если посетитель авторизован в вашем приложении, вызовите на странице
`window.$chatwoot.setUser(identifier, {...})` (пример закомментирован в
`site/index.html`). Тогда:

- оператор видит имя/email/атрибуты клиента из вашей системы;
- во всех webhooks к вам приходит этот же `identifier` — по нему вы находите
  клиента у себя в БД.

В проде включите в настройках инбокса **проверку личности (HMAC)** и передавайте
`identifier_hash = hex(hmac_sha256(ключ_инбокса, identifier))`, посчитанный на
бэкенде, — иначе любой сможет представиться чужим `identifier`.

## 3. Интеграция с вашим приложением

Два канала связи:

**События из Chatwoot к вам (webhooks).** Настройки → Интеграции → Webhooks →
URL вашего обработчика. Пример обработчика — `integration/webhook_receiver.py`
(Flask): ловит `message_created` от клиента, достаёт `identifier` и текст.

**Действия из вашего приложения (REST API).** Токен: профиль → Настройки
профиля → Access Token. Пример — `integration/send_message.py`: отправка
ответа в диалог, список открытых диалогов. Полная документация API:
https://developers.chatwoot.com/api-reference

Так можно, например: показывать переписку в своей CRM, отвечать из неё,
автоматически создавать диалоги, подключить своего бота (в Chatwoot есть и
отдельный Agent Bot API c передачей диалога живому оператору).

## 4. Продакшен

- Поставьте перед `rails` reverse-proxy с HTTPS (порт 3000 в compose привязан
  к 127.0.0.1). Пример для nginx:

```nginx
server {
    listen 443 ssl http2;
    server_name chat.example.com;
    # ssl_certificate / ssl_certificate_key — например, от certbot

    location / {
        proxy_pass http://127.0.0.1:3000;
        proxy_http_version 1.1;
        proxy_set_header Host $host;
        proxy_set_header X-Forwarded-Proto $scheme;
        # WebSocket (живые обновления чата)
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
    }
}
```

- В `.env`: `FRONTEND_URL=https://chat.example.com`, `FORCE_SSL=true`,
  свои пароли `POSTGRES_PASSWORD` / `REDIS_PASSWORD`, SMTP для писем.
- Обновление версии: поднять тег образа в `docker-compose.yml`, затем
  `docker compose pull && docker compose run --rm rails bundle exec rails db:chatwoot_prepare && docker compose up -d`.
- Бэкапы: том `postgres` (или `pg_dump`) + том `storage` (вложения).
