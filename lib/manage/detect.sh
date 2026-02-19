# ═══════════════════════════════════════════════
# ОПРЕДЕЛЕНИЕ ПУТИ К REMNAWAVE
# ═══════════════════════════════════════════════

detect_remnawave_path() {
    # Сначала проверяем /opt/remnawave (панель или панель+нода)
    if [ -f "/opt/remnawave/docker-compose.yml" ]; then
        echo "/opt/remnawave"
        return 0
    fi
    # Затем проверяем /opt/remnanode (только нода)
    if [ -f "/opt/remnanode/docker-compose.yml" ]; then
        echo "/opt/remnanode"
        return 0
    fi

    echo
    echo -e "${YELLOW}⚠️  Remnawave не найдена по стандартному пути ${WHITE}/opt/remnawave${NC} или ${WHITE}/opt/remnanode${NC}"
    echo
    reading "Укажите путь к директории Remnawave:" custom_path

    if [ -z "$custom_path" ]; then
        print_error "Путь не указан"
        return 1
    fi

    custom_path="${custom_path%/}"

    if [ ! -f "${custom_path}/docker-compose.yml" ]; then
        print_error "Файл docker-compose.yml не найден в ${custom_path}"
        return 1
    fi

    echo "$custom_path"
    return 0
}
