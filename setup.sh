#!/bin/bash

echo "--- DNS Stack Setup ---"

# 1. Запрос данных
read -p "Введите ваш домен (напр. example.com): " DOMAIN
read -p "Введите ваш Email (для SSL): " EMAIL

# 2. Автоматическое определение IP
IPV4=$(curl -s https://api.ipify.org)
IPV6=$(curl -s https://api6.ipify.org || echo "::1")

# 3. Создание директорий
mkdir -p certs caddy_data caddy_config templates

# 4. Исправление шаблона и генерация файлов
sed -i 's/"proxy_protocol": "v0"/"proxy_protocol": ""/g' templates/config.json.tmpl
sed "s/\${DOMAIN}/$DOMAIN/g" templates/config.json.tmpl > config.json
sed -e "s/\${DOMAIN}/$DOMAIN/g" -e "s/\${IPV4}/$IPV4/g" -e "s/\${IPV6}/$IPV6/g" templates/dnsdist.conf.tmpl > dnsdist.conf

# 5. Получение сертификата
echo "Запускаем Caddy для получения сертификата..."
docker rm -f caddy_setup > /dev/null 2>&1
docker run --name caddy_setup -d \
  -p 80:80 -p 443:443 \
  -v $(pwd)/caddy_data:/data \
  caddy:latest caddy reverse-proxy --from "$DOMAIN" --to localhost:9999 --email "$EMAIL"

# 6. Умное ожидание сертификатов (вместо sleep 40)
echo "Ожидаем получение сертификата от Let's Encrypt..."
SEARCH_DIR="$(pwd)/caddy_data/caddy/certificates"
MAX_RETRIES=60
COUNTER=0
CRT_FILE=""

while [ $COUNTER -lt $MAX_RETRIES ]; do
    # Пытаемся найти файл через sudo
    CRT_FILE=$(sudo find "$SEARCH_DIR" -name "$DOMAIN.crt" | head -n 1)
    
    if [ -n "$CRT_FILE" ]; then
        echo "✅ Сертификат получен за $COUNTER сек.!"
        break
    fi
    
    # Каждые 5 секунд выводим точку для визуализации
    if (( $COUNTER % 5 == 0 )); then echo -n "."; fi
    
    sleep 1
    ((COUNTER++))
done

echo "" # Перенос строки после точек

# 7. Копирование и права
if [ -n "$CRT_FILE" ]; then
    KEY_FILE=$(sudo find "$SEARCH_DIR" -name "$DOMAIN.key" | head -n 1)
    sudo cp "$CRT_FILE" certs/fullchain.pem
    sudo cp "$KEY_FILE" certs/privkey.pem
    sudo chown $USER:$USER certs/fullchain.pem certs/privkey.pem
    chmod 644 certs/*.pem
    chmod 755 certs/
    echo "✅ Сертификаты скопированы."
else
    echo "❌ ОШИБКА: Тайм-аут ожидания сертификата (60 сек)."
    echo "--- ЛОГИ CADDY ---"
    docker logs caddy_setup --tail 20
    docker rm -f caddy_setup > /dev/null 2>&1
    exit 1
fi

# 8. Перезапуск стека
docker rm -f caddy_setup > /dev/null 2>&1
echo "Запускаем основной стек..."
docker-compose down && docker-compose up -d

echo "Настройка завершена."
