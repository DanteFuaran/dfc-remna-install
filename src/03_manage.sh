# ═══════════════════════════════════════════════
# БАЗА ДАННЫХ: ОПРЕДЕЛЕНИЕ ПУТИ К REMNAWAVE
# ═══════════════════════════════════════════════
detect_remnawave_path() {
    local panel_dir="/opt/remnawave"

    if [ -f "${panel_dir}/docker-compose.yml" ]; then
        echo "$panel_dir"
        return 0
    fi

    echo
    echo -e "${YELLOW}⚠️  Remnawave не найдена по стандартному пути ${WHITE}/opt/remnawave${NC}"
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

# ═══════════════════════════════════════════════
# БАЗА ДАННЫХ: СОХРАНЕНИЕ ДАМПА
# ═══════════════════════════════════════════════
db_backup() {
    clear
    echo -e "${BLUE}══════════════════════════════════════${NC}"
    echo -e "${GREEN}   💾 СОХРАНЕНИЕ БАЗЫ ДАННЫХ${NC}"
    echo -e "${BLUE}══════════════════════════════════════${NC}"
    echo

    local panel_dir
    panel_dir=$(detect_remnawave_path)
    if [ $? -ne 0 ]; then
        echo
        read -s -n 1 -p "$(echo -e "${DARKGRAY}Нажмите Enter для возврата${NC}")"
        echo
        return 1
    fi

    # Проверяем что контейнер БД запущен
    if ! docker ps --filter "name=remnawave-db" --format "{{.Names}}" 2>/dev/null | grep -q "remnawave-db"; then
        print_error "Контейнер remnawave-db не запущен"
        echo
        read -s -n 1 -p "$(echo -e "${DARKGRAY}Нажмите Enter для возврата${NC}")"
        echo
        return 1
    fi

    local backup_dir="${panel_dir}/backups"
    mkdir -p "$backup_dir"

    local timestamp
    timestamp=$(date +%d.%m.%y)
    local dump_file="${backup_dir}/backup_remnawave_${timestamp}.sql.gz"

    # Если файл с таким именем уже существует, добавляем время
    if [ -f "$dump_file" ]; then
        timestamp=$(date +%d.%m.%y_%H-%M-%S)
        dump_file="${backup_dir}/backup_remnawave_${timestamp}.sql.gz"
    fi

    echo -e "${WHITE}Директория бэкапа:${NC} ${DARKGRAY}${backup_dir}${NC}"
    echo

    (
        docker exec remnawave-db pg_dump -U postgres -d postgres 2>/dev/null | gzip > "$dump_file"
    ) &
    show_spinner "Создание дампа базы данных"

    if [ -f "$dump_file" ] && [ -s "$dump_file" ]; then
        local file_size
        file_size=$(du -h "$dump_file" | cut -f1)
        echo
        print_success "Дамп успешно сохранён"
        echo
        echo -e "${WHITE}Файл:${NC}    ${DARKGRAY}${dump_file}${NC}"
        echo -e "${WHITE}Размер:${NC}  ${DARKGRAY}${file_size}${NC}"
    else
        print_error "Не удалось создать дамп базы данных"
        rm -f "$dump_file" 2>/dev/null
    fi

    echo
    read -s -n 1 -p "$(echo -e "${DARKGRAY}Нажмите Enter для возврата${NC}")"
    echo
}

# ═══════════════════════════════════════════════
# БАЗА ДАННЫХ: ЗАГРУЗКА ДАМПА
# ═══════════════════════════════════════════════
db_restore() {
    clear
    echo -e "${BLUE}══════════════════════════════════════${NC}"
    echo -e "${GREEN}   📥 ЗАГРУЗКА БАЗЫ ДАННЫХ${NC}"
    echo -e "${BLUE}══════════════════════════════════════${NC}"
    echo

    local panel_dir
    panel_dir=$(detect_remnawave_path)
    if [ $? -ne 0 ]; then
        echo
        read -s -n 1 -p "$(echo -e "${DARKGRAY}Нажмите Enter для возврата${NC}")"
        echo
        return 1
    fi

    # Проверяем что контейнер БД запущен
    if ! docker ps --filter "name=remnawave-db" --format "{{.Names}}" 2>/dev/null | grep -q "remnawave-db"; then
        print_error "Контейнер remnawave-db не запущен"
        echo
        read -s -n 1 -p "$(echo -e "${DARKGRAY}Нажмите Enter для возврата${NC}")"
        echo
        return 1
    fi

    local backup_dir="${panel_dir}/backups"

    # Ищем дампы в папке backups
    if [ ! -d "$backup_dir" ] || ! compgen -G "$backup_dir/*.sql.gz" > /dev/null 2>&1; then
        echo -e "${YELLOW}⚠️  Дампы не найдены в ${WHITE}${backup_dir}${NC}"
        echo
        echo -e "${WHITE}Поместите файл дампа (.sql.gz) в эту папку${NC}"
        echo -e "${WHITE}или укажите путь к файлу вручную.${NC}"
        echo

        reading "Путь к файлу бэкапа (или Enter для отмены):" custom_dump_path

        if [ -z "$custom_dump_path" ]; then
            return 0
        fi

        if [ ! -f "$custom_dump_path" ]; then
            print_error "Файл не найден: ${custom_dump_path}"
            echo
            read -s -n 1 -p "$(echo -e "${DARKGRAY}Нажмите Enter для возврата${NC}")"
            echo
            return 1
        fi

        # Копируем файл в папку бэкапов
        mkdir -p "$backup_dir"
        cp "$custom_dump_path" "$backup_dir/"
    fi

    # Собираем список бэкапов
    local dump_files=()
    local menu_items=()
    while IFS= read -r file; do
        dump_files+=("$file")
        local fname
        fname=$(basename "$file")
        local fsize
        fsize=$(du -h "$file" | cut -f1)
        menu_items+=("📄  ${fname} (${fsize})")
    done < <(find "$backup_dir" -maxdepth 1 -name "*.sql.gz" | sort -r)

    if [ ${#dump_files[@]} -eq 0 ]; then
        print_error "Файлы бэкапов не найдены"
        echo
        read -s -n 1 -p "$(echo -e "${DARKGRAY}Нажмите Enter для возврата${NC}")"
        echo
        return 1
    fi

    menu_items+=("──────────────────────────────────────")
    menu_items+=("❌  Назад")

    show_arrow_menu "ВЫБЕРИТЕ БЭКАП ДЛЯ ЗАГРУЗКИ" "${menu_items[@]}"
    local choice=$?

    # Проверка — выбран ли разделитель или "Назад"
    if [ $choice -ge ${#dump_files[@]} ]; then
        return 0
    fi

    local selected_dump="${dump_files[$choice]}"
    local selected_name
    selected_name=$(basename "$selected_dump")

    clear
    echo -e "${BLUE}══════════════════════════════════════${NC}"
    echo -e "${GREEN}   📥 ЗАГРУЗКА БАЗЫ ДАННЫХ${NC}"
    echo -e "${BLUE}══════════════════════════════════════${NC}"
    echo
    echo -e "${WHITE}Файл:${NC} ${DARKGRAY}${selected_name}${NC}"
    echo
    echo -e "${DARKGRAY}──────────────────────────────────────${NC}"
    echo -e "${YELLOW}⚠️  ВНИМАНИЕ!${NC}"
    echo -e "${WHITE}Все текущие данные панели будут потеряны.${NC}"
    echo -e "${WHITE}Логин и пароль для входа в панель будут сброшены.${NC}"

    if ! confirm_action; then
        print_error "Операция отменена"
        sleep 2
        return 0
    fi

    echo -e "${DARKGRAY}──────────────────────────────────────${NC}"

    # Останавливаем панель и страницу подписки
    (
        cd "$panel_dir"
        docker compose stop remnawave remnawave-subscription-page >/dev/null 2>&1
    ) &
    show_spinner "Остановка панели"

    # Очищаем базу данных перед восстановлением
    (
        docker exec remnawave-db psql -U postgres -d postgres -c "DROP SCHEMA public CASCADE; CREATE SCHEMA public;" >/dev/null 2>&1
    ) &
    show_spinner "Подготовка базы данных"

    # Восстанавливаем дамп
    (
        zcat "$selected_dump" | docker exec -i remnawave-db psql -U postgres -d postgres >/dev/null 2>&1
    ) &
    show_spinner "Загрузка данных из бэкапа"

    # Очищаем таблицу admin для перевода панели в режим регистрации
    (
        docker exec remnawave-db psql -U postgres -d postgres -c "TRUNCATE TABLE admin CASCADE;" >/dev/null 2>&1
    ) &
    show_spinner "Подготовка к регистрации"

    # Запускаем панель (без subscription-page, т.к. токен ещё не обновлён)
    (
        cd "$panel_dir"
        docker compose up -d remnawave >/dev/null 2>&1
    ) &
    show_spinner "Запуск панели"

    # Ожидание готовности API
    show_spinner_timer 10 "Ожидание запуска панели" "Запуск панели"

    local domain_url="127.0.0.1:3000"

    show_spinner_until_ready "http://$domain_url/api/auth/status" "Проверка доступности API" 60
    if [ $? -ne 0 ]; then
        print_error "API не отвечает после восстановления"
        echo -e "${YELLOW}Запустите панель вручную и создайте администратора${NC}"
        echo
        read -s -n 1 -p "$(echo -e "${DARKGRAY}Нажмите Enter для возврата${NC}")"
        echo
        return
    fi

    # Регистрация нового администратора и создание API токена
    local SUPERADMIN_USERNAME
    local SUPERADMIN_PASSWORD
    SUPERADMIN_USERNAME=$(generate_admin_username)
    SUPERADMIN_PASSWORD=$(generate_admin_password)

    print_action "Регистрация администратора..."
    local token
    token=$(register_remnawave "$domain_url" "$SUPERADMIN_USERNAME" "$SUPERADMIN_PASSWORD")

    if [ -n "$token" ]; then
        print_success "Регистрация администратора"

        # Создание API токена для страницы подписки
        print_action "Создание API токена для страницы подписки..."
        if create_api_token "$domain_url" "$token" "$panel_dir"; then
            # Извлекаем созданный токен из .env
            local api_token
            api_token=$(grep -oP '^REMNAWAVE_API_TOKEN=\K\S+' "$panel_dir/.env" 2>/dev/null | head -1)

            # Сброс администратора (CASCADE удалит и API токены)
            (
                docker exec remnawave-db psql -U postgres -d postgres -c "TRUNCATE TABLE admin CASCADE;" >/dev/null 2>&1
            ) &
            show_spinner "Сброс данных суперадмина"

            # Восстанавливаем API токен напрямую в базу
            if [ -n "$api_token" ]; then
                local token_uuid
                token_uuid=$(cat /proc/sys/kernel/random/uuid 2>/dev/null || uuidgen 2>/dev/null || echo "$(openssl rand -hex 16 | sed 's/\(........\)\(....\)\(....\)\(....\)\(............\)/\1-\2-\3-\4-\5/')")
                (
                    docker exec remnawave-db psql -U postgres -d postgres -c \
                        "INSERT INTO api_tokens (uuid, token, token_name, created_at, updated_at) 
                         VALUES ('$token_uuid', '$api_token', 'subscription-page', NOW(), NOW());" >/dev/null 2>&1
                ) &
                show_spinner "Восстановление API токена"
            fi

            # Перезапуск subscription-page с обновлённым токеном
            (
                cd "$panel_dir"
                docker compose up -d remnawave-subscription-page >/dev/null 2>&1
            ) &
            show_spinner "Перезапуск страницы подписки"
        else
            print_error "Не удалось создать API токен"
        fi
    else
        print_error "Не удалось зарегистрировать администратора"
        echo -e "${YELLOW}Создайте администратора вручную через панель${NC}"
    fi

    echo
    print_success "База данных успешно загружена!"
    echo
    echo -e "${BLUE}══════════════════════════════════════${NC}"
    read -s -n 1 -p "$(echo -e "${DARKGRAY}Нажмите Enter для возврата${NC}")"
    echo
}

# ═══════════════════════════════════════════════
# БАЗА ДАННЫХ: ПОЛУЧЕНИЕ СЕРТИФИКАТА ДЛЯ ДОМЕНА
# ═══════════════════════════════════════════════
obtain_cert_for_domain() {
    local new_domain="$1"
    local panel_dir="$2"
    local current_domain="$3"
    local -n __cert_result_ref=$4

    # Определяем cert domain для нового домена
    # Имя _cert_dom вместо new_cert_domain чтобы не конфликтовать с nameref
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
        # Определяем правильный cert_domain
        if [ -d "/etc/letsencrypt/live/${new_domain}" ]; then
            __cert_result_ref="$new_domain"
        else
            __cert_result_ref="$_cert_dom"
        fi
        return 0
    fi

    # Нужно получить новый сертификат
    if [ "$cert_method" = "1" ] && [ -f "/etc/letsencrypt/cloudflare.ini" ]; then
        # Cloudflare DNS-01 — не нужно останавливать сервисы
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
        # ACME HTTP-01 — нужно остановить nginx и открыть порт 80
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

        # Для ACME сертификат хранится под точным именем домена
        _cert_dom="$new_domain"
    fi

    # Проверяем, получен ли сертификат
    if [ ! -d "/etc/letsencrypt/live/${_cert_dom}" ]; then
        print_error "Не удалось получить сертификат для ${new_domain}"
        echo -e "${WHITE}Убедитесь что DNS-записи для ${YELLOW}${new_domain}${WHITE} настроены правильно.${NC}"
        echo
        # Перезапускаем nginx если он был остановлен
        (
            cd "$panel_dir"
            docker compose start remnawave-nginx >/dev/null 2>&1
        ) &
        show_spinner "Запуск nginx"
        echo
        return 1
    fi

    print_success "SSL-сертификат получен"

    # Добавляем cron для обновления если ещё нет
    local cron_rule="0 3 * * * certbot renew --quiet --deploy-hook 'cd ${panel_dir} && docker compose restart remnawave-nginx' 2>/dev/null"
    if ! crontab -l 2>/dev/null | grep -q "certbot renew"; then
        (crontab -l 2>/dev/null; echo "$cron_rule") | crontab -
    fi

    __cert_result_ref="$_cert_dom"
    return 0
}

# ═══════════════════════════════════════════════
# БАЗА ДАННЫХ: РЕДАКТИРОВАНИЕ ДОМЕНОВ
# ═══════════════════════════════════════════════
change_panel_domain() {
    clear
    echo -e "${BLUE}══════════════════════════════════════${NC}"
    echo -e "${GREEN}   🌐 СМЕНА ДОМЕНА ПАНЕЛИ${NC}"
    echo -e "${BLUE}══════════════════════════════════════${NC}"
    echo

    local panel_dir
    panel_dir=$(detect_remnawave_path)
    if [ $? -ne 0 ]; then
        echo
        read -s -n 1 -p "$(echo -e "${DARKGRAY}Нажмите Enter для возврата${NC}")"
        echo
        return 1
    fi

    # Показываем текущий домен
    local current_domain
    current_domain=$(grep -oP 'server_name\s+\K[^;]+' "${panel_dir}/nginx.conf" | head -1)
    echo -e "${WHITE}Текущий домен панели:${NC} ${YELLOW}${current_domain}${NC}"
    echo

    local new_domain
    if ! prompt_domain_with_retry "Введите новый домен панели:" new_domain; then
        return 0
    fi

    # Убираем протокол если вставили с ним
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

    # Получаем сертификат для нового домена
    local new_cert_domain=""
    if ! obtain_cert_for_domain "$new_domain" "$panel_dir" "$current_domain" new_cert_domain; then
        echo
        read -s -n 1 -p "$(echo -e "${DARKGRAY}Нажмите Enter для возврата${NC}")"
        echo
        return 1
    fi

    # Определяем старый cert_domain из nginx.conf (первое вхождение — панель)
    local old_cert_domain
    old_cert_domain=$(grep -oP 'ssl_certificate\s+"/etc/letsencrypt/live/\K[^/]+' "${panel_dir}/nginx.conf" | head -1)

    # Находим границу (второй server_name) ДО изменений
    local boundary
    boundary=$(grep -nP '^\s*server_name\s' "${panel_dir}/nginx.conf" | sed -n '2p' | cut -d: -f1)

    # Обновляем nginx.conf (синхронно, без фонового выполнения)
    # СНАЧАЛА заменяем пути к сертификатам
    if [ -n "$old_cert_domain" ] && [ "$old_cert_domain" != "$new_cert_domain" ]; then
        if [ -n "$boundary" ]; then
            sed -i "1,${boundary}s|/etc/letsencrypt/live/${old_cert_domain}/|/etc/letsencrypt/live/${new_cert_domain}/|g" "${panel_dir}/nginx.conf"
        else
            sed -i "s|/etc/letsencrypt/live/${old_cert_domain}/|/etc/letsencrypt/live/${new_cert_domain}/|g" "${panel_dir}/nginx.conf"
        fi
    fi
    # ПОТОМ заменяем server_name
    sed -i "s|server_name ${current_domain}|server_name ${new_domain}|g" "${panel_dir}/nginx.conf"
    
    (sleep 0.3) &
    show_spinner "Обновление nginx.conf"

    # Обновляем .env
    (
        if [ -f "${panel_dir}/.env" ]; then
            sed -i "s|^FRONT_END_DOMAIN=.*|FRONT_END_DOMAIN=${new_domain}|" "${panel_dir}/.env"
        fi
    ) &
    show_spinner "Обновление .env"

    # Перезапуск сервисов
    (
        cd "$panel_dir"
        docker compose down >/dev/null 2>&1
        docker compose up -d >/dev/null 2>&1
    ) &
    show_spinner "Перезапуск сервисов"

    # Регенерация cookie после смены домена
    local OLD_COOKIE_NAME OLD_COOKIE_VALUE NEW_COOKIE_NAME NEW_COOKIE_VALUE
    if get_cookie_from_nginx; then
        OLD_COOKIE_NAME="$COOKIE_NAME"
        OLD_COOKIE_VALUE="$COOKIE_VALUE"
        
        # Генерируем новые cookie
        NEW_COOKIE_NAME=$(generate_cookie_key)
        NEW_COOKIE_VALUE=$(generate_cookie_key)
        
        # Заменяем cookie в nginx.conf
        sed -i "s|~\*${OLD_COOKIE_NAME}=${OLD_COOKIE_VALUE}|~*${NEW_COOKIE_NAME}=${NEW_COOKIE_VALUE}|g" "${panel_dir}/nginx.conf"
        sed -i "s|\$arg_${OLD_COOKIE_NAME}|\$arg_${NEW_COOKIE_NAME}|g" "${panel_dir}/nginx.conf"
        sed -i "s|    \"[^\"]*\" \"${OLD_COOKIE_NAME}=${OLD_COOKIE_VALUE}; Path=|    \"${NEW_COOKIE_VALUE}\" \"${NEW_COOKIE_NAME}=${NEW_COOKIE_VALUE}; Path=|g" "${panel_dir}/nginx.conf"
        sed -i "s|\"${OLD_COOKIE_VALUE}\" 1|\"${NEW_COOKIE_VALUE}\" 1|g" "${panel_dir}/nginx.conf"
        
        # Перезапускаем nginx для применения новых cookie
        (
            cd "$panel_dir"
            docker compose restart remnawave-nginx >/dev/null 2>&1
        ) &
        show_spinner "Обновление cookie доступа"
    fi

    echo
    print_success "Домен панели изменён на ${new_domain}"

    # Показываем новую cookie-ссылку
    echo
    echo -e "${DARKGRAY}──────────────────────────────────────${NC}"
    echo -e "${GREEN}🔗 Ссылка на панель:${NC}"
    if [ -n "$NEW_COOKIE_NAME" ] && [ -n "$NEW_COOKIE_VALUE" ]; then
        echo -e "${WHITE}https://${new_domain}/auth/login?${NEW_COOKIE_NAME}=${NEW_COOKIE_VALUE}${NC}"
    else
        # Fallback на старые cookie если что-то пошло не так
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
    panel_dir=$(detect_remnawave_path)
    if [ $? -ne 0 ]; then
        echo
        read -s -n 1 -p "$(echo -e "${DARKGRAY}Нажмите Enter для возврата${NC}")"
        echo
        return 1
    fi

    # Показываем текущий домен подписки
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

    # Получаем сертификат для нового домена
    local new_cert_domain=""
    if ! obtain_cert_for_domain "$new_domain" "$panel_dir" "$current_sub_domain" new_cert_domain; then
        echo
        read -s -n 1 -p "$(echo -e "${DARKGRAY}Нажмите Enter для возврата${NC}")"
        echo
        return 1
    fi

    # Определяем старый cert_domain подписки
    local old_sub_cert_domain
    old_sub_cert_domain=$(grep -A5 "server_name.*${current_sub_domain}" "${panel_dir}/nginx.conf" 2>/dev/null | grep -oP '/etc/letsencrypt/live/\K[^/]+' | head -1)

    # Находим границы (второй и третий server_name) ДО изменений
    local start_line end_line
    start_line=$(grep -nP '^\s*server_name\s' "${panel_dir}/nginx.conf" | sed -n '2p' | cut -d: -f1)
    end_line=$(grep -nP '^\s*server_name\s' "${panel_dir}/nginx.conf" | sed -n '3p' | cut -d: -f1)

    # Обновляем nginx.conf (синхронно)
    # СНАЧАЛА заменяем пути к сертификатам
    if [ -n "$old_sub_cert_domain" ] && [ "$old_sub_cert_domain" != "$new_cert_domain" ]; then
        if [ -n "$start_line" ] && [ -n "$end_line" ]; then
            sed -i "${start_line},${end_line}s|/etc/letsencrypt/live/${old_sub_cert_domain}/|/etc/letsencrypt/live/${new_cert_domain}/|g" "${panel_dir}/nginx.conf"
        elif [ -n "$start_line" ]; then
            sed -i "${start_line},\$s|/etc/letsencrypt/live/${old_sub_cert_domain}/|/etc/letsencrypt/live/${new_cert_domain}/|g" "${panel_dir}/nginx.conf"
        fi
    fi
    # ПОТОМ заменяем server_name
    sed -i "s|server_name ${current_sub_domain}|server_name ${new_domain}|g" "${panel_dir}/nginx.conf"
    
    (sleep 0.3) &
    show_spinner "Обновление nginx.conf"

    # Обновляем .env
    (
        if [ -f "${panel_dir}/.env" ]; then
            sed -i "s|^SUB_PUBLIC_DOMAIN=.*|SUB_PUBLIC_DOMAIN=${new_domain}|" "${panel_dir}/.env"
        fi
    ) &
    show_spinner "Обновление .env"

    # Перезапуск сервисов
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
    panel_dir=$(detect_remnawave_path)
    if [ $? -ne 0 ]; then
        echo
        read -s -n 1 -p "$(echo -e "${DARKGRAY}Нажмите Enter для возврата${NC}")"
        echo
        return 1
    fi

    # Проверяем наличие ноды в nginx (третий server блок с реальным доменом)
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

    # Получаем сертификат для нового домена
    local new_cert_domain=""
    if ! obtain_cert_for_domain "$new_domain" "$panel_dir" "$current_node_domain" new_cert_domain; then
        echo
        read -s -n 1 -p "$(echo -e "${DARKGRAY}Нажмите Enter для возврата${NC}")"
        echo
        return 1
    fi

    # Определяем старый cert_domain ноды
    local old_node_cert_domain
    old_node_cert_domain=$(grep -A5 "server_name.*${current_node_domain}" "${panel_dir}/nginx.conf" 2>/dev/null | grep -oP '/etc/letsencrypt/live/\K[^/]+' | head -1)

    # Находим границу (третий server_name без '_') ДО изменений
    local start_line
    start_line=$(grep -n "server_name" "${panel_dir}/nginx.conf" | grep -v '_' | sed -n '3p' | cut -d: -f1)

    # Обновляем nginx.conf (синхронно)
    # СНАЧАЛА заменяем пути к сертификатам
    if [ -n "$old_node_cert_domain" ] && [ "$old_node_cert_domain" != "$new_cert_domain" ]; then
        if [ -n "$start_line" ]; then
            sed -i "${start_line},\$s|/etc/letsencrypt/live/${old_node_cert_domain}/|/etc/letsencrypt/live/${new_cert_domain}/|g" "${panel_dir}/nginx.conf"
        fi
    fi
    # ПОТОМ заменяем server_name
    sed -i "s|server_name ${current_node_domain}|server_name ${new_domain}|g" "${panel_dir}/nginx.conf"
    
    (sleep 0.3) &
    show_spinner "Обновление nginx.conf"

    # Обновляем docker-compose.yml если используется
    (
        if [ -f "${panel_dir}/docker-compose.yml" ] && grep -q "${current_node_domain}" "${panel_dir}/docker-compose.yml" 2>/dev/null; then
            sed -i "s|${current_node_domain}|${new_domain}|g" "${panel_dir}/docker-compose.yml"
        fi
    ) &
    show_spinner "Обновление docker-compose.yml"

    # Перезапуск сервисов
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
    panel_dir=$(detect_remnawave_path)
    if [ $? -ne 0 ]; then
        echo
        read -s -n 1 -p "$(echo -e "${DARKGRAY}Нажмите Enter для возврата${NC}")"
        echo
        return 1
    fi

    # Показываем текущие домены
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
        3) continue ;;
        4) return ;;
    esac
}

# ═══════════════════════════════════════════════
# БАЗА ДАННЫХ: ГЛАВНОЕ МЕНЮ
# ═══════════════════════════════════════════════
manage_database() {
    clear
    echo -e "${BLUE}══════════════════════════════════════${NC}"
    echo -e "${GREEN}   💾  БАЗА ДАННЫХ${NC}"
    echo -e "${BLUE}══════════════════════════════════════${NC}"
    echo

    show_arrow_menu "БАЗА ДАННЫХ" \
        "💾  Сохранить базу данных" \
        "📥  Загрузить базу данных" \
        "──────────────────────────────────────" \
        "❌  Назад"
    local choice=$?

    case $choice in
        0) db_backup ;;
        1) db_restore ;;
        2) continue ;;
        3) return ;;
    esac
}

