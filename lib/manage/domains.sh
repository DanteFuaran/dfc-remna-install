# ═══════════════════════════════════════════════
# РЕДАКТИРОВАНИЕ ДОМЕНОВ
# ═══════════════════════════════════════════════

obtain_cert_for_domain() {
    local new_domain="$1"
    local panel_dir="$2"
    local current_domain="$3"
    local -n __cert_result_ref=$4

    # Определяем cert domain для нового домена
    local _cert_dom _base_dom
    _base_dom=$(extract_domain "$new_domain")
    local parts
    parts=$(echo "$new_domain" | tr '.' '\n' | wc -l)
    if [ "$parts" -gt 2 ]; then
        _cert_dom="$_base_dom"
    else
        _cert_dom="$new_domain"
    fi

    # Определяем метод получения сертификата по текущему домену
    local cert_method
    cert_method=$(detect_cert_method "$current_domain")

    # Проверяем наличие сертификата для нового домена
    if [ -d "/etc/letsencrypt/live/${_cert_dom}" ] || [ -d "/etc/letsencrypt/live/${new_domain}" ]; then
        print_success "SSL-сертификат для ${new_domain} уже существует"
        if [ -d "/etc/letsencrypt/live/${new_domain}" ]; then
            __cert_result_ref="$new_domain"
        else
            __cert_result_ref="$_cert_dom"
        fi
        return 0
    fi

    # Нужно получить новый сертификат
    if [ "$cert_method" = "1" ] && [ -f "/etc/letsencrypt/cloudflare.ini" ]; then
        (
            certbot certonly --dns-cloudflare \
                --dns-cloudflare-credentials /etc/letsencrypt/cloudflare.ini \
                --dns-cloudflare-propagation-seconds 30 \
                -d "$_cert_dom" -d "*.$_cert_dom" \
                --agree-tos --register-unsafely-without-email --non-interactive \
                --key-type ecdsa >/dev/null 2>&1
        ) &
        show_spinner "Получение wildcard сертификата для *.$_cert_dom"
    else
        (
            cd "$panel_dir"
            docker compose stop remnawave-nginx >/dev/null 2>&1
        ) &
        show_spinner "Остановка nginx"

        (
            ufw allow 80/tcp >/dev/null 2>&1
        ) &
        show_spinner "Открытие порта 80"

        (
            certbot certonly --standalone \
                -d "$new_domain" \
                --agree-tos --register-unsafely-without-email --non-interactive \
                --http-01-port 80 \
                --key-type ecdsa >/dev/null 2>&1
        ) &
        show_spinner "Получение SSL-сертификата для $new_domain"

        (
            ufw delete allow 80/tcp >/dev/null 2>&1
            ufw reload >/dev/null 2>&1
        ) &
        show_spinner "Закрытие порта 80"

        _cert_dom="$new_domain"
    fi

    # Проверяем, получен ли сертификат
    if [ ! -d "/etc/letsencrypt/live/${_cert_dom}" ]; then
        print_error "Не удалось получить сертификат для ${new_domain}"
        echo -e "${WHITE}Убедитесь что DNS-записи для ${YELLOW}${new_domain}${WHITE} настроены правильно.${NC}"
        echo
        (
            cd "$panel_dir"
            docker compose start remnawave-nginx >/dev/null 2>&1
        ) &
        show_spinner "Запуск nginx"
        echo
        return 1
    fi

    print_success "SSL-сертификат получен"

    local cron_rule="0 3 * * * certbot renew --quiet --deploy-hook 'cd ${panel_dir} && docker compose restart remnawave-nginx' 2>/dev/null"
    if ! crontab -l 2>/dev/null | grep -q "certbot renew"; then
        (crontab -l 2>/dev/null; echo "$cron_rule") | crontab -
    fi

    __cert_result_ref="$_cert_dom"
    return 0
}

