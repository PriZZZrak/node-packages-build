#!/bin/sh
# Установка ключа подписи для custom_node фида на OpenWRT
# Запускать на роутере: sh setup-feed.sh
#
# ВАЖНО: fingerprint берётся из Packages.sig, а не из usign -F -p,
# потому что usign из SDK 24.10 считает fingerprint при подписи
# как seed[24:32], а usign -F -p показывает stored_keyid + pubkey[0:4].
# Эти значения НЕ совпадают для обычного Ed25519 ключа.
# opkg ищет ключ по fingerprint из Packages.sig, поэтому берём его оттуда.

URL="https://prizzzrak.github.io/node-packages-build/packages/aarch64_cortex-a53"

echo "=== Получение Packages.sig ==="
wget -qO /tmp/Packages.sig "$URL/node/Packages.sig"

echo "=== Извлечение fingerprint из подписи ==="
FINGERPRINT=$(head -1 /tmp/Packages.sig | grep -oP 'key \K[0-9a-f]+')
echo "Fingerprint (из Packages.sig): $FINGERPRINT"

echo "=== Получение публичного ключа ==="
wget -qO "/etc/opkg/keys/$FINGERPRINT" "$URL/key-build.pub"

echo "=== Очистка ==="
rm -f /tmp/Packages.sig

echo "=== Проверка ==="
opkg update