# ═══════════════════════════════════════════════
# УПРАВЛЕНИЕ: ШАБЛОН САЙТА-ЗАГЛУШКИ
# ═══════════════════════════════════════════════
manage_start() {
    (
        cd /opt/remnawave
        docker compose up -d >/dev/null 2>&1
    ) &
    show_spinner "Запуск сервисов"
    print_success "Сервисы запущены"
    echo
    read -s -n 1 -p "$(echo -e "${DARKGRAY}Нажмите Enter для продолжения${NC}")"
        echo
}

manage_stop() {
    (
        cd /opt/remnawave
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

    (
        cd /opt/remnawave
        docker compose pull >/dev/null 2>&1
    ) &
    show_spinner "Скачивание обновлений"

    (
        cd /opt/remnawave
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
    clear
    echo -e "${YELLOW}Для выхода из логов нажмите Ctrl+C${NC}"
    sleep 1
    cd /opt/remnawave
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

    (
        cd /opt/remnawave
        docker compose down -v --rmi all >/dev/null 2>&1
        docker system prune -af >/dev/null 2>&1
    ) &
    show_spinner "Удаление контейнеров и данных"

    (
        rm -f /opt/remnawave/.env
        rm -f /opt/remnawave/docker-compose.yml
        rm -f /opt/remnawave/nginx.conf
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
        1) continue ;;
        2) installation_panel ;;
        3) installation_node ;;
        4) add_node_to_panel ;;
        5) continue ;;
        6) return ;;
    esac
}

