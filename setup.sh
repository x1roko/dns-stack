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

# 4. Генерация рабочих файлов
if [ ! -f templates/config.json.tmpl ] || [ ! -f templates/dnsdist.conf.tmpl ]; then
    echo "Ошибка: Шаблоны не найдены!"
    exit 1
fi

sed "s/\${DOMAIN}/$DOMAIN/g" templates/config.json.tmpl > config.json
sed -e "s/\${DOMAIN}/$DOMAIN/g" -e "s/\${IPV4}/$IPV4/g" -e "s/\${IPV6}/$IPV6/g" templates/dnsdist.conf.tmpl > dnsdist.conf

# 5. Получение сертификата
echo "Запускаем Caddy для получения сертификата..."
docker run --name caddy_setup -d \
  -p 80:80 -p 443:443 \
  -v $(pwd)/caddy_data:/data \
  caddy:latest caddy reverse-proxy --from "$DOMAIN" --to localhost:9999 --email "$EMAIL"

echo "Ожидаем 40 секунд..."
sleep 40

# 6. Копирование сертификатов с использованием sudo (из-за прав Docker)
SEARCH_DIR="$(pwd)/caddy_data/caddy/certificates"
# Используем sudo для поиска, так как файлы принадлежат root
CRT_FILE=$(sudo find "$SEARCH_DIR" -name "$DOMAIN.crt" | head -n 1)
KEY_FILE=$(sudo find "$SEARCH_DIR" -name "$DOMAIN.key" | head -n 1)

if [ -n "$CRT_FILE" ]; then
    sudo cp "$CRT_FILE" certs/fullchain.pem
    sudo cp "$KEY_FILE" certs/privkey.pem
    # Меняем владельца на текущего пользователя, чтобы dnsdist мог их прочитать
    sudo chown $USER:$USER certs/*.pem
    echo "✅ СЕРТИФИКАТЫ ПОЛУЧЕНЫ И СКОПИРОВАНЫ."
else
    echo "❌ ОШИБКА: Сертификаты не найдены."
    docker logs caddy_setup --tail 10
fi

# 7. Остановка временного контейнера и запуск основного стека
docker rm -f caddy_setup > /dev/null 2>&1

echo "Запускаем основной стек..."
docker-compose up -d

echo "Настройка завершена."
