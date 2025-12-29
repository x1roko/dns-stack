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
mkdir -p certs caddy_data caddy_config templates

# 4. Генерация рабочих файлов из шаблонов
if [ ! -f templates/config.json.tmpl ] || [ ! -f templates/dnsdist.conf.tmpl ]; then
    echo "Ошибка: Шаблоны в папке templates/ не найдены!"
    exit 1
fi

sed "s/\${DOMAIN}/$DOMAIN/g" templates/config.json.tmpl > config.json
sed -e "s/\${DOMAIN}/$DOMAIN/g" -e "s/\${IPV4}/$IPV4/g" -e "s/\${IPV6}/$IPV6/g" templates/dnsdist.conf.tmpl > dnsdist.conf

# 5. Получение сертификата
echo "Запускаем процесс получения сертификата..."

# Запуск Caddy одной командой для получения сертификата
# Используем '--arg', чтобы прокинуть переменные
docker run --name caddy_setup -d \
  -p 80:80 -p 443:443 \
  -v $(pwd)/caddy_data:/data \
  caddy:latest caddy reverse-proxy --from $DOMAIN --to localhost:9999 --access-log

echo "Ожидаем 40 секунд (Caddy проходит ACME Challenge)..."
sleep 40

# Путь к сертификатам внутри caddy_data
CERT_PATH="caddy_data/caddy/certificates/acme-v02.api.letsencrypt.org-directory/$DOMAIN"

if [ -f "$CERT_PATH/$DOMAIN.crt" ]; then
    cp "$CERT_PATH/$DOMAIN.crt" certs/fullchain.pem
    cp "$CERT_PATH/$DOMAIN.key" certs/privkey.pem
    echo "✅ СЕРТИФИКАТЫ ПОЛУЧЕНЫ!"
else
    echo "❌ ОШИБКА: Сертификаты не появились."
    echo "--- ЛОГИ CADDY ---"
    docker logs caddy_setup
    echo "------------------"
fi

# Чистка
docker rm -f caddy_setup > /dev/null 2>&1

echo "Настройка завершена."
