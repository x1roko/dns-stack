#!/bin/bash

echo "--- DNS Stack Setup ---"

# 1. Запрос данных
read -p "Введите ваш домен (напр. example.com): " DOMAIN
read -p "Введите ваш Email (для SSL): " EMAIL

# 2. Автоматическое определение IP
IPV4=$(curl -s https://api.ipify.org)
IPV6=$(curl -s https://api6.ipify.org || echo "::1")

echo "Определен IPv4: $IPV4"
echo "Определен IPv6: $IPV6"

# 3. Создание директорий
mkdir -p certs caddy_data caddy_config

# 4. Генерация рабочих файлов из шаблонов
sed "s/\${DOMAIN}/$DOMAIN/g" templates/config.json.tmpl > config.json
sed -e "s/\${DOMAIN}/$DOMAIN/g" -e "s/\${IPV4}/$IPV4/g" -e "s/\${IPV6}/$IPV6/g" templates/dnsdist.conf.tmpl > dnsdist.conf

# 5. Получение сертификата через Caddy JSON API
echo "Получаем SSL сертификат..."

# Создаем временный Caddyfile для получения сертификата
cat <<EOF > Caddyfile.temp
{
    email $EMAIL
}
$DOMAIN {
    tls {
        on_demand
    }
    respond "OK"
}
EOF

# Запускаем Caddy на короткое время, чтобы он выпустил сертификат
docker run --rm -d \
  --name caddy_gen \
  -v $(pwd)/Caddyfile.temp:/etc/caddy/Caddyfile \
  -v $(pwd)/caddy_data:/data \
  -p 80:80 -p 443:443 \
  caddy:latest

echo "Ожидаем выпуска сертификата (30 секунд)..."
sleep 30

# Копируем сертификаты
# В новых версиях Caddy использует расширение .crt и .key
BASE_PATH="caddy_data/caddy/certificates/acme-v02.api.letsencrypt.org-directory/$DOMAIN"

if [ -f "$BASE_PATH/$DOMAIN.crt" ]; then
    cp "$BASE_PATH/$DOMAIN.crt" certs/fullchain.pem
    cp "$BASE_PATH/$DOMAIN.key" certs/privkey.pem
    echo "Сертификаты успешно скопированы."
else
    echo "Ошибка: Сертификаты не найдены. Проверьте логи: docker logs caddy_gen"
fi

# Останавливаем временный контейнер и удаляем временный файл
docker stop caddy_gen
rm Caddyfile.temp

echo "Настройка завершена! Теперь можно запускать: docker-compose up -d"