change_panel_domain() {
    clear
    echo -e "${BLUE}══════════════════════════════════════${NC}"
    echo -e "${GREEN}   🌐 СМЕНА ДОМЕНА ПАНЕЛИ${NC}"
    echo -e "${BLUE}══════════════════════════════════════${NC}"
    echo

    local panel_dir
    if ! panel_dir=$(detect_remnawave_path); then
        echo
        read -s -n 1 -p "$(echo -e "${DARKGRAY}Нажмите Enter для возврата${NC}")"
        echo
        return 1
    fi

    local current_domain
    current_domain=$(grep -oP 'server_name\s+\K[^;]+' "${panel_dir}/nginx.conf" | head -1)
    echo -e "${WHITE}Текущий домен панели:${NC} ${YELLOW}${current_domain}${NC}"
    echo

    local new_domain
    if ! prompt_domain_with_retry "Введите новый домен панели:" new_domain; then
        return 0
    fi

    new_domain=$(echo "$new_domain" | sed 's|https\?://||;s|/.*||')

    echo -e "${DARKGRAY}──────────────────────────────────────${NC}"
    echo
    echo -e "${WHITE}Текущий домен:${NC} ${YELLOW}${current_domain}${NC}"
    echo -e "${WHITE}Новый домен:${NC}   ${GREEN}${new_domain}${NC}"

    if ! confirm_action; then
        print_error "Операция отменена"
        sleep 2
        return 0
    fi

    echo -e "${DARKGRAY}──────────────────────────────────────${NC}"

    local new_cert_domain=""
    if ! obtain_cert_for_domain "$new_domain" "$panel_dir" "$current_domain" new_cert_domain; then
        echo
        read -s -n 1 -p "$(echo -e "${DARKGRAY}Нажмите Enter для возврата${NC}")"
        echo
        return 1
    fi

    local old_cert_domain
    old_cert_domain=$(grep -oP 'ssl_certificate\s+"/etc/letsencrypt/live/\K[^/]+' "${panel_dir}/nginx.conf" | head -1)

    local boundary
    boundary=$(grep -nP '^\s*server_name\s' "${panel_dir}/nginx.conf" | sed -n '2p' | cut -d: -f1)

    if [ -n "$old_cert_domain" ] && [ "$old_cert_domain" != "$new_cert_domain" ]; then
        if [ -n "$boundary" ]; then
            sed -i "1,${boundary}s|/etc/letsencrypt/live/${old_cert_domain}/|/etc/letsencrypt/live/${new_cert_domain}/|g" "${panel_dir}/nginx.conf"
        else
            sed -i "s|/etc/letsencrypt/live/${old_cert_domain}/|/etc/letsencrypt/live/${new_cert_domain}/|g" "${panel_dir}/nginx.conf"
        fi
    fi
    sed -i "s|server_name ${current_domain}|server_name ${new_domain}|g" "${panel_dir}/nginx.conf"
    
    (sleep 0.3) &
    show_spinner "Обновление nginx.conf"

    (
        if [ -f "${panel_dir}/.env" ]; then
            sed -i "s|^FRONT_END_DOMAIN=.*|FRONT_END_DOMAIN=${new_domain}|" "${panel_dir}/.env"
        fi
    ) &
    show_spinner "Обновление .env"

    (
        cd "$panel_dir"
        docker compose down >/dev/null 2>&1
        docker compose up -d >/dev/null 2>&1
    ) &
    show_spinner "Перезапуск сервисов"

    local OLD_COOKIE_NAME OLD_COOKIE_VALUE NEW_COOKIE_NAME NEW_COOKIE_VALUE
    if get_cookie_from_nginx; then
        OLD_COOKIE_NAME="$COOKIE_NAME"
        OLD_COOKIE_VALUE="$COOKIE_VALUE"
        
        NEW_COOKIE_NAME=$(generate_cookie_key)
        NEW_COOKIE_VALUE=$(generate_cookie_key)
        
        sed -i "s|~\*${OLD_COOKIE_NAME}=${OLD_COOKIE_VALUE}|~*${NEW_COOKIE_NAME}=${NEW_COOKIE_VALUE}|g" "${panel_dir}/nginx.conf"
        sed -i "s|\$arg_${OLD_COOKIE_NAME}|\$arg_${NEW_COOKIE_NAME}|g" "${panel_dir}/nginx.conf"
        sed -i "s|    \"[^\"]*\" \"${OLD_COOKIE_NAME}=${OLD_COOKIE_VALUE}; Path=|    \"${NEW_COOKIE_VALUE}\" \"${NEW_COOKIE_NAME}=${NEW_COOKIE_VALUE}; Path=|g" "${panel_dir}/nginx.conf"
        sed -i "s|\"${OLD_COOKIE_VALUE}\" 1|\"${NEW_COOKIE_VALUE}\" 1|g" "${panel_dir}/nginx.conf"
        
        (
            cd "$panel_dir"
            docker compose restart remnawave-nginx >/dev/null 2>&1
        ) &
        show_spinner "Обновление cookie доступа"
    fi

    echo
    print_success "Домен панели изменён на ${new_domain}"

    echo
    echo -e "${DARKGRAY}──────────────────────────────────────${NC}"
    echo -e "${GREEN}🔗 Ссылка на панель:${NC}"
    if [ -n "$NEW_COOKIE_NAME" ] && [ -n "$NEW_COOKIE_VALUE" ]; then
        echo -e "${WHITE}https://${new_domain}/auth/login?${NEW_COOKIE_NAME}=${NEW_COOKIE_VALUE}${NC}"
    else
        get_cookie_from_nginx
        echo -e "${WHITE}https://${new_domain}/auth/login?${COOKIE_NAME}=${COOKIE_VALUE}${NC}"
    fi
    echo -e "${BLUE}══════════════════════════════════════${NC}"
    read -s -n 1 -p "$(echo -e "${DARKGRAY}Нажмите Enter для продолжения${NC}")"
    echo
}

