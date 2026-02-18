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
    get_panel_token
    if [ $? -ne 0 ]; then
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
    get_panel_token
    if [ $? -ne 0 ]; then
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

open_panel_access() {
    clear
    echo -e "${BLUE}══════════════════════════════════════${NC}"
    echo -e "${GREEN}   🔓 ОТКРЫТИЕ ДОСТУПА К ПАНЕЛИ (8443)${NC}"
    echo -e "${BLUE}══════════════════════════════════════${NC}"
    echo

    local dir="/opt/remnawave"

    # Проверяем, что nginx.conf существует
    if [ ! -f "$dir/nginx.conf" ]; then
        print_error "Файл nginx.conf не найден"
        sleep 2
        return
    fi

    # Читаем данные cookie из nginx.conf
    local COOKIE_NAME COOKIE_VALUE
    if ! get_cookie_from_nginx; then
        print_error "Не удалось извлечь cookie из nginx.conf"
        sleep 2
        return
    fi

    # Определяем домен панели
    local panel_domain
    panel_domain=$(grep -oP 'server_name\s+\K[^;]+' "$dir/nginx.conf" | head -1)

    # Определяем сертификат панели
    local panel_cert
    panel_cert=$(grep -A 5 "server_name ${panel_domain};" "$dir/nginx.conf" | grep -oP 'ssl_certificate\s+"/etc/nginx/ssl/\K[^/]+' | head -1)

    # Проверяем, уже настроен ли 8443
    if grep -q "# ─── 8443 Fallback" "$dir/nginx.conf" 2>/dev/null; then
        # 8443 блок уже существует — проверяем UFW
        if ufw status 2>/dev/null | grep -q "8443/tcp.*ALLOW"; then
            print_success "Доступ по 8443 уже открыт"
        else
            ufw allow 8443/tcp >/dev/null 2>&1
            print_success "Порт 8443 открыт в файрволе"
        fi
        echo
        echo -e "${GREEN}🔗 Ссылка на панель:${NC}"
        echo -e "${WHITE}https://${panel_domain}:8443/?${COOKIE_NAME}=${COOKIE_VALUE}${NC}"
        echo
        echo -e "${RED}⚠️  Не забудьте закрыть доступ после использования!${NC}"
        echo
        read -e -p "$(echo -e "${DARKGRAY}Нажмите Enter для продолжения...${NC}")" _
        return
    fi

    # Проверяем, не занят ли порт 8443
    if command -v ss >/dev/null 2>&1; then
        if ss -tuln | grep -q ":8443"; then
            print_error "Порт 8443 уже занят другим процессом"
            sleep 2
            return
        fi
    elif command -v netstat >/dev/null 2>&1; then
        if netstat -tuln | grep -q ":8443"; then
            print_error "Порт 8443 уже занят другим процессом"
            sleep 2
            return
        fi
    fi

    # Находим номер строки с закрывающей скобкой последнего server блока
    # Используем awk для корректного поиска закрывающей скобки на верхнем уровне
    local insert_after_line
    insert_after_line=$(awk '/^server \{/ {start=NR; brace=1} 
        brace {if (/\{/) brace++; if (/\}/) brace--} 
        brace==0 && start {print NR; exit}' "$dir/nginx.conf")
    
    # Если не нашли, ищем просто последнюю закрывающую скобку
    if [ -z "$insert_after_line" ]; then
        insert_after_line=$(grep -n "^}$" "$dir/nginx.conf" | tail -1 | cut -d: -f1)
    fi

    # Создаем временный файл с блоком
    local temp_file="/tmp/remnawave_8443_block_$$.conf"
    cat > "$temp_file" << 'EOF'

# ─── 8443 Fallback (direct access) ───
server {
    server_name PANEL_DOMAIN;
    listen 8443 ssl;
    listen [::]:8443 ssl;
    http2 on;

    ssl_certificate "/etc/nginx/ssl/PANEL_CERT/fullchain.pem";
    ssl_certificate_key "/etc/nginx/ssl/PANEL_CERT/privkey.pem";
    ssl_trusted_certificate "/etc/nginx/ssl/PANEL_CERT/fullchain.pem";

    add_header Set-Cookie $set_cookie_header;

    # API endpoints - no auth required for auth status
    location ^~ /api/auth/ {
        proxy_http_version 1.1;
        proxy_pass http://remnawave;
        proxy_busy_buffers_size 24k;
        proxy_buffers 8 16k;
        proxy_buffer_size 16k;
        proxy_set_header Host $host;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection $connection_upgrade;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto https;
        proxy_set_header X-Forwarded-Host $host;
        proxy_set_header X-Forwarded-Port 8443;
        proxy_connect_timeout 60s;
        proxy_send_timeout 60s;
        proxy_read_timeout 60s;
    }

    location / {
        error_page 418 = @unauthorized;
        recursive_error_pages on;
        if ($authorized = 0) {
            return 418;
        }
        proxy_http_version 1.1;
        proxy_pass http://remnawave;
        proxy_busy_buffers_size 24k;
        proxy_buffers 8 16k;
        proxy_buffer_size 16k;
        proxy_redirect off;
        proxy_set_header Host $host;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection $connection_upgrade;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto https;
        proxy_set_header X-Forwarded-Host $host;
        proxy_set_header X-Forwarded-Port 8443;
        proxy_connect_timeout 60s;
        proxy_send_timeout 60s;
        proxy_read_timeout 60s;
    }

    location @unauthorized {
        root /var/www/html;
        index index.html;
    }
}
EOF

    # Заменяем плейсхолдеры
    sed -i "s/PANEL_DOMAIN/${panel_domain}/g" "$temp_file"
    sed -i "s/PANEL_CERT/${panel_cert}/g" "$temp_file"

    if [ -n "$insert_after_line" ]; then
        # Вставляем fallback блок после найденной строки
        sed -i "${insert_after_line}r ${temp_file}" "$dir/nginx.conf"
    else
        # Если не нашли, просто добавляем в конец
        cat "$temp_file" >> "$dir/nginx.conf"
    fi

    # Удаляем временный файл
    rm -f "$temp_file"

    # Перезапускаем nginx контейнер
    (
        cd "$dir"
        docker compose down remnawave-nginx >/dev/null 2>&1
        docker compose up -d remnawave-nginx >/dev/null 2>&1
    ) &
    show_spinner "Перезапуск nginx"

    # Проверяем, что nginx запустился без ошибок
    sleep 2
    if ! docker ps --format '{{.Names}}' 2>/dev/null | grep -q '^remnawave-nginx$'; then
        print_error "Nginx не запустился. Проверьте: docker logs remnawave-nginx"
        echo
        read -e -p "$(echo -e "${DARKGRAY}Нажмите Enter для продолжения...${NC}")" _
        return
    fi

    # Открываем порт в UFW
    ufw allow 8443/tcp >/dev/null 2>&1

    echo
    print_success "Доступ по 8443 открыт"
    echo
    echo -e "${GREEN}🔗 Ссылка на панель:${NC}"
    echo -e "${WHITE}https://${panel_domain}:8443/?${COOKIE_NAME}=${COOKIE_VALUE}${NC}"
    echo
    echo -e "${RED}⚠️  Не забудьте закрыть доступ после использования!${NC}"
    echo
    read -e -p "$(echo -e "${DARKGRAY}Нажмите Enter для продолжения...${NC}")" _
}

close_panel_access() {
    clear
    echo -e "${BLUE}══════════════════════════════════════${NC}"
    echo -e "${RED}   🔒 ЗАКРЫТИЕ ДОСТУПА К ПАНЕЛИ (8443)${NC}"
    echo -e "${BLUE}══════════════════════════════════════${NC}"
    echo

    local dir="/opt/remnawave"

    # Проверяем, что nginx.conf существует
    if [ ! -f "$dir/nginx.conf" ]; then
        print_error "Файл nginx.conf не найден"
        sleep 2
        return
    fi

    # Проверяем, есть ли fallback блок 8443
    if ! grep -q "# ─── 8443 Fallback" "$dir/nginx.conf" 2>/dev/null; then
        print_warning "Доступ по 8443 уже закрыт"
        sleep 2
        return
    fi

    # Удаляем весь серверный блок для 8443 (от маркера до закрывающей скобки)
    # Используем sed для удаления блока от "# ─── 8443 Fallback" до следующего "^}"
    sed -i '/# ─── 8443 Fallback/,/^}$/d' "$dir/nginx.conf"

    # Перезапускаем nginx контейнер
    (
        cd "$dir"
        docker compose down remnawave-nginx >/dev/null 2>&1
        docker compose up -d remnawave-nginx >/dev/null 2>&1
    ) &
    show_spinner "Перезапуск nginx"

    # Проверяем, что nginx запустился
    sleep 2
    if ! docker ps --format '{{.Names}}' 2>/dev/null | grep -q '^remnawave-nginx$'; then
        print_error "Nginx не запустился. Проверьте: docker logs remnawave-nginx"
        echo
        read -e -p "$(echo -e "${DARKGRAY}Нажмите Enter для продолжения...${NC}")" _
        return
    fi

    # Закрываем порт в UFW
    if ufw status 2>/dev/null | grep -q "8443.*ALLOW"; then
        ufw delete allow 8443/tcp >/dev/null 2>&1
        ufw reload >/dev/null 2>&1
    fi

    echo
    print_success "Доступ по 8443 закрыт"
    echo
    read -e -p "$(echo -e "${DARKGRAY}Нажмите Enter для продолжения...${NC}")" _
}


manage_random_template() {
    clear
    echo -e "${BLUE}══════════════════════════════════════${NC}"
    echo -e "${GREEN}   🎨 СМЕНА ШАБЛОНА САЙТА-ЗАГЛУШКИ${NC}"
    echo -e "${BLUE}══════════════════════════════════════${NC}"
    echo

    # Показываем текущий шаблон
    if [ -f /var/www/.current_template ]; then
        local current_template
        current_template=$(cat /var/www/.current_template)
        echo -e "${WHITE}Текущий шаблон:${NC} ${YELLOW}${current_template}${NC}"
        if [ -f /var/www/.template_changed ]; then
            local changed_date
            changed_date=$(cat /var/www/.template_changed)
            echo -e "${DARKGRAY}Установлен: ${changed_date}${NC}"
        fi
        echo
    else
        echo -e "${YELLOW}Шаблон ещё не установлен${NC}"
        echo
    fi
    
    # Спрашиваем как применить шаблон
    show_arrow_menu "ВЫБЕРИТЕ СПОСОБ" \
        "🎲  Случайный шаблон" \
        "📋  Выбрать из списка" \
        "❌  Назад"
    local choice=$?
    
    case $choice in
        0)
            # Случайный шаблон
            clear
            echo -e "${BLUE}══════════════════════════════════════${NC}"
            echo -e "${GREEN}   🎲 СЛУЧАЙНЫЙ ШАБЛОН${NC}"
            echo -e "${BLUE}══════════════════════════════════════${NC}"
            echo
            randomhtml
            ;;
        1)
            # Выбор из списка
            show_arrow_menu "🎨 ВЫБЕРИТЕ ШАБЛОН" \
                "🏢  NexCore - Корпоративный портал" \
                "💻  DevForge - Технологический хаб" \
                "☁️   Nimbus - Облачные сервисы" \
                "💳  PayVault - Финтех платформа" \
                "📚  LearnHub - Образовательная платформа" \
                "🎬  StreamBox - Медиа портал" \
                "🛒  ShopWave - E-commerce" \
                "🎮  NeonArena - Игровой портал" \
                "👥  ConnectMe - Социальная сеть" \
                "📊  DataPulse - Аналитический центр" \
                "₿  CryptoNex - Крипто биржа" \
                "✈️   WanderWorld - Туристическое агентство" \
                "💪  IronPulse - Фитнес платформа" \
                "📰  ВестникПРО - Новостной портал" \
                "🎵  SoundWave - Музыкальный сервис" \
                "🏠  HomeNest - Недвижимость" \
                "🍕  FastBite - Доставка еды" \
                "🚗  AutoElite - Автомобильный портал" \
                "🎨  Prisma Studio - Дизайн студия" \
                "💼  Vertex Advisory - Консалтинг центр" \
                "❌  Назад"
            local template_choice=$?
            
            if [ $template_choice -eq 20 ]; then
                return
            fi
            
            clear
            echo -e "${BLUE}══════════════════════════════════════${NC}"
            echo -e "${GREEN}   🎨 ПРИМЕНЕНИЕ ШАБЛОНА${NC}"
            echo -e "${BLUE}══════════════════════════════════════${NC}"
            echo
            
            # Применяем выбранный шаблон (template_choice + 1)
            apply_template $((template_choice + 1))
            ;;
        2)
            return
            ;;
    esac
    
    echo

    # Перезапускаем Nginx для применения изменений
    if docker ps --filter "name=remnawave-nginx" --format "{{.Names}}" 2>/dev/null | grep -q "remnawave-nginx"; then
        (
            cd "${DIR_PANEL}" 2>/dev/null
            docker compose restart remnawave-nginx >/dev/null 2>&1
        ) &
        show_spinner "Применение изменений"
    fi

    print_success "Шаблон успешно изменён"
    echo
    read -s -n 1 -p "$(echo -e "${DARKGRAY}Нажмите Enter для продолжения${NC}")"
        echo
}

