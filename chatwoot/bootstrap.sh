#!/usr/bin/env bash
# Однокомандный запуск демо: поднимает стек, создаёт аккаунт + Website-инбокс,
# подставляет токен в страницу сайта и печатает готовые ссылки.
#
#   ./bootstrap.sh
#
# После запуска:
#   - приложение оператора: http://localhost:3000  (вход admin@example.com / SuperSecret1!.)
#   - страница сайта с виджетом: http://localhost:8080
set -euo pipefail
cd "$(dirname "$0")"

DEMO_EMAIL="admin@example.com"
DEMO_PASSWORD="SuperSecret1!."

# 1. .env с секретом
if [ ! -f .env ]; then
  cp .env.example .env
  sed -i "s/^SECRET_KEY_BASE=.*/SECRET_KEY_BASE=$(openssl rand -hex 64)/" .env
  echo "Создан .env"
fi

# 2. Подготовка БД (идемпотентно) и запуск
docker compose run --rm rails bundle exec rails db:chatwoot_prepare
docker compose up -d

# 3. Ждём веб-процесс
echo -n "Ждём Chatwoot"
until curl -sf --noproxy '*' -o /dev/null "http://localhost:3000/api"; do echo -n "."; sleep 3; done
echo " готов"

# 4. Аккаунт + Website-инбокс (find-or-create), получаем токены
SEED=$(docker compose exec -T rails bundle exec rails runner '
account = Account.first || AccountBuilder.new(account_name: "Demo", user_full_name: "Demo Admin", email: "'"$DEMO_EMAIL"'", user_password: "'"$DEMO_PASSWORD"'", super_admin: true, confirmed: true).perform && Account.first
user = User.find_by(email: "'"$DEMO_EMAIL"'") || User.first
user.update!(password: "'"$DEMO_PASSWORD"'", password_confirmation: "'"$DEMO_PASSWORD"'")
inbox = account.inboxes.find_by(name: "Website") || account.inboxes.create!(name: "Website", channel: Channel::WebWidget.create!(account: account, website_url: "http://localhost:8080"))
token = user.access_token&.token || user.create_access_token!.token
puts "SEED account_id=#{account.id} website_token=#{inbox.channel.website_token} api_token=#{token}"
' 2>&1 | grep "^SEED")

WEBSITE_TOKEN=$(echo "$SEED" | sed -n 's/.*website_token=\([^ ]*\).*/\1/p')
API_TOKEN=$(echo "$SEED" | sed -n 's/.*api_token=\([^ ]*\).*/\1/p')

# 5. Страница сайта с подставленным токеном (в run/ — не трогаем шаблон site/index.html)
mkdir -p run
sed "s/ВАШ_WEBSITE_TOKEN/$WEBSITE_TOKEN/" site/index.html > run/index.html

# 6. Статический сервер для страницы сайта
pkill -f "http.server 8080" 2>/dev/null || true
( cd run && nohup python3 -m http.server 8080 >/tmp/chatwoot-site.log 2>&1 & )

cat <<EOF

============================================================
  Chatwoot запущен.

  Приложение оператора : http://localhost:3000
      логин  : $DEMO_EMAIL
      пароль : $DEMO_PASSWORD

  Страница сайта с виджетом : http://localhost:8080

  Website token : $WEBSITE_TOKEN
  API token     : $API_TOKEN

  Проверка: напишите что-нибудь в виджете на :8080 —
  сообщение появится у оператора на :3000.
============================================================
EOF
