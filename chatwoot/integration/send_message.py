"""Отправка сообщений в диалог Chatwoot из вашего приложения (Application API).

Токен: в Chatwoot нажмите на свой профиль → Настройки профиля →
Access Token (или создайте отдельного агента-бота для интеграции).

    pip install requests
    export CHATWOOT_URL=http://localhost:3000
    export CHATWOOT_API_TOKEN=xxxxxxxx
    export CHATWOOT_ACCOUNT_ID=1
    python send_message.py <conversation_id> "Текст ответа"
"""

import os
import sys

import requests

CHATWOOT_URL = os.environ.get("CHATWOOT_URL", "http://localhost:3000")
API_TOKEN = os.environ["CHATWOOT_API_TOKEN"]
ACCOUNT_ID = os.environ.get("CHATWOOT_ACCOUNT_ID", "1")

HEADERS = {"api_access_token": API_TOKEN}


def send_message(conversation_id: int, text: str) -> dict:
    """Отправить сообщение клиенту в существующий диалог от имени оператора."""
    r = requests.post(
        f"{CHATWOOT_URL}/api/v1/accounts/{ACCOUNT_ID}/conversations/{conversation_id}/messages",
        headers=HEADERS,
        json={"content": text, "message_type": "outgoing"},
        timeout=10,
    )
    r.raise_for_status()
    return r.json()


def list_open_conversations() -> list:
    """Открытые диалоги — например, чтобы показать очередь в своём интерфейсе."""
    r = requests.get(
        f"{CHATWOOT_URL}/api/v1/accounts/{ACCOUNT_ID}/conversations",
        headers=HEADERS,
        params={"status": "open"},
        timeout=10,
    )
    r.raise_for_status()
    return r.json()["data"]["payload"]


if __name__ == "__main__":
    conv_id, text = int(sys.argv[1]), sys.argv[2]
    msg = send_message(conv_id, text)
    print(f"Отправлено, id сообщения: {msg['id']}")
