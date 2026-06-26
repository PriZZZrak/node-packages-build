#!/bin/sh
# Установка ключа подписи для custom_node фида на OpenWRT
# Запускать на роутере: sh setup-feed.sh

URL="https://prizzzrak.github.io/node-packages-build/packages/aarch64_cortex-a53"

echo "=== Получение публичного ключа ==="
wget -qO /tmp/key-build.pub "$URL/key-build.pub"

echo "=== Вычисление fingerprint ==="
FINGERPRINT=$(usign -F -p /tmp/key-build.pub)
echo "Fingerprint: $FINGERPRINT"

echo "=== Установка ключа ==="
cp /tmp/key-build.pub "/etc/opkg/keys/$FINGERPRINT"
rm /tmp/key-build.pub

echo "=== Проверка ==="
opkg update
