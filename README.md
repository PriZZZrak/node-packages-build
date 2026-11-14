# node-packages-build

Собственный opkg-фид с пакетами Node.js, собранными из фида
[nxhack/openwrt-node-packages](https://github.com/nxhack/openwrt-node-packages) под OpenWRT 24.10.

| параметр | значение |
|---|---|
| URL фида | `https://prizzzrak.github.io/node-packages-build/packages/aarch64_cortex-a53/node` |
| Архитектура | `aarch64_cortex-a53` (mediatek/filogic: MT7981, MT7986 и т.п.) |
| Node.js | `node127` 22.23.4 (LTS, предоставляет виртуальный `node`) |
| Пакетов | 142, суммарно ~381 МБ ipk |
| Подпись | `usign`, ключ `5b00e6cdb3a5881a` |
| Сборка | GitHub Actions, `.github/workflows/build.yml` |
| Запуск | только вручную: Actions → **Build OpenWRT Node Packages** → Run workflow |

---

## 1. Подключение фида к роутеру

### 1.1. Проверить архитектуру

Фиды в opkg привязаны к архитектуре — на другой арке пакеты не встанут:

```sh
opkg print-architecture
```

Нужна строка `aarch64_cortex-a53` (это MT7981/MT7986: Xiaomi AX3000T, Redmi AX6000,
RouteRich AX3000, GL-MT3000 и подобные). Если её нет — фид не подойдёт, нужна сборка
под свой target (см. §4).

### 1.2. Быстрый способ (одна команда)

Скрипт сам ставит ключ подписи, добавляет фид и обновляет списки:

```sh
wget -qO- https://raw.githubusercontent.com/PriZZZrak/node-packages-build/main/setup-feed.sh | sh
```

Он идемпотентен: повторный запуск не создаёт дублей в `/etc/opkg/customfeeds.conf`.

### 1.3. Вручную (три шага)

**1) Ключ подписи.** `usign` есть в стоковой прошивке; если нет — `opkg install usign`.

```sh
cd /tmp
wget -qO key-build.pub \
  https://prizzzrak.github.io/node-packages-build/packages/aarch64_cortex-a53/key-build.pub
FP=$(usign -F -p key-build.pub)
mkdir -p /etc/opkg/keys
cp key-build.pub "/etc/opkg/keys/$FP"
echo "ключ: $FP"
```

**2) Строка фида** в `/etc/opkg/customfeeds.conf`:

```sh
echo 'src/gz custom_node https://prizzzrak.github.io/node-packages-build/packages/aarch64_cortex-a53/node' \
  >> /etc/opkg/customfeeds.conf
```

**3) Обновить списки:**

```sh
opkg update
```

В выводе должно появиться:

```
Downloading https://prizzzrak.github.io/.../node/Packages.gz
Updated list of available packages in /var/opkg-lists/custom_node
```

Если вместо этого `Signature check failed` — не встал ключ (шаг 1) или он битый.
Если `wget: not an http or ftp url` / TLS-ошибка — нет `ca-bundle` (`opkg install ca-bundle`).

### 1.4. Установка пакетов

```sh
opkg list | grep '^node'          # что доступно
opkg install node127             # сам рантайм (18 МБ, ~54 МБ после установки)
opkg install node-npm node-yarn  # npm/npx и yarn
```

`node` — это **виртуальное** имя: его предоставляет пакет `node127`, поэтому ставь по
фактическому имени. Зависимости вида `Depends: libc, node127` разрешаются сами.

Модули ставятся так же: `opkg install node-red`, `opkg install node-homebridge-hue` и т.д.
Пакеты, которым нужен нативный C++ аддон, могут отсутствовать в фиде — сборка таких
пакетов падает на кросс-компиляции `node-gyp` (см. §6).

### 1.5. Пережить sysupgrade

Файлы фида лежат в `/etc`, но перечень сохраняемого при обновлении прошивки зависит от сборки.
Проверь:

```sh
grep -E 'opkg' /lib/upgrade/keep.d/base
```

Если `/etc/opkg/customfeeds.conf` или `/etc/opkg/keys` там нет — добавь в `/etc/sysupgrade.conf`:

```
/etc/opkg/customfeeds.conf
/etc/opkg/keys/
```

После обновления прошивки списки всё равно надо обновить один раз: `opkg update`
(сами списки лежат в `/tmp` и не сохраняются).

### 1.6. Убрать фид

```sh
sed -i '/custom_node/d' /etc/opkg/customfeeds.conf
rm -f /etc/opkg/keys/5b00e6cdb3a5881a*
opkg update
```

Уже установленные пакеты останутся; удалять их — `opkg remove <имя>`.

---

## 2. Что в фиде