change_sub_domain() {
    clear
    echo -e "${BLUE}══════════════════════════════════════${NC}"
    echo -e "${GREEN}   🌐 СМЕНА ДОМЕНА СТРАНИЦЫ ПОДПИСКИ${NC}"
    echo -e "${BLUE}══════════════════════════════════════${NC}"
    echo

    local panel_dir
    if ! panel_dir=$(detect_remnawave_path); then
        echo
        read -s -n 1 -p "$(echo -e "${DARKGRAY}Нажмите Enter для возврата${NC}")"
        echo
        return 1
    fi

    local current_sub_domain
    current_sub_domain=$(grep -oP '^SUB_PUBLIC_DOMAIN=\K.*' "${panel_dir}/.env" 2>/dev/null)
    if [ -z "$current_sub_domain" ]; then
        current_sub_domain=$(grep -oP 'server_name\s+\K[^;]+' "${panel_dir}/nginx.conf" | sed -n '2p')
    fi
    echo -e "${WHITE}Текущий домен подписки:${NC} ${YELLOW}${current_sub_domain}${NC}"
    echo

    local new_domain
    if ! prompt_domain_with_retry "Введите новый домен страницы подписки:" new_domain; then
        return 0
    fi

    new_domain=$(echo "$new_domain" | sed 's|https\?://||;s|/.*||')

    echo
    echo -e "${WHITE}Текущий домен:${NC} ${YELLOW}${current_sub_domain}${NC}"
    echo -e "${WHITE}Новый домен:${NC}   ${GREEN}${new_domain}${NC}"

    if ! confirm_action; then
        print_error "Операция отменена"
        sleep 2
        return 0
    fi

    echo

    local new_cert_domain=""
    if ! obtain_cert_for_domain "$new_domain" "$panel_dir" "$current_sub_domain" new_cert_domain; then
        echo
        read -s -n 1 -p "$(echo -e "${DARKGRAY}Нажмите Enter для возврата${NC}")"
        echo
        return 1
    fi

    local old_sub_cert_domain
    old_sub_cert_domain=$(grep -A5 "server_name.*${current_sub_domain}" "${panel_dir}/nginx.conf" 2>/dev/null | grep -oP '/etc/letsencrypt/live/\K[^/]+' | head -1)

    local start_line end_line
    start_line=$(grep -nP '^\s*server_name\s' "${panel_dir}/nginx.conf" | sed -n '2p' | cut -d: -f1)
    end_line=$(grep -nP '^\s*server_name\s' "${panel_dir}/nginx.conf" | sed -n '3p' | cut -d: -f1)

    if [ -n "$old_sub_cert_domain" ] && [ "$old_sub_cert_domain" != "$new_cert_domain" ]; then
        if [ -n "$start_line" ] && [ -n "$end_line" ]; then
            sed -i "${start_line},${end_line}s|/etc/letsencrypt/live/${old_sub_cert_domain}/|/etc/letsencrypt/live/${new_cert_domain}/|g" "${panel_dir}/nginx.conf"
        elif [ -n "$start_line" ]; then
            sed -i "${start_line},\$s|/etc/letsencrypt/live/${old_sub_cert_domain}/|/etc/letsencrypt/live/${new_cert_domain}/|g" "${panel_dir}/nginx.conf"
        fi
    fi
    sed -i "s|server_name ${current_sub_domain}|server_name ${new_domain}|g" "${panel_dir}/nginx.conf"
    
    (sleep 0.3) &
    show_spinner "Обновление nginx.conf"

    (
        if [ -f "${panel_dir}/.env" ]; then
            sed -i "s|^SUB_PUBLIC_DOMAIN=.*|SUB_PUBLIC_DOMAIN=${new_domain}|" "${panel_dir}/.env"
        fi
    ) &
    show_spinner "Обновление .env"

    (
        cd "$panel_dir"
        docker compose down >/dev/null 2>&1
        docker compose up -d >/dev/null 2>&1
    ) &
    show_spinner "Перезапуск сервисов"

    echo
    print_success "Домен страницы подписки изменён на ${new_domain}"
    echo
    read -s -n 1 -p "$(echo -e "${DARKGRAY}Нажмите Enter для возврата${NC}")"
    echo
}

