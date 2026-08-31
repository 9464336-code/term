"""Приём событий Chatwoot в вашем приложении (webhooks).

В Chatwoot: Настройки → Интеграции → Webhooks → Добавить webhook →
URL вида https://ваше-приложение/chatwoot-webhook, отметьте события
(минимум message_created).

Запуск примера:
    pip install flask
    python webhook_receiver.py          # слушает :5001

Chatwoot шлёт POST с JSON; ниже разобраны самые полезные поля.
"""

import os

from flask import Flask, request

app = Flask(__name__)

# Тот же токен, что в send_message.py — чтобы можно было ответить через API.
CHATWOOT_URL = os.environ.get("CHATWOOT_URL", "http://localhost:3000")


@app.post("/chatwoot-webhook")
def chatwoot_webhook():
    event = request.get_json(force=True)
    kind = event.get("event")

    if kind == "message_created":
        message_type = event.get("message_type")  # incoming — от клиента, outgoing — от оператора
        if message_type == "incoming":
            conversation_id = event["conversation"]["id"]
            text = event.get("content") or ""
            sender = event.get("sender") or {}
            # identifier — то, что вы передали в setUser() на сайте:
            # по нему находите клиента в своей БД.
            identifier = sender.get("identifier")
            print(f"Сообщение от клиента {identifier or sender.get('name')} "
                  f"(диалог #{conversation_id}): {text}")
            # Здесь ваша логика: создать тикет в CRM, дёрнуть бота,
            # ответить через API (см. send_message.py) и т.д.

    elif kind == "conversation_status_changed":
        conv = event.get("id") or event.get("conversation", {}).get("id")
        print(f"Диалог #{conv} сменил статус на {event.get('status')}")

    elif kind == "conversation_created":
        print(f"Новый диалог #{event.get('id')}")

    return {"ok": True}


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5001)
