# ═══════════════════════════════════════════════
# УСТАНОВКА СКРИПТА
# ═══════════════════════════════════════════════
install_script() {
    mkdir -p "${DIR_REMNAWAVE}"

    # Чистим старые артефакты (remna_install, alias ri)
    cleanup_old_aliases

    # Если скрипт уже установлен - обновляем симлинки и запускаем его
    if [ -f "${DIR_REMNAWAVE}dfc-remna-install" ]; then
        chmod +x "${DIR_REMNAWAVE}dfc-remna-install"
        ln -sf "${DIR_REMNAWAVE}dfc-remna-install" /usr/local/bin/dfc-remna-install
        ln -sf /usr/local/bin/dfc-remna-install /usr/local/bin/dfc-ri
        return
    fi

    # Первая установка - получаем SHA последнего коммита для обхода CDN-кеша
    local download_url="$SCRIPT_URL"
    local latest_sha
    latest_sha=$(curl -sL --max-time 5 "https://api.github.com/repos/DanteFuaran/dfc-remna-install/commits/dev" 2>/dev/null | grep -m 1 '"sha"' | cut -d'"' -f4)
    if [ -n "$latest_sha" ]; then
        download_url="https://raw.githubusercontent.com/DanteFuaran/dfc-remna-install/$latest_sha/install_remnawave.sh"
    fi

    if ! wget -O "${DIR_REMNAWAVE}dfc-remna-install" "$download_url" >/dev/null 2>&1; then
        echo -e "${RED}✖ Не удалось скачать скрипт${NC}"
        exit 1
    fi
    
    chmod +x "${DIR_REMNAWAVE}dfc-remna-install"
    ln -sf "${DIR_REMNAWAVE}dfc-remna-install" /usr/local/bin/dfc-remna-install
    ln -sf /usr/local/bin/dfc-remna-install /usr/local/bin/dfc-ri
}