change_node_domain() {
    clear
    echo -e "${BLUE}══════════════════════════════════════${NC}"
    echo -e "${GREEN}   🌐 СМЕНА ДОМЕНА НОДЫ${NC}"
    echo -e "${BLUE}══════════════════════════════════════${NC}"
    echo

    local panel_dir
    if ! panel_dir=$(detect_remnawave_path); then
        echo
        read -s -n 1 -p "$(echo -e "${DARKGRAY}Нажмите Enter для возврата${NC}")"
        echo
        return 1
    fi

    local current_node_domain
    current_node_domain=$(grep -oP 'server_name\s+\K[^;]+' "${panel_dir}/nginx.conf" | grep -v '^_$' | sed -n '3p')

    if [ -z "$current_node_domain" ]; then
        echo -e "${YELLOW}⚠️  Нода не обнаружена в конфигурации nginx.${NC}"
        echo -e "${WHITE}Смена домена ноды доступна только при установке${NC}"
        echo -e "${WHITE}типа \"Панель + Нода\" на одном сервере.${NC}"
        echo
        read -s -n 1 -p "$(echo -e "${DARKGRAY}Нажмите Enter для возврата${NC}")"
        echo
        return 1
    fi

    echo -e "${WHITE}Текущий домен ноды:${NC} ${YELLOW}${current_node_domain}${NC}"
    echo

    local new_domain
    if ! prompt_domain_with_retry "Введите новый домен ноды:" new_domain; then
        return 0
    fi

    new_domain=$(echo "$new_domain" | sed 's|https\?://||;s|/.*||')

    echo
    echo -e "${WHITE}Текущий домен:${NC} ${YELLOW}${current_node_domain}${NC}"
    echo -e "${WHITE}Новый домен:${NC}   ${GREEN}${new_domain}${NC}"

    if ! confirm_action; then
        print_error "Операция отменена"
        sleep 2
        return 0
    fi

    echo

    local new_cert_domain=""
    if ! obtain_cert_for_domain "$new_domain" "$panel_dir" "$current_node_domain" new_cert_domain; then
        echo
        read -s -n 1 -p "$(echo -e "${DARKGRAY}Нажмите Enter для возврата${NC}")"
        echo
        return 1
    fi

    local old_node_cert_domain
    old_node_cert_domain=$(grep -A5 "server_name.*${current_node_domain}" "${panel_dir}/nginx.conf" 2>/dev/null | grep -oP '/etc/letsencrypt/live/\K[^/]+' | head -1)

    local start_line
    start_line=$(grep -n "server_name" "${panel_dir}/nginx.conf" | grep -v '_' | sed -n '3p' | cut -d: -f1)

    if [ -n "$old_node_cert_domain" ] && [ "$old_node_cert_domain" != "$new_cert_domain" ]; then
        if [ -n "$start_line" ]; then
            sed -i "${start_line},\$s|/etc/letsencrypt/live/${old_node_cert_domain}/|/etc/letsencrypt/live/${new_cert_domain}/|g" "${panel_dir}/nginx.conf"
        fi
    fi
    sed -i "s|server_name ${current_node_domain}|server_name ${new_domain}|g" "${panel_dir}/nginx.conf"
    
    (sleep 0.3) &
    show_spinner "Обновление nginx.conf"

    (
        if [ -f "${panel_dir}/docker-compose.yml" ] && grep -q "${current_node_domain}" "${panel_dir}/docker-compose.yml" 2>/dev/null; then
            sed -i "s|${current_node_domain}|${new_domain}|g" "${panel_dir}/docker-compose.yml"
        fi
    ) &
    show_spinner "Обновление docker-compose.yml"

    (
        cd "$panel_dir"
        docker compose down >/dev/null 2>&1
        docker compose up -d >/dev/null 2>&1
    ) &
    show_spinner "Перезапуск сервисов"

    echo
    print_success "Домен ноды изменён на ${new_domain}"
    echo
    echo -e "${YELLOW}⚠️  Не забудьте обновить домен ноды в панели Remnawave${NC}"
    echo
    read -s -n 1 -p "$(echo -e "${DARKGRAY}Нажмите Enter для возврата${NC}")"
    echo
}