142 пакета. Основное:

| пакет | что это |
|---|---|
| `node127` | Node.js 22.23.4 (LTS), `Provides: node`, `ABIVersion: 127` |
| `node-npm`, `node-yarn` | npm/npx 22.23.4, yarn 1.22.22 |
| `node-red`, `node-red-contrib-*` | Node-RED и контрибы |
| `node-homebridge-*` | Homebridge и плагины (hue, miot, mqttthing, camera-ui, …) |
| `node-pty`, `node-serialport`, `node-sqlite3`, … | модули с нативными аддонами |

Самые крупные ipk: `node-homebridge-hue` 28 МБ, `node-homebridge-mqttthing` 28 МБ,
`node-camera.ui` 20 МБ, `node-pty` 19 МБ, `node-red` 18.5 МБ.

Не публикуются фиды `base`, `packages`, `luci`, `routing`, `telephony` — они уже есть в
официальном репозитории OpenWRT, и дублировать их в своём фиде опасно.

---

## 3. Как это собирается

Один прогон всех пакетов не влезает в лимит GitHub в 6 часов на job, поэтому сборка
разделена:

```
plan (1 мин) ── build-node   node + node-npm + node-yarn            ~1–1.5 ч
                     │  артефакт node-state: staging_dir + штампы сборки
                     ├─ build-modules  shard 1..N (только модули)   ~1–1.5 ч
                     └─ deploy         merge → Packages(.gz/.sig) → gh-pages/packages
```

* **plan** — читает `sha256sums` релиза, находит имя SDK и его sha256, выбирает ветку
  node-фида и раскладывает шарды.
* **build-node** — самый дорогой кусок (сборка V8). Собирает **обе** сборки Node:
  target (`node`, `node-npm`, `node-yarn`) и **host** (`node/host`) — host-вариант нужен
  шардам, потому что у 140 из 150 пакетов фида `PKG_BUILD_DEPENDS:=node/host`.
  Пакет `node-npm` объявлен внутри `node/Makefile`, поэтому собирается вместе с `node`.
  Результат кэшируется между прогонами
  (ключ: SDK + таргет + коммит node-фида) и упаковывается в артефакт `node-state`:
  `staging_dir` (там же `hostpkg/bin/node`), `build_dir/hostpkg` (штампы host-сборки),
  `build_dir/target-*/node-*` (штампы target-сборки) и ipk.
  Сборка идёт с `CONFIG_AUTOREMOVE=y`: от него зависит способ подсчёта штампа
  `.prepared` (по содержимому, а не по mtime), иначе перенесённое состояние не
  признаётся собранным и Node пересобирается заново.
  Важно: при сборке пакетов host-зависимости живут не в `build_dir/host`, а в
  `build_dir/hostpkg` (`rules.mk: BUILD_DIR_HOST`), и ставятся в `staging_dir/hostpkg`.
  Повторный прогон без изменений в Node начинается с восстановления этого состояния —
  сборки V8 нет вообще.
* **build-modules** — ждут `build-node`, распаковывают `node-state` в свой SDK и собирают
  только модули. Без этого каждый шард собирал бы Node сам: у 140 из 150 пакетов фида
  стоит `PKG_BUILD_DEPENDS:=node/host`. Сборка идёт **одним** вызовом `make -k` на шард —
  повторные вызовы в той же песочнице заставляют OpenWrt перегенерировать `.config`
  и запускать `clean-build` (полная пересборка node/openssl).
* **deploy** — скачивает все ipk, кладёт их в `bin/packages/<arch>/node`, генерирует
  `Packages`/`Packages.gz`, подписывает `usign`, проверяет подпись, публикует в `gh-pages`
  и делает smoke-test опубликованного `Packages`.

Ветка `gh-pages` публикуется с `force_orphan` — каждый прогон это один коммит с текущим
состоянием фида, история не растёт.

---

## 4. Запуск сборки

Actions → **Build OpenWRT Node Packages** → **Run workflow**.

| input | по умолчанию | смысл |
|---|---|---|
| `version` | `24.10.8` | релиз OpenWRT, из которого берётся SDK |
| `target` | `mediatek/filogic` | board/subtarget |
| `arch` | `aarch64_cortex-a53` | архитектура пакетов в фиде |
| `shards` | `3` | на сколько джоб делить «остальные» пакеты |
| `artifacts_run` | пусто | id прогона, из которого взять готовые ipk |

`artifacts_run` — режим «только публикация»: сборка пропускается, deploy качает ipk
из указанного прогона (артефакты живут 3 дня), генерирует индекс, подписывает и
публикует. Полезно, если упал только деплой или нужно переиздать фид без пересборки.

