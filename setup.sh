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

# 5. Получение сертификата через временный контейнер Caddy
echo "Получаем SSL сертификат..."
docker run --rm -it \
  -v $(pwd)/certs:/data/caddy/certificates/acme-v02.api.letsencrypt.org-directory/$DOMAIN \
  -v $(pwd)/caddy_data:/data \
  -p 80:80 -p 443:443 \
  caddy caddy tls $EMAIL --domain $DOMAIN

# Копируем сертификаты в удобное для dnsdist место (симлинки или копии)
# Caddy хранит их глубоко, поэтому вытащим их для удобства dnsdist
cp caddy_data/caddy/certificates/acme-v02.api.letsencrypt.org-directory/$DOMAIN/$DOMAIN.crt certs/fullchain.pem
cp caddy_data/caddy/certificates/acme-v02.api.letsencrypt.org-directory/$DOMAIN/$DOMAIN.key certs/privkey.pem

echo "Настройка завершена! Теперь можно запускать: docker-compose up -d"
