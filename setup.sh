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
echo "Запускаем Caddy для получения сертификата..."

# Запускаем Caddy. Добавлена опция --email для регистрации в ACME
docker run --name caddy_setup -d \
  -p 80:80 -p 443:443 \
  -v $(pwd)/caddy_data:/data \
  caddy:latest caddy reverse-proxy --from "$DOMAIN" --to localhost:9999 --contact-email "$EMAIL"

echo "Ожидаем 40 секунд (Caddy проходит ACME Challenge)..."
sleep 40

# 6. Улучшенный поиск сертификатов
# Caddy хранит их глубоко в caddy_data/caddy/certificates/...
SEARCH_DIR="$(pwd)/caddy_data/caddy/certificates"

# Ищем файл .crt и .key для указанного домена
CRT_FILE=$(find "$SEARCH_DIR" -name "$DOMAIN.crt" | head -n 1)
KEY_FILE=$(find "$SEARCH_DIR" -name "$DOMAIN.key" | head -n 1)

if [ -n "$CRT_FILE" ] && [ -f "$CRT_FILE" ]; then
    cp "$CRT_FILE" certs/fullchain.pem
    cp "$KEY_FILE" certs/privkey.pem
    echo "✅ СЕРТИФИКАТЫ НАЙДЕНЫ И СКОПИРОВАНЫ В ./certs/"
else
    echo "❌ ОШИБКА: Сертификаты не найдены в $SEARCH_DIR"
    echo "--- ЛОГИ CADDY ---"
    docker logs caddy_setup --tail 20
    echo "------------------"
fi

# 7. Запуск основной инфраструктуры
# Если у вас есть docker-compose.yml, лучше запускать его здесь
echo "Запускаем стек через docker-compose..."
docker rm -f caddy_setup > /dev/null 2>&1
docker-compose up -d

echo "Настройка завершена."
