# ═══════════════════════════════════════════════════
# WARP NATIVE
# ═══════════════════════════════════════════════════
manage_warp() {
    clear
    echo -e "${BLUE}══════════════════════════════════════${NC}"
    echo -e "${GREEN}   🌐 WARP${NC}"
    echo -e "${BLUE}══════════════════════════════════════${NC}"
    echo

    show_arrow_menu "WARP" \
        "📥  Установить WARP         " \
        "🗑️   Удалить WARP         " \
        "──────────────────────────────────────" \
        "➕  Добавить WARP в конфигурацию ноды" \
        "➖  Удалить WARP из конфигурации ноды" \
        "──────────────────────────────────────" \
        "❌  Назад"
    local choice=$?

    case $choice in
        0) install_warp_native ;;
        1) uninstall_warp_native ;;
        2) ;; # разделитель
        3) add_warp_to_config ;;
        4) remove_warp_from_config ;;
        5) ;; # разделитель
        6) return ;;
    esac
}

install_warp_native() {
    # Проверяем, есть ли нода на сервере
    local node_found=false
    if grep -q "remnanode:" /opt/remnawave/docker-compose.yml 2>/dev/null; then
        node_found=true
    fi
    if grep -q "remnanode:" /opt/remnanode/docker-compose.yml 2>/dev/null; then
        node_found=true
    fi
    if [ "$node_found" = false ]; then
        echo -e "${YELLOW}⚠️  Нода не найдена на этом сервере${NC}"
        echo -e "${DARKGRAY}WARP работает только с установленной нодой.${NC}"
        echo
        read -s -n 1 -p "$(echo -e "${DARKGRAY}Нажмите любую клавишу для продолжения...${NC}")"
        echo
        return 1
    fi

    clear
    echo -e "${BLUE}══════════════════════════════════════${NC}"
    echo -e "${GREEN}           📥 УСТАНОВКА WARP${NC}"
    echo -e "${BLUE}══════════════════════════════════════${NC}"
    echo

    # Проверяем, установлен ли уже WARP
    if ip link show warp 2>/dev/null | grep -q "warp"; then
        print_success "WARP уже установлен"
        echo
        read -s -n 1 -p "$(echo -e "${DARKGRAY}Нажмите любую клавишу для продолжения...${NC}")"
        echo
        return 0
    fi

    # Спрашиваем WARP+ ключ
    echo -e "${YELLOW}Если у вас есть ключ для WARP, вы можете ввести его ниже.${NC}"
    echo -e "${DARKGRAY}Оставьте пустым для бесплатной версии.${NC}"
    echo
    reading_inline "WARP+ ключ (Enter для пропуска):" warp_key
    echo

    clear
    echo -e "${BLUE}══════════════════════════════════════${NC}"
    echo -e "${GREEN}           📥 УСТАНОВКА WARP${NC}"
    echo -e "${BLUE}══════════════════════════════════════${NC}"
    echo

    (
        { echo "2"; echo "${warp_key:-}"; } | bash <(curl -fsSL https://raw.githubusercontent.com/distillium/warp-native/main/install.sh) >/dev/null 2>&1
    ) &
    show_spinner "Установка WARP"
    echo

    # Проверяем результат
    if ip link show warp 2>/dev/null | grep -q "warp"; then
        print_success "Настройка WARP"
        print_success "Создание WARP интерфейса"
        print_success "WARP успешно установлен"
        echo
        echo -e "${YELLOW}⚠️  Добавьте WARP в конфигурацию ноды через соответствующий пункт меню.${NC}"
    else
        print_error "Не удалось установить WARP"
        echo -e "${YELLOW}Проверьте подключение к интернету и попробуйте снова.${NC}"
    fi

    echo
    echo -e "${BLUE}══════════════════════════════════════${NC}"
    read -s -n 1 -p "$(echo -e "${DARKGRAY}Нажмите Enter для продолжения${NC}")"
    echo
}

uninstall_warp_native() {
    clear
    echo -e "${BLUE}══════════════════════════════════════${NC}"
    echo -e "${RED}          🗑️  УДАЛЕНИЕ WARP${NC}"
    echo -e "${BLUE}══════════════════════════════════════${NC}"

    # Проверяем, установлен ли WARP
    if ! ip link show warp 2>/dev/null | grep -q "warp"; then
        echo
        print_error "WARP не установлен"
        echo
        echo -e "${DARKGRAY}──────────────────────────────────────${NC}"
        read -s -n 1 -p "$(echo -e "${DARKGRAY}Нажмите Enter для продолжения${NC}")"
        echo
        return 0
    fi

    if ! confirm_action; then
        print_error "Операция отменена"
        sleep 2
        return 1
    fi

    clear
    echo -e "${BLUE}══════════════════════════════════════${NC}"
    echo -e "${RED}          🗑️  УДАЛЕНИЕ WARP${NC}"
    echo -e "${BLUE}══════════════════════════════════════${NC}"
    echo

    (
        echo "2" | bash <(curl -fsSL https://raw.githubusercontent.com/distillium/warp-native/main/uninstall.sh) >/dev/null 2>&1
    ) &
    show_spinner "Удаление WARP"
    echo

    # Проверяем результат
    if ! ip link show warp 2>/dev/null | grep -q "warp"; then
        print_success "Удаление WARP"
        print_success "WARP успешно удалён"
    else
        print_error "Не удалось удалить WARP — интерфейс всё ещё активен"
    fi

    echo
    echo -e "${BLUE}══════════════════════════════════════${NC}"
    read -s -n 1 -p "$(echo -e "${DARKGRAY}Нажмите любую клавишу для продолжения...${NC}")"
    echo
}

add_warp_to_config() {
    clear
    echo -e "${BLUE}══════════════════════════════════════${NC}"
    echo -e "${GREEN}   ➕ ДОБАВЛЕНИЕ WARP В КОНФИГУРАЦИЮ${NC}"
    echo -e "${BLUE}══════════════════════════════════════${NC}"
    echo

    # Предупреждение — операция должна выполняться на сервере с панелью
    echo -e "${RED}⚠️  ВНИМАНИЕ!${NC}"
    echo -e "${YELLOW}Вы уверены, что находитесь на сервере с установленной панелью?${NC}"
    echo -e "${DARKGRAY}Добавление WARP-настроек должно выполняться только на сервере,${NC}"
    echo -e "${DARKGRAY}где установлена панель, а не на сервере ноды.${NC}"
    echo
    echo -en "${GREEN}[?]${NC} ${YELLOW}Продолжить? (Enter/Esc):${NC} "
    read -rsn 1 -t 10 key 2>/dev/null || true
    echo

    if [ "$key" = $'\x1b' ]; then
        return 0
    fi

    # Получаем токен
    if ! get_panel_token; then
        return 1
    fi
    local token
    token=$(cat "${DIR_REMNAWAVE}/token")
    local domain_url="127.0.0.1:3000"

    # Получаем список конфигураций
    local config_response
    config_response=$(make_api_request "GET" "${domain_url}/api/config-profiles" "$token")

    if [ -z "$config_response" ] || ! echo "$config_response" | jq -e '.response.configProfiles' >/dev/null 2>&1; then
        print_error "Не удалось получить список конфигураций"
        echo
        read -s -n 1 -p "$(echo -e "${DARKGRAY}Нажмите любую клавишу для продолжения...${NC}")"
        echo
        return 1
    fi

    local configs
    configs=$(echo "$config_response" | jq -r '.response.configProfiles[] | select(.uuid and .name) | "\(.name) \(.uuid)"' 2>/dev/null)

    if [ -z "$configs" ]; then
        print_error "Конфигурации не найдены"
        echo
        read -s -n 1 -p "$(echo -e "${DARKGRAY}Нажмите любую клавишу для продолжения...${NC}")"
        echo
        return 1
    fi

    echo -e "${YELLOW}Выберите конфигурацию для добавления WARP:${NC}"
    echo

    local i=1
    declare -A config_map
    local menu_items=()
    while IFS=' ' read -r name uuid; do
        [ -z "$name" ] && continue
        menu_items+=("📄  $name")
        config_map[$i]="$uuid"
        ((i++))
    done <<< "$configs"

    menu_items+=("──────────────────────────────────────")
    menu_items+=("❌  Назад")

    show_arrow_menu "ВЫБЕРИТЕ КОНФИГУРАЦИЮ" "${menu_items[@]}"
    local choice=$?

    # Проверка - выбран ли разделитель или "Назад"
    if [ $choice -ge $((i-1)) ]; then
        return 0
    fi

    local selected_uuid=${config_map[$((choice+1))]}
    [ -z "$selected_uuid" ] && return 1

    # Получаем данные конфигурации
    local config_data
    config_data=$(make_api_request "GET" "${domain_url}/api/config-profiles/$selected_uuid" "$token")

    if [ -z "$config_data" ]; then
        print_error "Не удалось получить данные конфигурации"
        return 1
    fi

    local config_json
    config_json=$(echo "$config_data" | jq -r '.response.config // .config // empty')

    if [ -z "$config_json" ] || [ "$config_json" = "null" ]; then
        print_error "Конфигурация пуста"
        return 1
    fi

    # Проверяем, есть ли уже warp-out
    if echo "$config_json" | jq -e '.outbounds[] | select(.tag == "warp-out")' >/dev/null 2>&1; then
        echo -e "${YELLOW}⚠️  WARP уже добавлен в эту конфигурацию${NC}"
        echo
        read -s -n 1 -p "$(echo -e "${DARKGRAY}Нажмите любую клавишу для продолжения...${NC}")"
        echo
        return 0
    fi

    # Добавляем warp-out
    local warp_outbound
    warp_outbound='{
        "tag": "warp-out",
        "protocol": "freedom",
        "settings": {
            "domainStrategy": "UseIP"
        },
        "streamSettings": {
            "sockopt": {
                "interface": "warp",
                "tcpFastOpen": true
            }
        }
    }'

    config_json=$(echo "$config_json" | jq --argjson warp_out "$warp_outbound" '.outbounds += [$warp_out]' 2>/dev/null)

    # Добавляем правило маршрутизации — весь tcp/udp трафик через WARP
    local warp_rule
    warp_rule='{
        "type": "field",
        "network": ["tcp", "udp"],
        "outboundTag": "warp-out"
    }'

    config_json=$(echo "$config_json" | jq --argjson warp_rule "$warp_rule" '.routing.rules += [$warp_rule]' 2>/dev/null)

    # Устанавливаем domainStrategy на AsIs на уровне routing если не задано
    if echo "$config_json" | jq -e '.routing.domainStrategy' >/dev/null 2>&1; then
        : # уже есть
    else
        config_json=$(echo "$config_json" | jq '.routing.domainStrategy = "AsIs"' 2>/dev/null)
    fi

    # Обновляем конфигурацию
    local update_response
    update_response=$(make_api_request "PATCH" "${domain_url}/api/config-profiles" "$token" "{\"uuid\": \"$selected_uuid\", \"config\": $config_json}")

    if [ -n "$update_response" ] && echo "$update_response" | jq -e '.' >/dev/null 2>&1; then
        print_success "WARP добавлен в конфигурацию"
        echo
        echo -e "${DARKGRAY}Весь трафик (TCP/UDP) будет идти через WARP${NC}"
    else
        print_error "Не удалось обновить конфигурацию"
    fi

    echo
    read -s -n 1 -p "$(echo -e "${DARKGRAY}Нажмите любую клавишу для продолжения...${NC}")"
    echo
}