# ═══════════════════════════════════════════════════
# УПРАВЛЕНИЕ ДОСТУПОМ К ПАНЕЛИ
# ═══════════════════════════════════════════════════

manage_panel_access() {
    clear
    echo -e "${BLUE}══════════════════════════════════════${NC}"
    echo -e "${GREEN}   🔓 ДОСТУП К ПАНЕЛИ${NC}"
    echo -e "${BLUE}══════════════════════════════════════${NC}"
    echo

    # Показываем текущий статус доступа по 8443
    if grep -q "# ─── 8443 Fallback" /opt/remnawave/nginx.conf 2>/dev/null; then
        echo -e "${WHITE}Доступ по 8443:${NC} ${GREEN}открыт${NC}"
    else
        echo -e "${WHITE}Доступ по 8443:${NC} ${RED}закрыт${NC}"
    fi

    # Показываем cookie-ссылку
    local COOKIE_NAME COOKIE_VALUE
    if get_cookie_from_nginx; then
        local panel_domain
        panel_domain=$(grep -oP 'server_name\s+\K[^;]+' /opt/remnawave/nginx.conf | head -1)
        echo
        echo -e "${WHITE}🔗 Cookie-ссылка на панель:${NC}"
        echo -e "${DARKGRAY}https://${panel_domain}/?${COOKIE_NAME}=${COOKIE_VALUE}${NC}"
    fi
    echo

    show_arrow_menu "ДОСТУП К ПАНЕЛИ" \
        "🔓  Открыть доступ по 8443" \
        "🔒  Закрыть доступ по 8443" \
        "🔗  Показать cookie-ссылку" \
        "──────────────────────────────────────" \
        "🔐  Сбросить суперадмина" \
        "🍪  Сменить cookie доступа" \
        "🌐  Редактировать домены" \
        "──────────────────────────────────────" \
        "❌  Назад"
    local choice=$?

    case $choice in
        0) open_panel_access ;;
        1) close_panel_access ;;
        2)
            clear
            local COOKIE_NAME COOKIE_VALUE
            if get_cookie_from_nginx; then
                local pd
                pd=$(grep -oP 'server_name\s+\K[^;]+' /opt/remnawave/nginx.conf | head -1)
                echo
                echo -e "${GREEN}🔗 Cookie-ссылка на панель (основной порт):${NC}"
                echo -e "${WHITE}https://${pd}/?${COOKIE_NAME}=${COOKIE_VALUE}${NC}"
                echo
                if grep -q "# ─── 8443 Fallback" /opt/remnawave/nginx.conf 2>/dev/null; then
                    echo -e "${GREEN}🔗 Cookie-ссылка на панель (доступ по 8443):${NC}"
                    echo -e "${WHITE}https://${pd}:8443/?${COOKIE_NAME}=${COOKIE_VALUE}${NC}"
                    echo
                fi
            else
                echo
                print_error "Не удалось извлечь cookie из nginx.conf"
                echo
            fi
            echo
            read -e -p "$(echo -e "${DARKGRAY}Нажмите Enter для продолжения...${NC}")" _
            ;;
        3) ;;
        4) change_credentials ;;
        5) regenerate_cookies ;;
        6) manage_domains ;;
        7) ;;
        8) return ;;
    esac
}

