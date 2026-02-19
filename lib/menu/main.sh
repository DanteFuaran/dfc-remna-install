# ═══════════════════════════════════════════════
# ГЛАВНОЕ МЕНЮ
# ═══════════════════════════════════════════════

main_menu() {
    # Создаём алиасы при каждом запуске главного меню
    alias dfc-ri="/usr/local/bin/dfc-remna-install" 2>/dev/null || true
    
    while true; do
        local is_installed=false
        local has_panel=false
        local has_node=false
        if [ -f "/opt/remnawave/docker-compose.yml" ]; then
            is_installed=true
            if grep -q "remnawave:" /opt/remnawave/docker-compose.yml 2>/dev/null; then
                has_panel=true
            fi
            if grep -q "remnanode:" /opt/remnawave/docker-compose.yml 2>/dev/null; then
                has_node=true
            fi
        fi
        if [ -f "/opt/remnanode/docker-compose.yml" ]; then
            is_installed=true
            if grep -q "remnanode:" /opt/remnanode/docker-compose.yml 2>/dev/null; then
                has_node=true
            fi
        fi

        # Формируем заголовок с версией и статусом установки
        local update_notice=""
        local install_status=""
        if [ "$has_panel" = true ] && [ "$has_node" = true ]; then
            install_status="\n${DARKGRAY}  Установлено: ${GREEN}Панель + Нода${NC}"
        elif [ "$has_panel" = true ]; then
            install_status="\n${DARKGRAY}  Установлено: ${GREEN}Панель${NC}"
        elif [ "$has_node" = true ]; then
            install_status="\n${DARKGRAY}  Установлено: ${GREEN}Нода${NC}"
        fi
        local menu_title="    🚀 DFC REMNA-INSTALL v$SCRIPT_VERSION${install_status}\n${DARKGRAY}Проект развивается благодаря вашей поддержке\n        https://github.com/DanteFuaran${NC}"
        if [ -f "${UPDATE_AVAILABLE_FILE}" ]; then
            local new_version
            new_version=$(cat "${UPDATE_AVAILABLE_FILE}")
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
    done
}
