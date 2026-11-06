#!/bin/bash

set -e

# Путь к сертификату
CERT="/home/user/ca.crt"

# Установка необходимых пакетов
sudo apt update
sudo apt install -y ca-certificates libnss3-tools

# Установка сертификата в системное хранилище
sudo install -m 0644 "$CERT" /usr/local/share/ca-certificates/local-network-ca.crt

# Обновление системного хранилища
sudo update-ca-certificates

# Создание хранилища NSS для Chromium
mkdir -p ~/.pki/nssdb

# Создание базы сертификатов, если её ещё нет
if [ ! -f ~/.pki/nssdb/cert9.db ]; then
    certutil -N -d sql:$HOME/.pki/nssdb --empty-password
fi

# Удаление предыдущей записи, если она существует
certutil -D \
-d sql:$HOME/.pki/nssdb \
-n "Local Network CA" 2>/dev/null || true

# Импорт сертификата в Chromium
certutil -A \
-d sql:$HOME/.pki/nssdb \
-n "Local Network CA" \
-t "C,," \
-i "$CERT"

echo "CA certificate successfully installed!"