# ═══════════════════════════════════════════════
# ПРОВЕРКА ВЕРСИИ И ОБНОВЛЕНИЕ СКРИПТА
# ═══════════════════════════════════════════════
get_installed_version() {
    if [ -f "${DIR_REMNAWAVE}dfc-remna-install" ]; then
        grep -m 1 'SCRIPT_VERSION=' "${DIR_REMNAWAVE}dfc-remna-install" 2>/dev/null | cut -d'"' -f2
    else
        echo ""
    fi
}

get_remote_version() {
    # Получаем SHA последнего коммита для обхода кеша CDN
    local latest_sha
    latest_sha=$(curl -sL --max-time 5 "https://api.github.com/repos/DanteFuaran/dfc-remna-install/commits/dev" 2>/dev/null | grep -m 1 '"sha"' | cut -d'"' -f4)
    
    if [ -n "$latest_sha" ]; then
        # Используем конкретный SHA для получения актуальной версии
        curl -sL --max-time 5 "https://raw.githubusercontent.com/DanteFuaran/dfc-remna-install/$latest_sha/install_remnawave.sh" 2>/dev/null | grep -m 1 'SCRIPT_VERSION=' | cut -d'"' -f2
    else
        # Фоллбек на прямое обращение с timestamp
        curl -sL --max-time 5 "https://raw.githubusercontent.com/DanteFuaran/dfc-remna-install/dev/install_remnawave.sh?t=$(date +%s)" 2>/dev/null | grep -m 1 'SCRIPT_VERSION=' | cut -d'"' -f2
    fi
}