manage_domains() {
    clear
    echo -e "${BLUE}══════════════════════════════════════${NC}"
    echo -e "${GREEN}   🌐 РЕДАКТИРОВАНИЕ ДОМЕНОВ${NC}"
    echo -e "${BLUE}══════════════════════════════════════${NC}"
    echo

    local panel_dir
    if ! panel_dir=$(detect_remnawave_path); then
        echo
        read -s -n 1 -p "$(echo -e "${DARKGRAY}Нажмите Enter для возврата${NC}")"
        echo
        return 1
    fi

    local current_panel
    current_panel=$(grep -oP 'server_name\s+\K[^;]+' "${panel_dir}/nginx.conf" | head -1)
    local current_sub
    current_sub=$(grep -oP '^SUB_PUBLIC_DOMAIN=\K.*' "${panel_dir}/.env" 2>/dev/null)
    if [ -z "$current_sub" ]; then
        current_sub=$(grep -oP 'server_name\s+\K[^;]+' "${panel_dir}/nginx.conf" | sed -n '2p')
    fi
    local current_node
    current_node=$(grep -oP 'server_name\s+\K[^;]+' "${panel_dir}/nginx.conf" | grep -v '^_$' | sed -n '3p')

    echo -e "${WHITE}Домен панели:${NC}   ${YELLOW}${current_panel:-не задан}${NC}"
    echo -e "${WHITE}Домен подписки:${NC} ${YELLOW}${current_sub:-не задан}${NC}"
    if [ -n "$current_node" ]; then
        echo -e "${WHITE}Домен ноды:${NC}     ${YELLOW}${current_node}${NC}"
    fi
    echo

    show_arrow_menu "РЕДАКТИРОВАНИЕ ДОМЕНОВ" \
        "🌐  Сменить домен панели" \
        "🌐  Сменить домен страницы подписки" \
        "🌐  Сменить домен ноды" \
        "──────────────────────────────────────" \
        "❌  Назад"
    local choice=$?

    case $choice in
        0) change_panel_domain ;;
        1) change_sub_domain ;;
        2) change_node_domain ;;
        3) : ;;
        4) return ;;
    esac
}
