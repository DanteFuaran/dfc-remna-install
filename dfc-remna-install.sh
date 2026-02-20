#!/bin/bash
# ═══════════════════════════════════════════════════════════
#   DFC REMNA-INSTALL — Установщик Remnawave VPN Panel
#   https://github.com/DanteFuaran/dfc-remna-install
# ═══════════════════════════════════════════════════════════

_INSTALL_DIR="/usr/local/dfc-remna-install"
_REPO="DanteFuaran/dfc-remna-install"
_BRANCH="main"

# Bootstrap: при запуске через bash <(curl ...) скрипт читается из /dev/fd/N
# В этом случае рядом нет lib/ — скачиваем архив и переключаемся на установленную копию
_SELF="${BASH_SOURCE[0]}"
if [[ "$_SELF" == /dev/fd/* ]] || [[ "$_SELF" == /proc/* ]]; then
    # Если скрипт уже установлен — запускаем существующую копию без перезаписи
    if [ -f "${_INSTALL_DIR}/dfc-remna-install.sh" ] && [ -d "${_INSTALL_DIR}/lib" ]; then
        export REMNA_INSTALLED_RUN=1
        exec "${_INSTALL_DIR}/dfc-remna-install.sh"
    fi

    # Первичная установка — скачиваем архив
    echo "⏳ Загрузка скрипта..."
    mkdir -p "${_INSTALL_DIR}" || { echo "✖ Ошибка создания ${_INSTALL_DIR}"; exit 1; }
    
    _TMP_FILE=$(mktemp)
    if ! curl -fsSL "https://github.com/${_REPO}/archive/refs/heads/${_BRANCH}.tar.gz" -o "${_TMP_FILE}" 2>/dev/null; then
        echo "✖ Ошибка загрузки архива. Проверьте соединение с интернетом."
        rm -f "${_TMP_FILE}"
        exit 1
    fi
    
    if ! tar -xz -C "${_INSTALL_DIR}" --strip-components=1 -f "${_TMP_FILE}" 2>/dev/null; then
        echo "✖ Ошибка распаковки архива."
        rm -f "${_TMP_FILE}"
        exit 1
    fi
    rm -f "${_TMP_FILE}"
    
    if [ ! -f "${_INSTALL_DIR}/dfc-remna-install.sh" ]; then
        echo "✖ Файл скрипта не найден. Архив повреждён?"
        exit 1
    fi
    chmod +x "${_INSTALL_DIR}/dfc-remna-install.sh"
    mkdir -p /usr/local/bin
    ln -sf "${_INSTALL_DIR}/dfc-remna-install.sh" /usr/local/bin/dfc-remna-install
    ln -sf /usr/local/bin/dfc-remna-install /usr/local/bin/dfc-ri
    export REMNA_INSTALLED_RUN=1
    exec "${_INSTALL_DIR}/dfc-remna-install.sh"
fi

set -euo pipefail

# Определяем директорию скрипта (уже установлен), резолвим симлинки
SCRIPT_DIR="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"

# ─── Загрузка модулей ───

# Core: базовые определения (порядок важен)
source "${SCRIPT_DIR}/lib/core/constants.sh"
source "${SCRIPT_DIR}/lib/core/colors.sh"
source "${SCRIPT_DIR}/lib/core/terminal.sh"
source "${SCRIPT_DIR}/lib/core/ui.sh"
source "${SCRIPT_DIR}/lib/core/system.sh"

# Install: генераторы и утилиты установки
source "${SCRIPT_DIR}/lib/install/generators.sh"
source "${SCRIPT_DIR}/lib/install/log_rotation.sh"
source "${SCRIPT_DIR}/lib/install/domain.sh"
source "${SCRIPT_DIR}/lib/install/certificates.sh"
source "${SCRIPT_DIR}/lib/install/templates.sh"
source "${SCRIPT_DIR}/lib/install/api.sh"
source "${SCRIPT_DIR}/lib/install/config.sh"
source "${SCRIPT_DIR}/lib/install/full.sh"
source "${SCRIPT_DIR}/lib/install/panel.sh"
source "${SCRIPT_DIR}/lib/install/node.sh"

# Manage: управление установкой
source "${SCRIPT_DIR}/lib/manage/detect.sh"
source "${SCRIPT_DIR}/lib/manage/services.sh"
source "${SCRIPT_DIR}/lib/manage/database.sh"
source "${SCRIPT_DIR}/lib/manage/domains.sh"
source "${SCRIPT_DIR}/lib/manage/access.sh"
source "${SCRIPT_DIR}/lib/manage/node.sh"
source "${SCRIPT_DIR}/lib/manage/template.sh"

# Extra: дополнительные настройки
source "${SCRIPT_DIR}/lib/extra/swap.sh"
source "${SCRIPT_DIR}/lib/extra/bbr.sh"
source "${SCRIPT_DIR}/lib/extra/fail2ban.sh"
source "${SCRIPT_DIR}/lib/extra/ufw.sh"
source "${SCRIPT_DIR}/lib/extra/logrotate.sh"
source "${SCRIPT_DIR}/lib/extra/warp.sh"
source "${SCRIPT_DIR}/lib/extra/menu.sh"

# Update: обновление и удаление
source "${SCRIPT_DIR}/lib/update/version.sh"
source "${SCRIPT_DIR}/lib/update/script.sh"

# Menu: главное меню
source "${SCRIPT_DIR}/lib/menu/main.sh"

# ═══════════════════════════════════════════════
# ТОЧКА ВХОДА
# ═══════════════════════════════════════════════
if [ "${REMNA_INSTALLED_RUN:-}" != "1" ]; then
    echo -e "${BLUE}⏳ Происходит подготовка установки... Пожалуйста, подождите${NC}"
    echo ""
fi

check_root
check_os

# Если запущены НЕ из установленной копии - скачиваем свежую и переключаемся
install_script
if [ "${REMNA_INSTALLED_RUN:-}" != "1" ]; then
    export REMNA_INSTALLED_RUN=1
    exec /usr/local/bin/dfc-remna-install
fi

# Проверка обновлений (всегда)
current_time=$(date +%s)
last_check=0

if [ -f "${UPDATE_CHECK_TIME_FILE}" ]; then
    last_check=$(cat "${UPDATE_CHECK_TIME_FILE}" 2>/dev/null || echo 0)
fi

# Проверяем раз в час (3600 секунд)
time_diff=$((current_time - last_check))
if [ $time_diff -gt 3600 ] || [ ! -f "${UPDATE_AVAILABLE_FILE}" ]; then
    new_version=$(check_for_updates) || true
    if [ -n "$new_version" ]; then
        echo "$new_version" > "${UPDATE_AVAILABLE_FILE}"
    else
        rm -f "${UPDATE_AVAILABLE_FILE}" 2>/dev/null || true
    fi
    echo "$current_time" > "${UPDATE_CHECK_TIME_FILE}"
fi

main_menu