Если modules-шарды подбираются к 4–5 часам — увеличь `shards`: теперь, когда Node
собирается один раз, время стены ≈ время `build-node` + время самого шарда, поэтому
`3`–`4` шарда дают почти линейный выигрыш. Файл менять не нужно — это input запуска.

Ветка node-фида выводится из `version` автоматически: `24.10.8` → `openwrt-24.10`
(у nxhack своя ветка на каждый релиз OpenWRT; `master` тянет Node 26 и пакеты, которым нужен
более свежий OpenWRT). Если такой ветки нет — сборка предупредит и возьмёт `master`.

Сборка под другую арку: поменяй `target`/`arch` в inputs (например
`mediatek/mt7622` + `aarch64_cortex-a53`, или `ramips/mt7621` + `mipsel_24kc`).
URL фида тогда изменится — `.../packages/<arch>/node`.

Проверка перед деплоем: если пакетов меньше `MIN_PACKAGES` (100), публикация блокируется —
чтобы упавшая сборка не затёрла рабочий фид пустым индексом.

---

## 5. Подпись пакетов

`opkg` проверяет подпись индекса, если в `/etc/opkg.conf` стоит `option check_signature 1`
(по умолчанию в OpenWRT так и есть).

* Публичный ключ лежит в репозитории (`key-build.pub`) и копируется в фид:
  `.../packages/aarch64_cortex-a53/key-build.pub`.
* Приватный ключ хранится **только** в секрете `OPKG_SIGN_KEY` (base64 от usign-ключа),
  в репозиторий не попадает (`.gitignore`: `key-build`, `key-build.secret.b64`).
* `deploy` сверяет отпечаток приватного ключа с `key-build.pub`, валидирует
  `Packages.sig` через `usign -V` и падает, если подпись не сошлась. Неподписанный
  фид не публикуется.

Ротация ключа (сломает установку у всех, кто уже подключил фид — им нужно заново
импортировать ключ по §1.3):

```sh
usign -G -s key-build -p key-build.pub -c "node-packages-build feed"
base64 -w0 key-build > key-build.secret.b64   # содержимое → секрет OPKG_SIGN_KEY
git add key-build.pub && git commit -m "rotate feed signing key"
```

---

## 6. Артефакты, кэши и диагностика

| артефакт | содержимое | хранение |
|---|---|---|
| `node-state` | `staging_dir` + штампы сборки Node (передаётся в шарды) | 3 дня |
| `ipk-node`, `ipk-shard-N` | собранные ipk (передаются в deploy) | 3 дня |
| `logs-node`, `logs-shard-N` | `build.log`, `failures.txt`, `shard-list.txt`, `sdk/logs/` | 14 дней |

Кэшируются только SDK-тарболл (по sha256), `sdk/dl` и состояние собранного Node
(`node-state-<sdk>-<коммит фида>`). Сам SDK каждый раз распаковывается заново, поэтому
«замороженного» состояния сборки не бывает. `sdk/dl` имеет статический ключ — если нужно
принудительно перекачать исходники, поменяй `v1` в ключе.

Пересобрать Node принудительно: удалить кэш `node-state-*` в Actions → Caches (или
дождаться нового коммита в node-фиде — ключ сменится сам).

Если пакета нет в фиде:

1. посмотри `$GITHUB_STEP_SUMMARY` прогона — там списки упавших пакетов по шардам;
2. скачай `logs-shard-N` и открой `log-<пакет>.txt`;
3. типовые причины: `node-gyp` (нативная сборка под cross), `@BROKEN` в апстриме,
   несовместимая с Node 22 версия модуля.

---

## 7. Известные ограничения

* Только `aarch64_cortex-a53` — другие арки не собираются (см. §4).
* Два пакета зависят от виртуального `nodejs`, которого в фиде никто не предоставляет:
  `node-homekit2mqtt`, `node-red-contrib-homekit-bridged`. Они индексируются, но не
  установятся, пока апстрим не поправит `DEPENDS`.
* `node`/`node127` ~54 МБ в распакованном виде — на роутере с 16 МБ flash места нет,
  нужен USB-накопитель или extroot.
* Фиды `base`, `packages`, `luci`, … из фида удалены намеренно: их место — официальный
  репозиторий OpenWRT.
* Сборка не привязана к коммиту апстрима: node-фид забирается из ветки релиза
  (`openwrt-24.10`), поэтому версии пакетов меняются от прогона к прогону.
  `Check Upstream Updates` следит за той же веткой и сам запускает сборку при новых коммитах.
* GitHub Pages: сайт весит ~381 МБ и отдаётся только по прямым путям — корень
  `/node-packages-build/` отдаёт 404, это нормально (индекса нет, он не нужен).
