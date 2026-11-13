#!/bin/sh
# Подключение фида node-пакетов к OpenWRT: ключ подписи + строка фида + opkg update.
#
#   wget -qO- https://raw.githubusercontent.com/PriZZZrak/node-packages-build/main/setup-feed.sh | sh
#
# Или локально: sh setup-feed.sh
# Скрипт идемпотентен: повторный запуск не создаёт дублей в customfeeds.conf.

set -e

FEED_NAME="${FEED_NAME:-custom_node}"
FEED_URL="${FEED_URL:-https://prizzzrak.github.io/node-packages-build/packages/aarch64_cortex-a53/node}"
KEY_URL="${KEY_URL:-${FEED_URL%/*}/key-build.pub}"
OPKG_CONF="/etc/opkg/customfeeds.conf"

say() { echo "==> $*"; }
die() { echo "!!! $*" >&2; exit 1; }

# --- 0. архитектура ---------------------------------------------------------
need_arch="$(printf '%s' "$FEED_URL" | sed -n 's#.*/packages/\([^/]*\)/.*#\1#p')"
[ -n "$need_arch" ] || die "не удалось определить архитектуру из FEED_URL: $FEED_URL"

say "фид: $FEED_URL"
say "архитектура фида: $need_arch"

if command -v opkg >/dev/null 2>&1; then
	if opkg print-architecture | grep -qw "$need_arch"; then
		say "архитектура роутера подходит"
	else
		echo "доступные архитектуры:"
		opkg print-architecture
		die "фид собран под $need_arch — на этой арке пакеты не встанут"
	fi
else
	say "opkg не найден — похоже, это не OpenWRT, проверка архитектуры пропущена"
fi

command -v usign >/dev/null 2>&1 || die "нет usign (нужен для ключа подписи): opkg install usign"
command -v wget >/dev/null 2>&1 || die "нет wget (обычно есть в busybox): opkg install ca-bundle"

# --- 1. ключ подписи --------------------------------------------------------
keyfile="/tmp/key-build.pub"
say "скачиваю ключ: $KEY_URL"
wget -qO "$keyfile" "$KEY_URL" || die "не удалось скачать ключ (нет ca-bundle? opkg install ca-bundle)"

grep -q '^untrusted comment' "$keyfile" || die "файл ключа не похож на usign-ключ: $keyfile"

fingerprint="$(usign -F -p "$keyfile")"
[ -n "$fingerprint" ] || die "usign не смог вычислить отпечаток ключа"

mkdir -p /etc/opkg/keys
cp "$keyfile" "/etc/opkg/keys/$fingerprint"
chmod 644 "/etc/opkg/keys/$fingerprint"
rm -f "$keyfile"
say "ключ установлен: /etc/opkg/keys/$fingerprint"

# --- 2. строка фида ---------------------------------------------------------
touch "$OPKG_CONF"
if grep -qF "$FEED_URL" "$OPKG_CONF"; then
	say "фид уже прописан в $OPKG_CONF"
else
	# дописываем перевод строки, если файл оборван без него
	[ -s "$OPKG_CONF" ] && [ "$(tail -c 1 "$OPKG_CONF" | wc -l)" -eq 0 ] && echo >> "$OPKG_CONF"
	echo "src/gz $FEED_NAME $FEED_URL" >> "$OPKG_CONF"
	say "добавлено в $OPKG_CONF: src/gz $FEED_NAME $FEED_URL"
fi

# --- 3. обновление списков --------------------------------------------------
say "opkg update"
if ! opkg update; then
	echo "" >&2
	echo "opkg update упал. Частые причины:" >&2
	echo "  Signature check failed — ключ не установлен/не тот (см. /etc/opkg/keys/$fingerprint)" >&2
	echo "  TLS/сертификаты          — opkg install ca-bundle" >&2
	echo "  несколько строк $FEED_NAME в $OPKG_CONF — оставь одну" >&2
	exit 1
fi

list="/var/opkg-lists/$FEED_NAME"
if [ -f "$list" ]; then
	count="$(grep -c '^Package: ' "$list" 2>/dev/null || echo 0)"
	say "фид подключён, пакетов в списке: $count"
else
	say "фид подключён (список $list не найден — проверь вывод opkg update выше)"
fi

cat <<EOF

Готово. Что дальше:
  opkg list | grep '^node'      — что доступно
  opkg install node127          — Node.js 22 (18 МБ)
  opkg install node-npm         — npm/npx к нему

Убрать фид:
  sed -i '/$FEED_NAME/d' $OPKG_CONF
  rm -f /etc/opkg/keys/$fingerprint
  opkg update
EOF
