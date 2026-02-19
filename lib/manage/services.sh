# ═══════════════════════════════════════════════
# УПРАВЛЕНИЕ СЕРВИСАМИ
# ═══════════════════════════════════════════════

manage_start() {
    local rw_path
    rw_path=$(detect_remnawave_path) || return
    (
        cd "$rw_path"
        docker compose up -d >/dev/null 2>&1
    ) &
    show_spinner "Запуск сервисов"
    print_success "Сервисы запущены"
    echo
    read -s -n 1 -p "$(echo -e "${DARKGRAY}Нажмите Enter для продолжения${NC}")"
    echo
}

manage_stop() {
    local rw_path
    rw_path=$(detect_remnawave_path) || return
    (
        cd "$rw_path"
        docker compose down >/dev/null 2>&1
    ) &
    show_spinner "Остановка сервисов"
    print_success "Сервисы остановлены"
    echo
    read -s -n 1 -p "$(echo -e "${DARKGRAY}Нажмите Enter для продолжения${NC}")"
    echo
}

manage_update() {
    clear
    echo -e "${BLUE}══════════════════════════════════════${NC}"
    echo -e "${GREEN}   🔄 ОБНОВЛЕНИЕ КОМПОНЕНТОВ${NC}"
    echo -e "${BLUE}══════════════════════════════════════${NC}"
    echo

    if ! is_panel_installed && ! is_node_installed; then
        echo -e "${RED}✖  Не найдено установленных компонентов.${NC}"
        echo
        echo -e "${BLUE}══════════════════════════════════════${NC}"
        read -s -n 1 -p "$(echo -e "${DARKGRAY}Нажмите Enter для продолжения${NC}")"
        echo
        return
    fi

    local rw_path
    rw_path=$(detect_remnawave_path) || return

    (
        cd "$rw_path"
        docker compose pull >/dev/null 2>&1
    ) &
    show_spinner "Скачивание обновлений"

    (
        cd "$rw_path"
        docker compose up -d >/dev/null 2>&1
    ) &
    show_spinner "Перезапуск сервисов"

    (
        docker image prune -af >/dev/null 2>&1
    ) &
    show_spinner "Очистка старых образов"

    print_success "Обновление завершено"
    echo
    read -s -n 1 -p "$(echo -e "${DARKGRAY}Нажмите Enter для продолжения${NC}")"
        echo
}

manage_logs() {
    local rw_path
    rw_path=$(detect_remnawave_path) || return
    clear
    echo -e "${YELLOW}Для выхода из логов нажмите Ctrl+C${NC}"
    sleep 1
    cd "$rw_path"
    docker compose logs -f -t --tail 100
}

manage_reinstall() {
    clear
    echo -e "${BLUE}══════════════════════════════════════${NC}"
    echo -e "${RED}   🗑️ ПЕРЕУСТАНОВКА${NC}"
    echo -e "${BLUE}══════════════════════════════════════${NC}"
    echo

    echo -e "${RED}⚠️  Все данные будут удалены!${NC}"

    if ! confirm_action; then
        return
    fi

    local rw_path
    rw_path=$(detect_remnawave_path) || return

    (
        cd "$rw_path"
        docker compose down -v --rmi all >/dev/null 2>&1
        docker system prune -af >/dev/null 2>&1
    ) &
    show_spinner "Удаление контейнеров и данных"

    (
        rm -f "$rw_path/.env"
        rm -f "$rw_path/docker-compose.yml"
        rm -f "$rw_path/nginx.conf"
    ) &
    show_spinner "Очистка конфигурации"

    print_success "Готово к переустановке"

    show_arrow_menu "📦 ВЫБЕРИТЕ ТИП УСТАНОВКИ" \
        "📦  Панель + Нода (один сервер)" \
        "──────────────────────────────────────" \
        "🖥️   Только панель" \
        "🌐  Только нода" \
        "➕  Подключить ноду в панель" \
        "──────────────────────────────────────" \
        "❌  Назад"
    local choice=$?

    case $choice in
        0) installation_full ;;
        1) : ;;
        2) installation_panel ;;
        3) installation_node ;;
        4) add_node_to_panel ;;
        5) : ;;
        6) return ;;
    esac
}