# ═══════════════════════════════════════════════
# ГЛАВНОЕ МЕНЮ
# ═══════════════════════════════════════════════
main_menu() {
    # Создаём алиасы при каждом запуске главного меню
    alias dfc-ri="/usr/local/bin/dfc-remna-install" 2>/dev/null || true
    
    while true; do
        local is_installed=false
        if [ -f "/opt/remnawave/docker-compose.yml" ]; then
            is_installed=true
        fi

        if [ "$is_installed" = true ]; then
            # Формируем заголовок с версией и уведомлением об обновлении
            local update_notice=""
            local menu_title="    🚀 DFC REMNA-INSTALL v$SCRIPT_VERSION\n${DARKGRAY}Проект развивается благодаря вашей поддержке\n        https://github.com/DanteFuaran${NC}"
            if [ -f /tmp/remna_update_available ]; then
                local new_version
                new_version=$(cat /tmp/remna_update_available)
                update_notice=" ${YELLOW}(Доступно обновление до v$new_version)${NC}"
            fi

            show_arrow_menu "$menu_title" \
                "📦  Установить компоненты" \
                "🔄  Переустановить" \
                "──────────────────────────────────────" \
                "▶️   Запустить сервисы" \
                "⏹️   Остановить сервисы" \
                "📋  Просмотр логов" \
                "──────────────────────────────────────" \
                "💾  База данных" \
                "🔓  Доступ к панели" \
                "🎨  Сменить сайт-заглушку" \
                "──────────────────────────────────────" \
                "⚙️   Дополнительные настройки" \
                "──────────────────────────────────────" \
                "🔄  Обновить панель/ноду" \
                "🔄  Обновить скрипт$update_notice" \
                "──────────────────────────────────────" \
                "🗑️   Удаление компонентов" \
                "──────────────────────────────────────" \
                "❌  Выход"
            local choice=$?

            case $choice in
                0)
                    show_arrow_menu "📦 ВЫБЕРИТЕ ТИП УСТАНОВКИ" \
                        "📦  Панель + Нода (один сервер)" \
                        "──────────────────────────────────────" \
                        "🖥️   Только панель" \
                        "🌐  Только нода" \
                        "➕  Подключить ноду в панель" \
                        "──────────────────────────────────────" \
                        "❌  Назад"
                    local install_choice=$?
                    case $install_choice in
                        0)
                            if [ ! -f "${DIR_REMNAWAVE}install_packages" ] || ! command -v docker >/dev/null 2>&1; then
                                install_packages
                            fi
                            installation_full
                            ;;
                        1) continue ;;
                        2)
                            if [ ! -f "${DIR_REMNAWAVE}install_packages" ] || ! command -v docker >/dev/null 2>&1; then
                                install_packages
                            fi
                            installation_panel
                            ;;
                        3)
                            if [ ! -f "${DIR_REMNAWAVE}install_packages" ] || ! command -v docker >/dev/null 2>&1; then
                                install_packages
                            fi
                            installation_node
                            ;;
                        4)
                            add_node_to_panel
                            ;;
                        5) continue ;;
                        6) continue ;;
                    esac
                    ;;
                1) manage_reinstall ;;
                2) continue ;;
                3) manage_start ;;
                4) manage_stop ;;
                5) manage_logs ;;
                6) continue ;;
                7) manage_database ;;
                8) manage_panel_access ;;
                9) manage_random_template ;;
                10) continue ;;
                11) manage_extra_settings ;;
                12) continue ;;
                13) manage_update ;;
                14) update_script ;;
                15) continue ;;
                16)
                    show_arrow_menu "🗑️ УДАЛЕНИЕ КОМПОНЕНТОВ" \
                        "💣  Удалить скрипт и все данные Remnawave" \
                        "🗑️   Удалить только скрипт" \
                        "🗑️   Удалить ноду с сервера" \
                        "──────────────────────────────────────" \
                        "❌  Назад"
                    local del_choice=$?
                    case $del_choice in
                        0) remove_script_all ;;
                        1) remove_script ;;
                        2) remove_node_from_panel ;;
                        3) continue ;;
                        4) continue ;;
                    esac
                    ;;
                17) continue ;;
                18) cleanup_terminal; exit 0 ;;
            esac
        else
            # Для неустановленного состояния
            local menu_title="    🚀 DFC REMNA-INSTALL v$SCRIPT_VERSION\n${DARKGRAY}Проект развивается благодаря вашей поддержке\n        https://github.com/DanteFuaran${NC}"
            
            show_arrow_menu "$menu_title" \
                "📦  Установить компоненты" \
                "──────────────────────────────────────" \
                "❌  Выход"
            local choice=$?

            case $choice in
                0)
                    show_arrow_menu "📦 ВЫБЕРИТЕ ТИП УСТАНОВКИ" \
                        "📦  Панель + Нода (один сервер)" \
                        "──────────────────────────────────────" \
                        "🖥️   Только панель" \
                        "🌐  Только нода" \
                        "➕  Подключить ноду в панель" \
                        "──────────────────────────────────────" \
                        "❌  Назад"
                    local install_choice=$?
                    case $install_choice in
                        0)
                            install_packages
                            installation_full
                            ;;
                        1) continue ;;
                        2)
                            install_packages
                            installation_panel
                            ;;
                        3)
                            install_packages
                            installation_node
                            ;;
                        4)
                            add_node_to_panel
                            ;;
                        5) continue ;;
                        6) continue ;;
                    esac
                    ;;
                1) continue ;;
                2) cleanup_uninstalled; cleanup_terminal; exit 0 ;;
            esac
        fi
    done
}

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

# Проверка обновлений только если Remnawave установлен
if [ -f "/opt/remnawave/docker-compose.yml" ]; then
    UPDATE_CHECK_FILE="/tmp/remna_last_update_check"
    current_time=$(date +%s)
    last_check=0

    if [ -f "$UPDATE_CHECK_FILE" ]; then
        last_check=$(cat "$UPDATE_CHECK_FILE" 2>/dev/null || echo 0)
    fi

    # Проверяем раз в час (3600 секунд)
    time_diff=$((current_time - last_check))
    if [ $time_diff -gt 3600 ] || [ ! -f /tmp/remna_update_available ]; then
        new_version=$(check_for_updates)
        if [ $? -eq 0 ] && [ -n "$new_version" ]; then
            echo "$new_version" > /tmp/remna_update_available
        else
            rm -f /tmp/remna_update_available 2>/dev/null
        fi
        echo "$current_time" > "$UPDATE_CHECK_FILE"
    fi
else
    rm -f /tmp/remna_update_available /tmp/remna_last_update_check 2>/dev/null
fi

main_menu