check_for_updates() {
    local remote_version
    remote_version=$(get_remote_version)
    
    if [ -z "$remote_version" ]; then
        return 1
    fi
    
    # Сравниваем установленную версию с удаленной
    local local_version
    local_version=$(get_installed_version)
    if [ -z "$local_version" ]; then
        local_version="$SCRIPT_VERSION"
    fi

    # Сравниваем версии: обновление доступно только если удалённая версия новее
    if [ "$remote_version" != "$local_version" ]; then
        # Проверяем что удалённая версия действительно новее
        local IFS=.
        local i remote_parts=($remote_version) local_parts=($local_version)
        for ((i=0; i<${#remote_parts[@]}; i++)); do
            local r=${remote_parts[i]:-0}
            local l=${local_parts[i]:-0}
            if (( r > l )); then
                echo "$remote_version"
                return 0
            elif (( r < l )); then
                return 1
            fi
        done
        return 1
    fi
    
    return 1
}

show_update_notification() {
    local new_version=$1
    echo
    echo -e "${YELLOW}┌──────────────────────────────────────────────────┐${NC}"
    echo -e "${YELLOW}│${NC}  ${GREEN}🔔 ДОСТУПНО ОБНОВЛЕНИЕ!${NC}                        ${YELLOW}│${NC}"
    echo -e "${YELLOW}│${NC}                                                  ${YELLOW}│${NC}"
    echo -e "${YELLOW}│${NC}  Текущая версия:  ${WHITE}v$SCRIPT_VERSION${NC}                      ${YELLOW}│${NC}"
    echo -e "${YELLOW}│${NC}  Новая версия:     ${GREEN}v$new_version${NC}                      ${YELLOW}│${NC}"
    echo -e "${YELLOW}│${NC}                                                  ${YELLOW}│${NC}"
    echo -e "${YELLOW}│${NC}  Обновите скрипт через меню:                    ${YELLOW}│${NC}"
    echo -e "${YELLOW}│${NC}  ${BLUE}🔄 Обновить скрипт${NC}                             ${YELLOW}│${NC}"
    echo -e "${YELLOW}└──────────────────────────────────────────────────┘${NC}"
    echo
}

update_script() {
    local force_update="$1"
    clear
    echo -e "${BLUE}══════════════════════════════════════${NC}"
    echo -e "${GREEN}   🔄 ОБНОВЛЕНИЕ СКРИПТА${NC}"
    echo -e "${BLUE}══════════════════════════════════════${NC}"
    echo

    local installed_version
    installed_version=$(get_installed_version)
    local remote_version
    remote_version=$(get_remote_version)
    
    if [ -n "$installed_version" ]; then
        echo -e "${WHITE}Установленная версия:${NC} v$installed_version"
    else
        echo -e "${YELLOW}Скрипт не установлен в системе${NC}"
    fi
    
    if [ -n "$remote_version" ]; then
        echo -e "${WHITE}Доступная версия:${NC}     v$remote_version"
    else
        print_error "Не удалось получить информацию о версии с GitHub"
    echo
        read -s -n 1 -p "$(echo -e "${DARKGRAY}Нажмите Enter для возврата${NC}")"
        echo
        return 1
    fi
    
    echo
    
    # Проверяем нужно ли обновление
    if [ "$force_update" != "force" ] && [ "$installed_version" = "$remote_version" ]; then
        print_success "У вас уже установлена последняя версия"
    echo
        read -s -n 1 -p "$(echo -e "${DARKGRAY}Нажмите Enter для возврата${NC}")"
        echo
        return 0
    fi

    (
        # Создаём директорию если её нет
        mkdir -p "${DIR_REMNAWAVE}"
        
        # Получаем SHA для скачивания точной версии
        local download_url="$SCRIPT_URL"
        local latest_sha
        latest_sha=$(curl -sL --max-time 5 "https://api.github.com/repos/DanteFuaran/dfc-remna-install/commits/dev" 2>/dev/null | grep -m 1 '"sha"' | cut -d'"' -f4)
        
        if [ -n "$latest_sha" ]; then
            download_url="https://raw.githubusercontent.com/DanteFuaran/dfc-remna-install/$latest_sha/install_remnawave.sh"
        fi
        
        # Скачиваем с обходом кеша
        wget -q --no-cache -O "${DIR_REMNAWAVE}dfc-remna-install" "$download_url" 2>/dev/null
        chmod +x "${DIR_REMNAWAVE}dfc-remna-install"
        ln -sf "${DIR_REMNAWAVE}dfc-remna-install" /usr/local/bin/dfc-remna-install
        ln -sf /usr/local/bin/dfc-remna-install /usr/local/bin/dfc-ri
    ) &
    show_spinner "Загрузка обновлений"

    # Проверяем успешность обновления
    local new_installed_version
    new_installed_version=$(get_installed_version)
    
    if [ "$new_installed_version" = "$remote_version" ]; then
        # Удаляем файл с информацией об обновлении и сбрасываем кеш
        rm -f "${UPDATE_AVAILABLE_FILE}" "${UPDATE_CHECK_TIME_FILE}" 2>/dev/null
        
        print_success "Скрипт успешно обновлён до версии v$new_installed_version"
    echo
        echo -e "${BLUE}══════════════════════════════════════${NC}"
        read -s -n 1 -p "$(echo -e "${DARKGRAY}Нажмите Enter для продолжения${NC}")"
        echo
        exec /usr/local/bin/dfc-remna-install
    else
        print_error "Ошибка при обновлении скрипта"
    echo
        read -s -n 1 -p "$(echo -e "${DARKGRAY}Нажмите Enter для возврата${NC}")"
        echo
        return 1
    fi
}

remove_script_all() {
    clear
    echo -e "${BLUE}══════════════════════════════════════${NC}"
    echo -e "${RED}   💣 УДАЛЕНИЕ СКРИПТА И ДАННЫХ${NC}"
    echo -e "${BLUE}══════════════════════════════════════${NC}"
    echo

    echo -e "${RED}⚠️  ВСЕ ДАННЫЕ REMNAWAVE БУДУТ УДАЛЕНЫ!${NC}"
    echo

    if ! confirm_action; then
        print_error "Операция отменена"
        sleep 2
        return 1
    fi

    echo
    (
        cd "${DIR_PANEL}" 2>/dev/null
        docker compose down -v --rmi all >/dev/null 2>&1 || true
        docker system prune -af >/dev/null 2>&1 || true
    ) &
    show_spinner "Удаление контейнеров"
    rm -rf "${DIR_PANEL}"
    rm -f /usr/local/bin/dfc-remna-install
    rm -f /usr/local/bin/dfc-ri
    rm -rf "${DIR_REMNAWAVE}"
    rm -f "${UPDATE_AVAILABLE_FILE}" "${UPDATE_CHECK_TIME_FILE}" 2>/dev/null
    cleanup_old_aliases
    print_success "Скрипт и все данные удалены"
    echo
    exit 0
}

remove_script() {
    clear
    echo -e "${BLUE}══════════════════════════════════════${NC}"
    echo -e "${RED}   🗑️ УДАЛЕНИЕ СКРИПТА${NC}"
    echo -e "${BLUE}══════════════════════════════════════${NC}"
    echo

    show_arrow_menu "УДАЛЕНИЕ СКРИПТА" \
        "🗑️   Удалить только скрипт" \
        "💣  Удалить скрипт + все данные Remnawave" \
        "──────────────────────────────────────" \
        "❌  Назад"
    local choice=$?

    case $choice in
        0)
            rm -f /usr/local/bin/dfc-remna-install
            rm -f /usr/local/bin/dfc-ri
            rm -rf "${DIR_REMNAWAVE}"
            rm -f "${UPDATE_AVAILABLE_FILE}" "${UPDATE_CHECK_TIME_FILE}" 2>/dev/null
            cleanup_old_aliases
            print_success "Скрипт удалён"
            echo
            exit 0
            ;;
        1)
            echo
            echo -e "${RED}⚠️  ВСЕ ДАННЫЕ БУДУТ УДАЛЕНЫ!${NC}"

            if confirm_action; then
                echo
                (
                    cd "${DIR_PANEL}" 2>/dev/null
                    docker compose down -v --rmi all >/dev/null 2>&1 || true
                    docker system prune -af >/dev/null 2>&1 || true
                ) &
                show_spinner "Удаление контейнеров"
                rm -rf "${DIR_PANEL}"
                rm -f /usr/local/bin/dfc-remna-install
                rm -f /usr/local/bin/dfc-ri
                rm -rf "${DIR_REMNAWAVE}"
                rm -f "${UPDATE_AVAILABLE_FILE}" "${UPDATE_CHECK_TIME_FILE}" 2>/dev/null
                cleanup_old_aliases
                print_success "Всё удалено"
                echo
                exit 0
            fi
            ;;
        2) continue ;;
        3) return ;;
    esac
}

