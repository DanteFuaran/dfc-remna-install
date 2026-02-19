# ═══════════════════════════════════════════════
# ОПРЕДЕЛЕНИЕ ПУТИ К REMNAWAVE
# ═══════════════════════════════════════════════

# Проверяет, установлена ли панель (/opt/remnawave)
is_panel_installed() {
    [ -f "/opt/remnawave/docker-compose.yml" ]
}

# Проверяет, установлена ли нода (/opt/remnanode)
is_node_installed() {
    [ -f "/opt/remnanode/docker-compose.yml" ]
}

# Возвращает путь к установленному компоненту:
# сначала /opt/remnawave (панель), затем /opt/remnanode (нода).
# Если ничего не найдено — выводит ошибку и возвращает 1.
detect_remnawave_path() {
    if is_panel_installed; then
        echo "/opt/remnawave"
        return 0
    fi
    if is_node_installed; then
        echo "/opt/remnanode"
        return 0
    fi
    print_error "Remnawave не найдена. Убедитесь, что панель или нода установлены."
    return 1
}
