#!/bin/sh
# Обновляет манифест бакета Scoop под вышедшую версию.
#
# Зачем скрипт, а не правка руками: манифест держит ТРИ вещи, которые обязаны
# совпадать между собой, — `version`, `url` с этой версией внутри и `hash`.
# Забытая из них даёт не «грязный файл», а установку, которая падает на
# проверке контрольной суммы у пользователя. Плюс `hash` в разных релизах
# разный, и взять его руками — значит скопировать его откуда-то вслепую.
#
#   sh packaging/update_scoop_manifest.sh 0.1.8
#
# Хеш берётся из `.zip.sha256` рядом с архивом релиза: релизный пайплайн
# кладёт туда ровно ту сумму, которую посчитает `sha256sum` по архиву, и
# источник не может разойтись с тем, что лежит в Releases.
#
# Exit codes: 0 updated, 1 bad arguments, 2 release asset missing,
#             3 manifest not found.
set -eu

VERSION=${1:-}
BUCKET=${BUCKET:-https://github.com/alex37529/voxspica-scoop}
BASE="https://github.com/alex37529/voxspica/releases/download/v$VERSION"
MANIFEST="bucket/voxspica.json"

[ -n "$VERSION" ] || {
    echo "usage: sh $0 <version>" >&2
    exit 1
}
[ -f "$MANIFEST" ] || {
    echo "нет манифеста $MANIFEST — запускать из клона $BUCKET" >&2
    exit 3
}

HASH_URL="$BASE/VoxSpica-$VERSION-win64.zip.sha256"
HASH=$(curl -fsSL "$HASH_URL" 2>/dev/null | tr -d '[:space:]' | tr 'a-f' 'A-F')
if [ -z "$HASH" ]; then
    echo "не скачался хеш: $HASH_URL" >&2
    echo "релиз v$VERSION ещё не опубликован или в нём нет .zip.sha256" >&2
    exit 2
fi
case "$HASH" in
    *[!0-9A-F]*) echo "хеш выглядит не как SHA256: $HASH" >&2; exit 2 ;;
esac
if [ "${#HASH}" -ne 64 ]; then
    echo "в .zip.sha256 ожидалась одна сумма в 64 символа, пришло ${#HASH}" >&2
    exit 2
fi

echo "версия:  $VERSION"
echo "хеш:     $HASH"
echo "url:     $BASE/VoxSpica-$VERSION-win64.zip"

python3 - "$MANIFEST" "$VERSION" "$HASH" <<'PY'
import json, re, sys

path, version, digest = sys.argv[1], sys.argv[2], sys.argv[3]
text = open(path, encoding="utf-8").read()

# Читаем через json, чтобы не потерять форматирование при записи назад:
# манифест Scoop читают глазами при ревью, и переформатированный diff
# засоряет историю бакета.
data = json.loads(text)

old_version = data.get("version")
data["version"] = version
# url и hash обязаны уехать вместе с версией: в шаблоне автообновления
# `$version` подставляется checkver'ом, а в самом манифесте стоит
# развёрнутая ссылка на конкретный тег.
data["url"] = re.sub(r"/v[^/]+/VoxSpica-[^/]+-win64\.zip$",
                     f"/v{version}/VoxSpica-{version}-win64.zip", data["url"])
data["hash"] = digest

open(path, "w", encoding="utf-8").write(
    json.dumps(data, indent=4, ensure_ascii=False) + "\n"
)
print(f"было:  version {old_version}")
print(f"стало: version {version}")
PY

echo
echo "Проверьте перед пушем:"
echo "  git diff $MANIFEST"
echo "И сам файл: $MANIFEST"