#!/usr/bin/env bash
# Публичный демо-доступ к Chatwoot через Cloudflare Tunnel одной командой.
#
#   ./tunnel-up.sh
#
# Требуется свободный доступ в интернет к сети Cloudflare.
# Даёт две публичные https-ссылки: приложение оператора и страницу с виджетом.
set -euo pipefail
cd "$(dirname "$0")"

COMPOSE="docker compose -f docker-compose.yml -f docker-compose.tunnel.yml"
DEMO_EMAIL="admin@example.com"
DEMO_PASSWORD="SuperSecret1!."

# Достаём публичный URL из логов cloudflared (ждём до ~60 c).
wait_for_url() {
  local svc="$1" url=""
  for _ in $(seq 1 30); do
    url=$($COMPOSE logs "$svc" 2>/dev/null | grep -oE 'https://[a-z0-9-]+\.trycloudflare\.com' | head -1 || true)
    [ -n "$url" ] && { echo "$url"; return 0; }
    sleep 2
  done
  return 1
}

# 0. .env с секретом
if [ ! -f .env ]; then
  cp .env.example .env
  sed -i "s/^SECRET_KEY_BASE=.*/SECRET_KEY_BASE=$(openssl rand -hex 64)/" .env
fi

# 1. БД + базовые сервисы
docker compose run --rm rails bundle exec rails db:chatwoot_prepare
docker compose up -d
echo -n "Ждём Chatwoot"; until curl -sf --noproxy '*' -o /dev/null http://localhost:3000/api; do echo -n .; sleep 3; done; echo

# 2. Туннель на приложение оператора и его публичный URL
$COMPOSE up -d cloudflared-app
echo "Поднимаем туннель на приложение оператора..."
APP_URL=$(wait_for_url cloudflared-app) || { echo "Не удалось получить URL туннеля (нет доступа к Cloudflare?)"; exit 1; }
echo "Приложение оператора: $APP_URL"

# 3. Перенастраиваем Chatwoot на публичный адрес и перезапускаем
sed -i "s#^FRONTEND_URL=.*#FRONTEND_URL=$APP_URL#" .env
sed -i "s#^FORCE_SSL=.*#FORCE_SSL=true#" .env
docker compose up -d rails sidekiq
echo -n "Ждём перезапуск Chatwoot"; until curl -sf --noproxy '*' -o /dev/null http://localhost:3000/api; do echo -n .; sleep 3; done; echo

# 4. Аккаунт + Website-инбокс (find-or-create), токены
SEED=$(docker compose exec -T rails bundle exec rails runner '
account = Account.first || AccountBuilder.new(account_name: "Demo", user_full_name: "Demo Admin", email: "'"$DEMO_EMAIL"'", user_password: "'"$DEMO_PASSWORD"'", super_admin: true, confirmed: true).perform && Account.first
account.custom_attributes = (account.custom_attributes || {}).merge("onboarding_step" => "true"); account.save!
user = User.find_by(email: "'"$DEMO_EMAIL"'") || User.first
user.update!(password: "'"$DEMO_PASSWORD"'", password_confirmation: "'"$DEMO_PASSWORD"'")
inbox = account.inboxes.find_by(name: "Website") || account.inboxes.create!(name: "Website", channel: Channel::WebWidget.create!(account: account, website_url: "'"$APP_URL"'"))
puts "SEED website_token=#{inbox.channel.website_token} api_token=#{user.access_token&.token || user.create_access_token!.token}"
' 2>&1 | grep "^SEED")
WEBSITE_TOKEN=$(echo "$SEED" | sed -n 's/.*website_token=\([^ ]*\).*/\1/p')
API_TOKEN=$(echo "$SEED" | sed -n 's/.*api_token=\([^ ]*\).*/\1/p')

# 5. Генерируем страницу сайта: BASE_URL = публичный адрес Chatwoot, свой токен
mkdir -p run
sed -e "s#http://localhost:3000#$APP_URL#g" -e "s/ВАШ_WEBSITE_TOKEN/$WEBSITE_TOKEN/" site/index.html > run/index.html

# 6. Поднимаем сайт и туннель на него
$COMPOSE up -d site cloudflared-site
echo "Поднимаем туннель на страницу сайта..."
SITE_URL=$(wait_for_url cloudflared-site) || { echo "Не удалось получить URL туннеля сайта"; exit 1; }

cat <<EOF

============================================================
  Chatwoot доступен публично.

  Приложение оператора : $APP_URL
      логин  : $DEMO_EMAIL
      пароль : $DEMO_PASSWORD

  Страница сайта с виджетом : $SITE_URL

  Website token : $WEBSITE_TOKEN
  API token     : $API_TOKEN

  Откройте $SITE_URL, напишите в виджете — сообщение появится
  у оператора на $APP_URL. Ссылки живут, пока запущены туннели.
============================================================
EOF
