# ═══════════════════════════════════════════════════
# УДАЛЕНИЕ/ДОБАВЛЕНИЕ НОДЫ
# ═══════════════════════════════════════════════════

remove_node_from_panel() {
    # Гарантируем, что мы в корне или в /opt/remnawave
    cd /opt/remnawave 2>/dev/null || cd / 2>/dev/null
    
    clear
    echo -e "${BLUE}══════════════════════════════════════${NC}"
    echo -e "${RED}   🗑️  УДАЛЕНИЕ НОДЫ С СЕРВЕРА ПАНЕЛИ${NC}"
    echo -e "${BLUE}══════════════════════════════════════${NC}"
    echo

    if ! grep -q "remnanode:" /opt/remnawave/docker-compose.yml 2>/dev/null; then
        print_error "Нода не найдена на этом сервере"
        echo -e "${YELLOW}На сервере установлена только панель.${NC}"
        echo
        read -s -n 1 -p "$(echo -e "${DARKGRAY}Нажмите любую клавишу для продолжения...${NC}")"
        echo
        return 1
    fi

    echo -e "${YELLOW}⚠️  ВНИМАНИЕ!${NC}"
    echo -e "${WHITE}Эта операция удалит ноду с сервера и настроит панель${NC}"
    echo -e "${WHITE}для работы на стандартном порту 443.${NC}"
    echo
    echo -e "${RED}После удаления ноды:${NC}"
    echo -e "  ${GREEN}✓${NC} Панель будет доступна по https (порт 443)"
    echo -e "  ${GREEN}✓${NC} Порт 8443 будет закрыт"
    echo -e "  ${RED}✗${NC} VPN через эту ноду перестанет работать"
    echo

    if ! confirm_action; then
        print_error "Операция отменена"
        sleep 2
        return 1
    fi

    local panel_domain sub_domain panel_cert sub_cert COOKIE_NAME COOKIE_VALUE
    panel_domain=$(grep -oP 'server_name\s+\K[^;]+' /opt/remnawave/nginx.conf | sed -n '1p')
    sub_domain=$(grep -oP 'server_name\s+\K[^;]+' /opt/remnawave/nginx.conf | sed -n '2p')
    
    get_cookie_from_nginx
    
    panel_cert=$(grep -A5 "server_name ${panel_domain};" /opt/remnawave/nginx.conf | grep -oP '/ssl/\K[^/]+' | head -1)
    sub_cert=$(grep -A5 "server_name ${sub_domain};" /opt/remnawave/nginx.conf | grep -oP '/ssl/\K[^/]+' | head -1)
    [ -z "$panel_cert" ] && panel_cert="$panel_domain"
    [ -z "$sub_cert" ] && sub_cert="$sub_domain"

    echo
    print_action "Остановка сервисов..."
    (
        cd /opt/remnawave
        docker compose down >/dev/null 2>&1
    ) &
    show_spinner "Остановка контейнеров"

    print_action "Удаление ноды из конфигурации..."
    
    cp /opt/remnawave/docker-compose.yml /opt/remnawave/docker-compose.yml.bak 2>/dev/null || true
    cp /opt/remnawave/.env /opt/remnawave/.env.bak 2>/dev/null || true
    
    generate_docker_compose_panel "$panel_cert" "$sub_cert"
    
    local existing_api_token
    existing_api_token=$(grep -oP '^REMNAWAVE_API_TOKEN=\K\S+' /opt/remnawave/.env.bak 2>/dev/null | head -1)
    if [ -n "$existing_api_token" ]; then
        sed -i "s|^REMNAWAVE_API_TOKEN=.*|REMNAWAVE_API_TOKEN=$existing_api_token|" /opt/remnawave/.env
    fi
    
    rm -f /opt/remnawave/docker-compose.yml.bak /opt/remnawave/.env.bak 2>/dev/null || true

    print_action "Настройка nginx для порта 443..."
    
    generate_nginx_conf_panel "$panel_domain" "$sub_domain" "$panel_cert" "$sub_cert" "$COOKIE_NAME" "$COOKIE_VALUE"

    print_action "Закрытие порта 8443..."
    if ufw status 2>/dev/null | grep -q "8443.*ALLOW"; then
        ufw delete allow 8443/tcp >/dev/null 2>&1
    fi

    print_action "Запуск сервисов..."
    (
        cd /opt/remnawave
        docker compose up -d >/dev/null 2>&1
    ) &
    show_spinner "Запуск контейнеров"

    show_spinner_timer 15 "Ожидание запуска панели" "Запуск панели"

    if curl -s -f http://127.0.0.1:3000/api/auth/status >/dev/null 2>&1; then
        print_success "Панель запущена и работает"
    fi

    clear
    echo
    echo -e "${BLUE}══════════════════════════════════════${NC}"
    echo -e "    ${GREEN}🎉 Нода удалена, панель настроена!${NC}"
    echo -e "${BLUE}══════════════════════════════════════${NC}"
    echo
    echo -e "${WHITE}Панель теперь доступна по:${NC}"
    echo -e "${GREEN}https://${panel_domain}/auth/login?${COOKIE_NAME}=${COOKIE_VALUE}${NC}"
    echo
    echo -e "${DARKGRAY}Порт 443 активен, порт 8443 закрыт${NC}"
    echo
    read -s -n 1 -p "$(echo -e "${DARKGRAY}Нажмите любую клавишу для продолжения...${NC}")"
    echo
}