remove_warp_from_config() {
    clear
    echo -e "${BLUE}══════════════════════════════════════${NC}"
    echo -e "${RED}   ➖ УДАЛЕНИЕ WARP ИЗ КОНФИГУРАЦИИ${NC}"
    echo -e "${BLUE}══════════════════════════════════════${NC}"
    echo

    # Предупреждение — операция должна выполняться на сервере с панелью
    echo -e "${RED}⚠️  ВНИМАНИЕ!${NC}"
    echo -e "${YELLOW}Вы уверены, что находитесь на сервере с установленной панелью?${NC}"
    echo -e "${DARKGRAY}Удаление WARP-настроек должно выполняться только на сервере,${NC}"
    echo -e "${DARKGRAY}где установлена панель, а не на сервере ноды.${NC}"
    echo
    echo -en "${GREEN}[?]${NC} ${YELLOW}Продолжить? (Enter/Esc):${NC} "
    read -rsn 1 -t 10 key 2>/dev/null || true
    echo

    if [ "$key" = $'\x1b' ]; then
        return 0
    fi

    # Получаем токен
    if ! get_panel_token; then
        return 1
    fi
    local token
    token=$(cat "${DIR_REMNAWAVE}/token")
    local domain_url="127.0.0.1:3000"

    # Получаем список конфигураций
    local config_response
    config_response=$(make_api_request "GET" "${domain_url}/api/config-profiles" "$token")

    if [ -z "$config_response" ]; then
        print_error "Не удалось получить список конфигураций"
        return 1
    fi

    local configs
    configs=$(echo "$config_response" | jq -r '.response.configProfiles[] | select(.uuid and .name) | "\(.name) \(.uuid)"' 2>/dev/null)

    if [ -z "$configs" ]; then
        print_error "Конфигурации не найдены"
        return 1
    fi

    echo -e "${YELLOW}Выберите конфигурацию для удаления WARP:${NC}"
    echo

    local i=1
    declare -A config_map
    local menu_items=()
    while IFS=' ' read -r name uuid; do
        [ -z "$name" ] && continue
        menu_items+=("📄  $name")
        config_map[$i]="$uuid"
        ((i++))
    done <<< "$configs"

    menu_items+=("──────────────────────────────────────")
    menu_items+=("❌  Назад")

    show_arrow_menu "ВЫБЕРИТЕ КОНФИГУРАЦИЮ" "${menu_items[@]}"
    local choice=$?

    # Проверка - выбран ли разделитель или "Назад"
    if [ $choice -ge $((i-1)) ]; then
        return 0
    fi

    local selected_uuid=${config_map[$((choice+1))]}
    [ -z "$selected_uuid" ] && return 1

    # Получаем данные конфигурации
    local config_data
    config_data=$(make_api_request "GET" "${domain_url}/api/config-profiles/$selected_uuid" "$token")

    local config_json
    config_json=$(echo "$config_data" | jq -r '.response.config // .config // empty')

    if [ -z "$config_json" ] || [ "$config_json" = "null" ]; then
        print_error "Конфигурация пуста"
        return 1
    fi

    local removed=false

    # Удаляем warp-out из outbounds
    if echo "$config_json" | jq -e '.outbounds[] | select(.tag == "warp-out")' >/dev/null 2>&1; then
        config_json=$(echo "$config_json" | jq 'del(.outbounds[] | select(.tag == "warp-out"))' 2>/dev/null)
        echo -e "${GREEN}✓${NC} Удалён warp-out из outbounds"
        removed=true
    else
        echo -e "${YELLOW}⚠${NC} warp-out не найден в outbounds"
    fi

    # Удаляем правило из routing
    if echo "$config_json" | jq -e '.routing.rules[] | select(.outboundTag == "warp-out")' >/dev/null 2>&1; then
        config_json=$(echo "$config_json" | jq 'del(.routing.rules[] | select(.outboundTag == "warp-out"))' 2>/dev/null)
        echo -e "${GREEN}✓${NC} Удалено правило WARP из routing"
        removed=true
    else
        echo -e "${YELLOW}⚠${NC} Правило WARP не найдено в routing"
    fi

    if [ "$removed" = false ]; then
        echo
        echo -e "${YELLOW}WARP не был настроен в этой конфигурации${NC}"
        echo
        read -s -n 1 -p "$(echo -e "${DARKGRAY}Нажмите любую клавишу для продолжения...${NC}")"
        echo
        return 0
    fi

    # Обновляем конфигурацию
    local update_response
    update_response=$(make_api_request "PATCH" "${domain_url}/api/config-profiles" "$token" "{\"uuid\": \"$selected_uuid\", \"config\": $config_json}")

    if [ -n "$update_response" ] && echo "$update_response" | jq -e '.' >/dev/null 2>&1; then
        echo
        print_success "WARP удалён из конфигурации"
    else
        echo
        print_error "Не удалось обновить конфигурацию"
    fi

    echo
    read -s -n 1 -p "$(echo -e "${DARKGRAY}Нажмите любую клавишу для продолжения...${NC}")"
    echo
}