# ═══════════════════════════════════════════════════
# УДАЛЕНИЕ НОДЫ С СЕРВЕРА ПАНЕЛИ
# ═══════════════════════════════════════════════════
remove_node_from_panel() {
    # Гарантируем, что мы в корне или в /opt/remnawave
    cd /opt/remnawave 2>/dev/null || cd / 2>/dev/null
    
    clear
    echo -e "${BLUE}══════════════════════════════════════${NC}"
    echo -e "${RED}   🗑️  УДАЛЕНИЕ НОДЫ С СЕРВЕРА ПАНЕЛИ${NC}"
    echo -e "${BLUE}══════════════════════════════════════${NC}"
    echo

    # Проверяем, есть ли нода на сервере
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

    # Получаем текущие домены из nginx.conf
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
    
    # Создаём бэкап для восстановления API токена
    cp /opt/remnawave/docker-compose.yml /opt/remnawave/docker-compose.yml.bak 2>/dev/null || true
    cp /opt/remnawave/.env /opt/remnawave/.env.bak 2>/dev/null || true
    
    # Генерируем новый docker-compose без remnanode
    generate_docker_compose_panel "$panel_cert" "$sub_cert"
    
    # Восстанавливаем API токен из бэкапа
    local existing_api_token
    existing_api_token=$(grep -oP '^REMNAWAVE_API_TOKEN=\K\S+' /opt/remnawave/.env.bak 2>/dev/null | head -1)
    if [ -n "$existing_api_token" ]; then
        sed -i "s|^REMNAWAVE_API_TOKEN=.*|REMNAWAVE_API_TOKEN=$existing_api_token|" /opt/remnawave/.env
    fi
    
    # Удаляем бэкап
    rm -f /opt/remnawave/docker-compose.yml.bak /opt/remnawave/.env.bak 2>/dev/null || true

    print_action "Настройка nginx для порта 443..."
    
    # Генерируем nginx.conf для работы на порту 443 (без unix socket)
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

    # Проверяем доступность
    if curl -s -f http://127.0.0.1:3000/api/auth_status >/dev/null 2>&1; then
        print_success "Панель запущена и работает"
    fi

    # Итог
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

# ═══════════════════════════════════════════════════
# АВТОМАТИЧЕСКОЕ ВКЛЮЧЕНИЕ ДОСТУПА ПО 8443
# ═════════════════════════════════════════════════==
auto_enable_panel_access_8443() {
    local panel_domain="${1:-}"
    local cookie_name="${2:-}"
    local cookie_value="${3:-}"
    local dir="/opt/remnawave"

    # Проверяем, что nginx.conf существует
    [ ! -f "$dir/nginx.conf" ] && return 1

    # Если домен не передан, получаем из конфига
    if [ -z "$panel_domain" ]; then
        panel_domain=$(grep -oP 'server_name\s+\K[^;]+' "$dir/nginx.conf" | head -1)
    fi

    # Определяем сертификат панели
    local panel_cert
    panel_cert=$(grep -A 5 "server_name ${panel_domain};" "$dir/nginx.conf" | grep -oP 'ssl_certificate\s+"/etc/nginx/ssl/\K[^/]+' | head -1)

    # Проверяем, уже настроен ли 8443
    if grep -q "# ─── 8443 Fallback" "$dir/nginx.conf" 2>/dev/null; then
        # Уже настроен - просто открываем в UFW
        ufw allow 8443/tcp >/dev/null 2>&1
        return 0
    fi

    # Проверяем, не занят ли порт 8443
    if command -v ss >/dev/null 2>&1; then
        ss -tuln | grep -q ":8443" && return 1
    elif command -v netstat >/dev/null 2>&1; then
        netstat -tuln | grep -q ":8443" && return 1
    fi

    # Находим номер строки с закрывающей скобкой последнего server блока
    local insert_after_line
    insert_after_line=$(awk '/^server \{/ {start=NR; brace=1} 
        brace {if (/\{/) brace++; if (/\}/) brace--} 
        brace==0 && start {print NR; exit}' "$dir/nginx.conf")
    
    if [ -z "$insert_after_line" ]; then
        insert_after_line=$(grep -n "^}$" "$dir/nginx.conf" | tail -1 | cut -d: -f1)
    fi

    # Создаем временный файл с блоком
    local temp_file="/tmp/remnawave_8443_auto_$$.conf"
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
        sed -i "${insert_after_line}r ${temp_file}" "$dir/nginx.conf"
    else
        cat "$temp_file" >> "$dir/nginx.conf"
    fi

    rm -f "$temp_file"

    # Перезапускаем nginx
    (
        cd "$dir"
        docker compose restart remnawave-nginx >/dev/null 2>&1
    ) &

    # Открываем порт в UFW
    ufw allow 8443/tcp >/dev/null 2>&1

    return 0
}
