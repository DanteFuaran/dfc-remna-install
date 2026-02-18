#!/bin/bash
#
# Собирает модули из src/ в единый install_remnawave.sh
# Использование: ./build.sh
#

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC_DIR="$SCRIPT_DIR/src"
OUTPUT="$SCRIPT_DIR/install_remnawave.sh"

# Порядок файлов для конкатенации
MODULES=(
    "01_header.sh"
    "02_install.sh"
    "03_manage.sh"
    "04_extra.sh"
    "05_warp.sh"
    "06_main.sh"
)

echo "🔨 Сборка install_remnawave.sh..."

# Проверяем наличие всех модулей
for mod in "${MODULES[@]}"; do
    if [ ! -f "$SRC_DIR/$mod" ]; then
        echo "❌ Не найден модуль: src/$mod"
        exit 1
    fi
done

# Конкатенируем
> "$OUTPUT"
for mod in "${MODULES[@]}"; do
    cat "$SRC_DIR/$mod" >> "$OUTPUT"
done

chmod +x "$OUTPUT"

# Считаем строки
total=$(wc -l < "$OUTPUT")
echo "✅ Собрано: install_remnawave.sh ($total строк)"

# Проверяем синтаксис
if bash -n "$OUTPUT" 2>/dev/null; then
    echo "✅ Синтаксис: OK"
else
    echo "❌ Ошибка синтаксиса!"
    bash -n "$OUTPUT"
    exit 1
fi