add_node_to_panel() {
    if [ ! -f "/opt/remnawave/docker-compose.yml" ] || [ ! -f "/opt/remnawave/nginx.conf" ]; then
        print_error "Панель Remnawave не найдена на этом сервере"
        echo -e "${YELLOW}Эта функция регистрирует ноду на удалённом сервере в панели.${NC}"
        echo -e "${YELLOW}Панель должна быть установлена на этом сервере.${NC}"
        echo
        read -s -n 1 -p "$(echo -e "${DARKGRAY}Нажмите любую клавишу для продолжения...${NC}")"
        echo
        return
    fi

    local domain_url="127.0.0.1:3000"

    clear
    echo -e "${BLUE}══════════════════════════════════════${NC}"
    echo -e "${GREEN}     ➕  Подключение ноды в панель${NC}"
    echo -e "${BLUE}══════════════════════════════════════${NC}"
    echo
    echo -e "${DARKGRAY}⚠️  Добавление ноды в панель предназначена для запуска${NC}"
    echo -e "${DARKGRAY}   на сервере с установленной панелью Remnawave.${NC}"
    echo
    echo -e "${DARKGRAY}   После завершения подключения, запустите установку${NC}"
    echo -e "${DARKGRAY}   ноды (Только нода) на сервере ноды.${NC}"
    echo
    echo -e "${BLUE}══════════════════════════════════════${NC}"
    echo -e "${DARKGRAY}  Enter: Подтвердить     Esc: Отмена${NC}"
    echo
    if ! get_panel_token; then
        print_error "Не удалось получить токен"
        echo
        read -s -n 1 -p "$(echo -e "${DARKGRAY}Нажмите любую клавишу для продолжения...${NC}")"
        echo
        return
    fi
    local token
    token=$(cat "${DIR_REMNAWAVE}/token")

    local SELFSTEAL_DOMAIN=""
    local entity_name=""
    local _step=1

    while true; do
        if [[ $_step -eq 1 ]]; then
            reading_inline "Введите selfsteal домен для ноды (например, node.example.com):" SELFSTEAL_DOMAIN
            local _rc_sd=$?
            if [[ $_rc_sd -eq 2 ]]; then
                return
            fi
            if [[ -z "$SELFSTEAL_DOMAIN" ]]; then continue; fi
            if check_node_domain "$domain_url" "$token" "$SELFSTEAL_DOMAIN"; then
                _step=2
            else
                echo -e "${YELLOW}Пожалуйста, используйте другой домен${NC}"
            fi
        else
            reading_inline "Введите имя для вашей ноды (например, Germany):" entity_name
            local _rc_en=$?
            if [[ $_rc_en -eq 2 ]]; then
                _step=1
                SELFSTEAL_DOMAIN=""
                continue
            fi
            if [[ -z "$entity_name" ]]; then continue; fi
            if [[ "$entity_name" =~ ^[a-zA-Z0-9-]+$ ]]; then
                if [ ${#entity_name} -ge 3 ] && [ ${#entity_name} -le 20 ]; then
                    local response
                    response=$(make_api_request "GET" "$domain_url/api/config-profiles" "$token")
                    if echo "$response" | jq -e ".response.configProfiles[] | select(.name == \"$entity_name\")" >/dev/null 2>&1; then
                        print_error "Имя конфигурационного профиля '$entity_name' уже используется. Выберите другое."
                    else
                        break
                    fi
                else
                    print_error "Имя должно содержать от 3 до 20 символов"
                fi
            else
                print_error "Имя должно содержать только английские буквы, цифры и дефис"
            fi
        fi
    done

    echo
    print_action "Генерация REALITY ключей..."
    local private_key
    private_key=$(generate_xray_keys "$domain_url" "$token")
    if [ -z "$private_key" ]; then
        print_error "Не удалось сгенерировать ключи"
        return 1
    fi
    print_success "Ключи сгенерированы"

    print_action "Создание конфиг-профиля ($entity_name)..."
    local config_result config_profile_uuid inbound_uuid
    if ! config_result=$(create_config_profile "$domain_url" "$token" "$entity_name" "$SELFSTEAL_DOMAIN" "$private_key" "$entity_name"); then
        print_error "Не удалось создать конфигурационный профиль"
        return 1
    fi
    read config_profile_uuid inbound_uuid <<< "$config_result"
    print_success "Конфигурационный профиль: $entity_name"

    print_action "Создание ноды ($entity_name)..."
    if create_node "$domain_url" "$token" "$config_profile_uuid" "$inbound_uuid" "$SELFSTEAL_DOMAIN" "$entity_name"; then
        print_success "Нода создана"
    else
        print_error "Не удалось создать ноду"
        return 1
    fi

    print_action "Создание хоста ($SELFSTEAL_DOMAIN)..."
    create_host "$domain_url" "$token" "$config_profile_uuid" "$inbound_uuid" "$entity_name" "$SELFSTEAL_DOMAIN"
    print_success "Хост зарегистрирован"

    print_action "Настройка сквадов..."
    local squad_uuids
    squad_uuids=$(get_default_squad "$domain_url" "$token")
    if [ -n "$squad_uuids" ]; then
        while IFS= read -r squad_uuid; do
            [ -z "$squad_uuid" ] && continue
            update_squad "$domain_url" "$token" "$squad_uuid" "$inbound_uuid"
        done <<< "$squad_uuids"
        print_success "Сквады обновлены"
    else
        echo -e "${YELLOW}⚠️  Сквады не найдены (будут настроены при создании пользователей)${NC}"
    fi

    echo
    print_success "Нода успешно зарегистрирована в панели!"
    echo
    echo -e "${RED}─────────────────────────────────────────────────${NC}"
    echo -e "${YELLOW}Для завершения установки ноды:${NC}"
    echo -e "${WHITE}1. Запустите этот скрипт на сервере, где будет установлена нода${NC}"
    echo -e "${WHITE}2. Выберите \"Установить компоненты\" → \"Только нода\"${NC}"
    echo -e "${RED}─────────────────────────────────────────────────${NC}"
    echo
    read -s -n 1 -p "$(echo -e "${DARKGRAY}Нажмите любую клавишу для продолжения...${NC}")"
    echo
}
