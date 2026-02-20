# ═══════════════════════════════════════════════════
# WARP NATIVE
# ═══════════════════════════════════════════════════
manage_warp() {
    local has_panel=false
    local has_node=false
    is_panel_installed && has_panel=true
    is_node_installed  && has_node=true

    local warp_installed=false
    ip link show warp 2>/dev/null | grep -q "warp" && warp_installed=true

    local -a items=()
    local -a actions=()

    # Ничего не установлено
    if [ "$has_panel" = false ] && [ "$has_node" = false ]; then
        clear
        echo -e "${BLUE}══════════════════════════════════════${NC}"
        echo -e "${GREEN}   🌐 WARP${NC}"
        echo -e "${BLUE}══════════════════════════════════════${NC}"
        echo
        echo -e "${YELLOW}На сервере нет приложений требующих WARP${NC}"
        echo -e "${BLUE}══════════════════════════════════════${NC}"
        show_continue_prompt || return 1
        return
    fi

    # Только панель (без ноды) — только пункты конфигурации
    if [ "$has_panel" = true ] && [ "$has_node" = false ]; then
        items+=("➕  Добавить WARP в конфигурацию ноды");  actions+=("add_config")
        items+=("➖  Удалить WARP из конфигурации ноды");  actions+=("del_config")
        items+=("──────────────────────────────────────");  actions+=("sep")
        items+=("❌  Назад");                               actions+=("back")

    # Только нода (без панели) — только установка/удаление WARP
    elif [ "$has_node" = true ] && [ "$has_panel" = false ]; then
        if [ "$warp_installed" = false ]; then
            items+=("📥  Установить WARP");  actions+=("install")
        else
            items+=("🗑️   Удалить WARP");    actions+=("uninstall")
        fi
        items+=("──────────────────────────────────────"); actions+=("sep")
        items+=("❌  Назад");                              actions+=("back")

    # Оба компонента — все пункты
    else
        if [ "$warp_installed" = false ]; then
            items+=("📥  Установить WARP");  actions+=("install")
        else
            items+=("🗑️   Удалить WARP");    actions+=("uninstall")
        fi
        items+=("──────────────────────────────────────");  actions+=("sep")
        items+=("➕  Добавить WARP в конфигурацию ноды");  actions+=("add_config")
        items+=("➖  Удалить WARP из конфигурации ноды");  actions+=("del_config")
        items+=("──────────────────────────────────────");  actions+=("sep")
        items+=("❌  Назад");                               actions+=("back")
    fi

    show_arrow_menu "🌐  WARP" "${items[@]}"
    local choice=$?
    local action="${actions[$choice]:-back}"

    case "$action" in
        install)   install_warp_native ;;
        uninstall) uninstall_warp_native ;;
        add_config) add_warp_to_config ;;
        del_config) remove_warp_from_config ;;
        *) return ;;
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
        show_continue_prompt || return 1
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
        show_continue_prompt || return 1
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
        # 1. Установка WireGuard
        apt-get update -qq >/dev/null 2>&1
        apt-get install -y wireguard >/dev/null 2>&1

        # 2. Определяем архитектуру и скачиваем wgcf
        local arch
        case $(uname -m) in
            x86_64)          arch="amd64" ;;
            aarch64|arm64)   arch="arm64" ;;
            armv7l)          arch="armv7" ;;
            *)               arch="amd64" ;;
        esac
        local wgcf_version
        wgcf_version=$(curl -sL --max-time 10 "https://api.github.com/repos/ViRb3/wgcf/releases/latest" 2>/dev/null | grep '"tag_name"' | cut -d'"' -f4)
        if [ -z "$wgcf_version" ]; then
            exit 1
        fi
        local wgcf_bin="wgcf_${wgcf_version#v}_linux_${arch}"
        wget -q "https://github.com/ViRb3/wgcf/releases/download/${wgcf_version}/${wgcf_bin}" -O /tmp/wgcf 2>/dev/null
        chmod +x /tmp/wgcf
        mv /tmp/wgcf /usr/local/bin/wgcf

        # 3. Регистрация
        cd /tmp
        rm -f wgcf-account.toml wgcf-profile.conf 2>/dev/null
        timeout 60 bash -c 'yes | wgcf register' >/dev/null 2>&1 || \
            { echo | wgcf register >/dev/null 2>&1; sleep 2; }

        # 4. Применяем WARP+ ключ если задан
        if [ -n "${warp_key:-}" ]; then
            wgcf update --license-key "${warp_key}" >/dev/null 2>&1 || true
        fi

        # 5. Генерация конфигурации
        wgcf generate >/dev/null 2>&1

        # 6. Редактирование конфигурации
        local conf="/tmp/wgcf-profile.conf"
        sed -i '/^DNS =/d' "$conf"
        grep -q 'Table = off' "$conf"           || sed -i '/^MTU =/aTable = off' "$conf"
        grep -q 'PersistentKeepalive' "$conf"  || sed -i '/^Endpoint =/aPersistentKeepalive = 25' "$conf"

        # 7. IPv6
        local ipv6_ok=false
        sysctl net.ipv6.conf.all.disable_ipv6 2>/dev/null | grep -q ' = 0' && \
        sysctl net.ipv6.conf.default.disable_ipv6 2>/dev/null | grep -q ' = 0' && \
        ip -6 addr show scope global 2>/dev/null | grep -qv 'fe80::' && ipv6_ok=true
        if [ "$ipv6_ok" = false ]; then
            sed -i 's/,\s*[0-9a-fA-F:]*\/128//' "$conf"
            sed -i '/Address = [0-9a-fA-F:]*\/128/d' "$conf"
        fi

        # 8. Перемещаем конфигурацию
        mkdir -p /etc/wireguard
        mv "$conf" /etc/wireguard/warp.conf

        # 9. Запускаем и включаем автозапуск
        systemctl start wg-quick@warp >/dev/null 2>&1
        systemctl enable wg-quick@warp >/dev/null 2>&1
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
    show_continue_prompt || return 1
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
        show_continue_prompt || return 1
        return 0
    fi

    if ! confirm_action; then
        print_error "Операция отменена"
        sleep 2
        return 0
    fi

    clear
    echo -e "${BLUE}══════════════════════════════════════${NC}"
    echo -e "${RED}          🗑️  УДАЛЕНИЕ WARP${NC}"
    echo -e "${BLUE}══════════════════════════════════════${NC}"
    echo

    (
        # Останавливаем интерфейс
        wg-quick down warp >/dev/null 2>&1 || true
        systemctl disable wg-quick@warp >/dev/null 2>&1 || true
        # Удаляем файлы
        rm -f /etc/wireguard/warp.conf 2>/dev/null || true
        rm -f /usr/local/bin/wgcf 2>/dev/null || true
        rm -f /tmp/wgcf-account.toml /tmp/wgcf-profile.conf 2>/dev/null || true
        # Удаляем пакеты
        DEBIAN_FRONTEND=noninteractive apt-get remove --purge -y wireguard >/dev/null 2>&1 || true
        DEBIAN_FRONTEND=noninteractive apt-get autoremove -y >/dev/null 2>&1 || true
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
    show_continue_prompt || return 1
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
        show_continue_prompt || return 1
        return 1
    fi

    local configs
    configs=$(echo "$config_response" | jq -r '.response.configProfiles[] | select(.uuid and .name) | "\(.name) \(.uuid)"' 2>/dev/null)

    if [ -z "$configs" ]; then
        print_error "Конфигурации не найдены"
        echo
        show_continue_prompt || return 1
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

    show_arrow_menu "📄  Выберите конфигурацию" "${menu_items[@]}"
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
        show_continue_prompt || return 1
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
    show_continue_prompt || return 1
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

    show_arrow_menu "📄  Выберите конфигурацию" "${menu_items[@]}"
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
        show_continue_prompt || return 1
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
    show_continue_prompt || return 1
}
