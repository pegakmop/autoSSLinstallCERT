#!/bin/bash

# Получаем имя текущего скрипта
SCRIPT_NAME=$(basename "$0")

# Если скрипт не исполняем, делаем его исполняемым
[ ! -x "$0" ] && chmod +x "$0"

# Пути к сертификатам
CERT_KEY="/etc/ssl/private/pegakmop.key"
CERT_CRT="/etc/ssl/certs/pegakmop.crt"
LE_CERT_KEY=""
LE_CERT_CRT=""
DOMAIN=""
PUBLIC_IP=""

# Получаем публичный IP
get_public_ip() {
    curl -s ifconfig.me
}

# Автоматически определяем домен из сертификатов Let's Encrypt
get_certbot_domain() {
    sudo certbot certificates | grep -oP "(?<=Domains: ).*" | head -n 1
}

# Запрашиваем у пользователя: использовать автоматический IP/домен или ввод вручную
read -p "1 - Автоматически получить IP или домен сервера
2 - Ввести вручную
Выберите (1/2): " AUTO_CHOICE

if [ "$AUTO_CHOICE" -eq 1 ]; then
    PUBLIC_IP=$(get_public_ip)
    DOMAIN=$(get_certbot_domain)
    echo -e "\nОпределено автоматически:"
    echo -e "IP: $PUBLIC_IP"
    echo -e "Домен: ${DOMAIN:-Отсутствует}"
    
    # Запросить привязку домена
    read -p "Вы хотите привязать домен к этому IP (y/n)? " CHOICE
    if [ "$CHOICE" == "y" ]; then
        read -p "Введите домен: " DOMAIN
        PUBLIC_IP=""
    fi
elif [ "$AUTO_CHOICE" -eq 2 ]; then
    read -p "Введите IP или домен: " USER_INPUT
    if [[ "$USER_INPUT" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        PUBLIC_IP=$USER_INPUT
        DOMAIN=""
    else
        DOMAIN=$USER_INPUT
        PUBLIC_IP=""
    fi
else
    echo "Ошибка: неверный выбор."
    exit 1
fi

# Создание самоподписного сертификата
create_self_signed_cert() {
    sudo openssl req -x509 -nodes -days 3650 -newkey rsa:2048 \
    -keyout "$CERT_KEY" -out "$CERT_CRT" \
    -subj "/C=RU/ST=Region/L=City/O=Org/CN=${DOMAIN:-$PUBLIC_IP}"
    sudo chmod 600 "$CERT_KEY"
}

# Создание сертификата Let's Encrypt
create_letsencrypt_cert() {
    [ -z "$DOMAIN" ] && read -p "Введите домен для Let's Encrypt: " DOMAIN
    sudo certbot certonly --standalone -d "$DOMAIN"
    LE_CERT_KEY="/etc/letsencrypt/live/$DOMAIN/privkey.pem"
    LE_CERT_CRT="/etc/letsencrypt/live/$DOMAIN/cert.pem"
}

# Продление сертификата Let's Encrypt
renew_letsencrypt_cert() {
    sudo certbot renew
}

# Продление самоподписного сертификата
renew_self_signed_cert() {
    create_self_signed_cert
}

# Выбор действия
echo -e "\n1. Создать/продлить самоподписной сертификат"
echo -e "2. Создать/продлить сертификат Let's Encrypt"
read -p "Выберите (1/2): " CHOICE

# Проверка наличия сертификатов
if [ "$CHOICE" -eq 1 ]; then
    if [ -f "$CERT_KEY" ] && [ -f "$CERT_CRT" ]; then
        EXPIRY_DATE=$(openssl x509 -in "$CERT_CRT" -noout -enddate | sed "s/.*=\(.*\)/\1/")
        CURRENT_DATE=$(date -u "+%Y%m%d%H%M%S")
        EXPIRY_TIMESTAMP=$(date -d "$EXPIRY_DATE" "+%Y%m%d%H%M%S")
        if [ "$CURRENT_DATE" -gt "$EXPIRY_TIMESTAMP" ]; then
            renew_self_signed_cert
        else
            echo -e "\nСамоподписной сертификат ещё действителен."
        fi
    else
        create_self_signed_cert
    fi
elif [ "$CHOICE" -eq 2 ]; then
    if [ -f "$LE_CERT_KEY" ] && [ -f "$LE_CERT_CRT" ]; then
        renew_letsencrypt_cert
    else
        create_letsencrypt_cert
    fi
else
    echo -e "\nНеверный выбор."
    exit 1
fi

# Выводим путь к сертификатам
echo -e "\n🔑 Сертификат и ключ:"
if [ -n "$LE_CERT_KEY" ]; then
    echo -e "Let's Encrypt\nКлюч: $LE_CERT_KEY\nСертификат: $LE_CERT_CRT"
else
    echo -e "Самоподписной\nКлюч: $CERT_KEY\nСертификат: $CERT_CRT"
fi

echo -e "\n🎉 Всё готово! 🎉"
