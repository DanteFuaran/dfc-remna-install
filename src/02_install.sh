# ═══════════════════════════════════════════════
# ГЕНЕРАТОРЫ
# ═══════════════════════════════════════════════
generate_password() {
    openssl rand -base64 48 | tr -dc 'a-zA-Z0-9!@#$%' | head -c 24
}

generate_username() {
    openssl rand -base64 12 | tr -dc 'a-zA-Z' | head -c 8
}

generate_secret() {
    openssl rand -base64 48 | tr -dc 'a-zA-Z0-9' | head -c 64
}

generate_webhook_secret() {
    openssl rand -hex 32
}

generate_admin_password() {
    # Генерация пароля минимум 24 символа с заглавными, строчными буквами и цифрами
    local upper=$(tr -dc 'A-Z' < /dev/urandom | head -c 8)
    local lower=$(tr -dc 'a-z' < /dev/urandom | head -c 8)
    local digits=$(tr -dc '0-9' < /dev/urandom | head -c 8)
    # Перемешиваем и добавляем ещё символов для длины
    echo "${upper}${lower}${digits}" | fold -w1 | shuf | tr -d '\n' && tr -dc 'a-zA-Z0-9' < /dev/urandom | head -c 8
}

generate_admin_username() {
    # Генерация логина из случайного слова + цифр
    echo "admin$(openssl rand -hex 4)"
}

generate_cookie_key() {
    # Генерация случайного ключа для cookie-защиты панели (8 символов, буквы + цифры)
    local key
    key=$(openssl rand -base64 24 | tr -dc 'a-zA-Z0-9' | head -c 8)
    echo "$key"
}

get_cookie_from_nginx() {
    # Извлекаем COOKIE_NAME и COOKIE_VALUE из nginx.conf
    local nginx_conf="/opt/remnawave/nginx.conf"
    if [ ! -f "$nginx_conf" ]; then
        return 1
    fi
    COOKIE_NAME=$(grep -oP '~\*\K[^=]+(?==[^"]+"\s+1)' "$nginx_conf" | head -1)
    COOKIE_VALUE=$(grep -oP '~\*[^=]+=\K[^"]+(?="\s+1)' "$nginx_conf" | head -1)
    if [ -z "$COOKIE_NAME" ] || [ -z "$COOKIE_VALUE" ]; then
        return 1
    fi
    return 0
}

# ═══════════════════════════════════════════════
# НАСТРОЙКА РОТАЦИИ ЛОГОВ
# ═══════════════════════════════════════════════
setup_log_rotation() {
    local panel_dir="${1:-/opt/remnawave}"
    local logs_dir="${panel_dir}/logs"
    local log_file="${logs_dir}/remnawave.log"
    local service_name="remnawave-logger"
    
    mkdir -p "$logs_dir"
    
    # Создаём systemd сервис для непрерывной записи логов
    cat > "/etc/systemd/system/${service_name}.service" << EOF
[Unit]
Description=Remnawave Docker Logs Collector
After=docker.service
Requires=docker.service

[Service]
Type=simple
ExecStart=/bin/bash -c 'cd ${panel_dir} && docker compose logs -f --no-log-prefix -t >> ${log_file} 2>&1'
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

    # Создаём logrotate конфигурацию (ежедневная ротация, хранение 14 дней)
    cat > "/etc/logrotate.d/remnawave" << EOF
${log_file} {
    daily
    rotate 14
    compress
    delaycompress
    missingok
    notifempty
    copytruncate
}
EOF

    # Запускаем сервис
    systemctl daemon-reload
    systemctl enable "$service_name" >/dev/null 2>&1
    systemctl restart "$service_name" >/dev/null 2>&1

    # Удаляем старый cron-скрипт если есть
    rm -f /etc/cron.daily/remnawave-logs
}

# ═══════════════════════════════════════════════
# РАБОТА С ДОМЕНАМИ
# ═══════════════════════════════════════════════
extract_domain() {
    local full_domain="$1"
    local parts
    parts=$(echo "$full_domain" | tr '.' '\n' | wc -l)
    if [ "$parts" -gt 2 ]; then
        echo "$full_domain" | cut -d'.' -f2-
    else
        echo "$full_domain"
    fi
}

get_server_ip() {
    local ip=""
    
    # Пробуем несколько сервисов для получения IP адреса
    ip=$(curl -s4 --max-time 5 ifconfig.me 2>/dev/null)
    if [ -n "$ip" ] && [[ "$ip" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; then
        echo "$ip"
        return 0
    fi
    
    ip=$(curl -s4 --max-time 5 icanhazip.com 2>/dev/null)
    if [ -n "$ip" ] && [[ "$ip" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; then
        echo "$ip"
        return 0
    fi
    
    ip=$(curl -s4 --max-time 5 ident.me 2>/dev/null)
    if [ -n "$ip" ] && [[ "$ip" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; then
        echo "$ip"
        return 0
    fi
    
    # Фоллбек на локальный IP если нет доступа в интернет
    ip=$(hostname -I 2>/dev/null | awk '{print $1}')
    if [ -n "$ip" ] && [[ "$ip" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; then
        echo "$ip"
        return 0
    fi
    
    echo "unknown"
}

check_domain() {
    local domain="$1"
    local check_ip="${2:-true}"
    
    # Получаем IP домена
    local domain_ip
    domain_ip=$(dig +short "$domain" A 2>/dev/null | head -1)

    # Получаем IP сервера для сообщений об ошибках
    local server_ip
    server_ip=$(get_server_ip)

    if [ -z "$domain_ip" ]; then
        echo
        echo -e "${RED}✖ Домен ${YELLOW}$domain${RED} не соответствует IP вашего сервера ${YELLOW}$server_ip${NC}"
        echo -e "${RED}❗Убедитесь что DNS записи настроены правильно.${NC}"
        return 1
    fi

    if [ "$check_ip" = false ]; then
        return 0
    fi

    # ═══════════════════════════════════════════════════════════
    # УЛУЧШЕННАЯ ПРОВЕРКА IP С ПОДДЕРЖКОЙ NAT/DOCKER/ПРОКСИ
    # ═══════════════════════════════════════════════════════════
    
    local ip_match=false
    
    # 1. Проверяем прямое совпадение с внешним IP
    if [ "$domain_ip" = "$server_ip" ]; then
        ip_match=true
    else
        # 2. Проверяем локальные IP интерфейсов (для Docker/NAT)
        local local_ips
        local_ips=$(ip -4 addr show 2>/dev/null | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | grep -v '127.0.0.1')
        
        if [ -n "$local_ips" ]; then
            while IFS= read -r local_ip; do
                if [ "$domain_ip" = "$local_ip" ]; then
                    ip_match=true
                    break
                fi
            done <<< "$local_ips"
        fi
    fi
    
    # 3. HTTP fallback проверка (если IP не совпал)
    if [ "$ip_match" = false ]; then
        # Создаём временный токен для проверки
        local test_token
        test_token=$(openssl rand -hex 16)
        mkdir -p /var/www/html
        echo "$test_token" > "/var/www/html/.test_${test_token}.txt" 2>/dev/null
        
        # Пытаемся получить файл через домен
        local test_response
        test_response=$(curl -s -m 5 "http://${domain}/.test_${test_token}.txt" 2>/dev/null || echo "")
        
        # Удаляем тестовый файл
        rm -f "/var/www/html/.test_${test_token}.txt" 2>/dev/null
        
        # Если получили правильный ответ - домен указывает на этот сервер
        if [ "$test_response" = "$test_token" ]; then
            ip_match=true
        fi
    fi
    
    # ═══════════════════════════════════════════════════════════
    # ФИНАЛЬНАЯ ПРОВЕРКА
    # ═══════════════════════════════════════════════════════════
    
    if [ "$ip_match" = false ]; then
        echo
        echo -e "${RED}✖ Домен ${YELLOW}$domain${RED} не соответствует IP вашего сервера ${YELLOW}$server_ip${NC}"
        echo -e "${RED}⚠️ Убедитесь что DNS записи настроены правильно.${NC}"
        echo
        return 1
    fi
    
    return 0
}

prompt_domain_with_retry() {
    local prompt_text="$1"
    local var_name="$2"
    local use_inline="${3:-false}"
    local skip_ip_check="${4:-false}"

    local first=true
    while true; do
        if [ "$first" = true ]; then
            if [ "$use_inline" = true ]; then
                reading_inline "$prompt_text" "$var_name"
            else
                reading "$prompt_text" "$var_name"
            fi
            first=false
        else
            reading_inline "$prompt_text" "$var_name"
        fi

        local check_ip_flag=true
        [ "$skip_ip_check" = true ] && check_ip_flag=false
        if check_domain "${!var_name}" "$check_ip_flag"; then
            return 0
        fi

        echo
        echo -e "${DARKGRAY}Нажмите Enter что бы ввести другой домен, или нажмите Esc для возвращения в главное меню.${NC}"

        local key
        while true; do
            read -s -n 1 key
            if [[ "$key" == $'\x1b' ]]; then
                echo
                return 1
            elif [[ "$key" == "" ]]; then
                # Очищаем всё после ввода домена и показываем промпт заново
                # Поднимаемся на нужное кол-во строк и очищаем
                # Строки: строка ввода + пустая + ошибка(2) + пустая + пустая + подсказка = 7 строк
                # Но удаляем только 6, чтобы оставить пустую строку после заголовка
                local lines_up=6
                for ((l=0; l<lines_up; l++)); do
                    tput cuu1 2>/dev/null
                    tput el 2>/dev/null
                done
                break
            fi
        done
    done
}

check_node_domain() {
    local domain_url="$1"
    local token="$2"
    local domain="$3"

    local response
    response=$(make_api_request "GET" "$domain_url/api/nodes" "$token")

    if [ -z "$response" ]; then
        print_error "Ошибка при проверке домена"
        return 1
    fi

    if echo "$response" | jq -e '.response' >/dev/null 2>&1; then
        local existing_domain
        existing_domain=$(echo "$response" | jq -r --arg addr "$domain" \
            '.response[] | select(.address == $addr) | .address' 2>/dev/null)
        if [ -n "$existing_domain" ]; then
            print_error "Домен уже используется: $domain"
            return 1
        fi
        return 0
    else
        local error_message
        error_message=$(echo "$response" | jq -r '.message // "Unknown error"')
        print_error "Ошибка при проверке домена: $error_message"
        return 1
    fi
}

# ═══════════════════════════════════════════════
# СЕРТИФИКАТЫ
# ═══════════════════════════════════════════════
handle_certificates() {
    local -n domains_ref=$1
    local cert_method="$2"
    local email="$3"

    for domain in "${!domains_ref[@]}"; do
        local base_domain
        base_domain=$(extract_domain "$domain")

        # Проверяем наличие сертификата
        if [ -d "/etc/letsencrypt/live/$domain" ] || [ -d "/etc/letsencrypt/live/$base_domain" ]; then
            print_success "Сертификат для $domain уже существует"
            continue
        fi

        case "$cert_method" in
            1)
                # Cloudflare DNS-01 (wildcard)
                get_cert_cloudflare "$base_domain" "$email"
                ;;
            2)
                # ACME HTTP-01
                get_cert_acme "$domain" "$email"
                ;;
            *)
                print_error "Неизвестный метод сертификации"
                return 1
                ;;
        esac
    done

    echo
}

detect_cert_method() {
    local domain="$1"
    local base_domain
    base_domain=$(extract_domain "$domain")

    if [ -d "/etc/letsencrypt/live/$base_domain" ]; then
        echo "1"
    elif [ -d "/etc/letsencrypt/live/$domain" ]; then
        echo "2"
    else
        echo "2"
    fi
}

check_if_certificates_needed() {
    local -n domains_ref=$1

    for domain in "${!domains_ref[@]}"; do
        local base_domain
        base_domain=$(extract_domain "$domain")

        if [ ! -d "/etc/letsencrypt/live/$domain" ] && [ ! -d "/etc/letsencrypt/live/$base_domain" ]; then
            return 0
        fi
    done

    return 1
}

get_cert_cloudflare() {
    local domain="$1"
    local email="$2"

    if [ ! -f "/etc/letsencrypt/cloudflare.ini" ]; then
        print_error "Файл /etc/letsencrypt/cloudflare.ini не найден"
        return 1
    fi

    (
        certbot certonly --dns-cloudflare \
            --dns-cloudflare-credentials /etc/letsencrypt/cloudflare.ini \
            --dns-cloudflare-propagation-seconds 30 \
            -d "$domain" -d "*.$domain" \
            --email "$email" --agree-tos --non-interactive \
            --key-type ecdsa >/dev/null 2>&1
    ) &
    show_spinner "Получение wildcard сертификата для *.$domain"

    # Добавляем cron для обновления
    local cron_rule="0 3 * * * certbot renew --quiet --deploy-hook 'cd ${DIR_PANEL} && docker compose restart remnawave-nginx' 2>/dev/null"
    if ! crontab -l 2>/dev/null | grep -q "certbot renew"; then
        (crontab -l 2>/dev/null; echo "$cron_rule") | crontab -
    fi
}

get_cert_acme() {
    local domain="$1"
    local email="$2"

    (
        ufw allow 80/tcp >/dev/null 2>&1
        certbot certonly --standalone \
            -d "$domain" \
            --email "$email" --agree-tos --non-interactive \
            --http-01-port 80 \
            --key-type ecdsa >/dev/null 2>&1
        ufw delete allow 80/tcp >/dev/null 2>&1
        ufw reload >/dev/null 2>&1
    ) &
    show_spinner "Получение сертификата для $domain"

    local cron_rule="0 3 * * * certbot renew --quiet --deploy-hook 'cd ${DIR_PANEL} && docker compose restart remnawave-nginx' 2>/dev/null"
    if ! crontab -l 2>/dev/null | grep -q "certbot renew"; then
        (crontab -l 2>/dev/null; echo "$cron_rule") | crontab -
    fi
}

setup_cloudflare_credentials() {
    reading "Введите Cloudflare API Token:" CF_TOKEN

    # Проверяем токен
    local check
    check=$(curl -s -X GET "https://api.cloudflare.com/client/v4/user/tokens/verify" \
        -H "Authorization: Bearer $CF_TOKEN" | jq -r '.success' 2>/dev/null)

    if [ "$check" != "true" ]; then
        print_error "Cloudflare API Token невалиден"
        return 1
    fi
    print_success "Cloudflare API Token подтверждён"

    mkdir -p /etc/letsencrypt
    cat > /etc/letsencrypt/cloudflare.ini <<EOF
dns_cloudflare_api_token = $CF_TOKEN
EOF
    chmod 600 /etc/letsencrypt/cloudflare.ini
}

# ═══════════════════════════════════════════════
# API ФУНКЦИИ (Remnawave Panel)
# ═══════════════════════════════════════════════
make_api_request() {
    local method=$1
    local url=$2
    local token=$3
    local data=$4

    local headers=(
        -H "Authorization: Bearer $token"
        -H "Content-Type: application/json"
        -H "X-Forwarded-For: 127.0.0.1"
        -H "X-Forwarded-Proto: https"
        -H "X-Remnawave-Client-Type: browser"
    )

    if [ -n "$data" ]; then
        curl -s -X "$method" "http://$url" "${headers[@]}" -d "$data"
    else
        curl -s -X "$method" "http://$url" "${headers[@]}"
    fi
}

get_panel_token() {
    local TOKEN_FILE="${DIR_REMNAWAVE}/token"
    local domain_url="127.0.0.1:3000"
    local token=""

    # Проверяем сохранённый токен
    if [ -f "$TOKEN_FILE" ]; then
        token=$(cat "$TOKEN_FILE")
        local test_response
        test_response=$(make_api_request "GET" "$domain_url/api/config-profiles" "$token")

        if [ -z "$test_response" ] || ! echo "$test_response" | jq -e '.response.configProfiles' >/dev/null 2>&1; then
            echo -e "${RED}Сохранённый токен недействителен. Запрашиваем новый...${NC}"
            token=""
        fi
    fi

    if [ -z "$token" ]; then
        # Проверяем наличие OAuth
        local auth_status
        auth_status=$(make_api_request "GET" "$domain_url/api/auth/status" "")
        local oauth_enabled=false

        if [ -n "$auth_status" ]; then
            local github_enabled yandex_enabled pocketid_enabled telegram_enabled
            github_enabled=$(echo "$auth_status" | jq -r '.response.authentication.oauth2.providers.github // false' 2>/dev/null)
            yandex_enabled=$(echo "$auth_status" | jq -r '.response.authentication.oauth2.providers.yandex // false' 2>/dev/null)
            pocketid_enabled=$(echo "$auth_status" | jq -r '.response.authentication.oauth2.providers.pocketid // false' 2>/dev/null)
            telegram_enabled=$(echo "$auth_status" | jq -r '.response.authentication.tgAuth.enabled // false' 2>/dev/null)

            if [ "$github_enabled" = "true" ] || [ "$yandex_enabled" = "true" ] || \
               [ "$pocketid_enabled" = "true" ] || [ "$telegram_enabled" = "true" ]; then
                oauth_enabled=true
            fi
        fi

        if [ "$oauth_enabled" = true ]; then
            echo -e "${YELLOW}═════════════════════════════════════════════════${NC}"
            echo -e "${RED}ВНИМАНИЕ:${NC}"
            echo -e "${YELLOW}Включена авторизация через OAuth/Telegram.${NC}"
            echo -e "${YELLOW}Зайдите в панель, перейдите в 'API токены' -> 'Создать новый токен'${NC}"
            echo -e "${YELLOW}Скопируйте созданный токен и введите его ниже.${NC}"

            local first_api=true
            while true; do
                if [ "$first_api" = true ]; then
                    reading "Введите API-токен: " token
                    first_api=false
                else
                    reading_inline "Введите API-токен: " token
                fi

                if [ -z "$token" ]; then
                    print_error "Токен не введён"
                    echo
                    echo -e "${DARKGRAY}Нажмите Enter чтобы ввести токен заново, или Esc для отмены.${NC}"
                    local key
                    while true; do
                        read -s -n 1 key
                        if [[ "$key" == $'\x1b' ]]; then
                            echo
                            return 1
                        elif [[ "$key" == "" ]]; then
                            local lines_up=4
                            for ((l=0; l<lines_up; l++)); do
                                tput cuu1 2>/dev/null
                                tput el 2>/dev/null
                            done
                            break
                        fi
                    done
                    continue
                fi

                local test_response
                test_response=$(make_api_request "GET" "$domain_url/api/config-profiles" "$token")
                if [ -z "$test_response" ] || ! echo "$test_response" | jq -e '.response.configProfiles' >/dev/null 2>&1; then
                    print_error "Токен недействителен"
                    echo
                    echo -e "${DARKGRAY}Нажмите Enter чтобы ввести токен заново, или Esc для отмены.${NC}"
                    local key
                    while true; do
                        read -s -n 1 key
                        if [[ "$key" == $'\x1b' ]]; then
                            echo
                            return 1
                        elif [[ "$key" == "" ]]; then
                            local lines_up=4
                            for ((l=0; l<lines_up; l++)); do
                                tput cuu1 2>/dev/null
                                tput el 2>/dev/null
                            done
                            break
                        fi
                    done
                    continue
                fi

                break
            done
        else
            local first_login=true
            while true; do
                if [ "$first_login" = true ]; then
                    reading "Введите логин панели: " username
                    first_login=false
                else
                    reading_inline "Введите логин панели: " username
                fi
                reading_inline "Введите пароль панели: " password

                local login_response
                login_response=$(make_api_request "POST" "$domain_url/api/auth/login" "" \
                    "{\"username\":\"$username\",\"password\":\"$password\"}")
                token=$(echo "$login_response" | jq -r '.response.accessToken // empty')

                if [ -n "$token" ] && [ "$token" != "null" ]; then
                    break
                fi

                print_error "Неверный логин или пароль"
                echo
                echo -e "${DARKGRAY}Нажмите Enter чтобы ввести данные заново, или Esc для отмены.${NC}"
                local key
                while true; do
                    read -s -n 1 key
                    if [[ "$key" == $'\x1b' ]]; then
                        echo
                        return 1
                    elif [[ "$key" == "" ]]; then
                        local lines_up=5
                        for ((l=0; l<lines_up; l++)); do
                            tput cuu1 2>/dev/null
                            tput el 2>/dev/null
                        done
                        break
                    fi
                done
            done
        fi

        echo "$token" > "$TOKEN_FILE"
    fi

    # Финальная проверка
    local final_test
    final_test=$(make_api_request "GET" "$domain_url/api/config-profiles" "$token")
    if [ -z "$final_test" ] || ! echo "$final_test" | jq -e '.response.configProfiles' >/dev/null 2>&1; then
        print_error "Токен не прошёл проверку"
        return 1
    fi

    return 0
}

register_remnawave() {
    local domain_url=$1
    local username=$2
    local password=$3
    local max_attempts=5
    local attempt=1

    local register_data='{"username":"'"$username"'","password":"'"$password"'"}'
    local token=""

    while [ $attempt -le $max_attempts ] && [ -z "$token" ]; do
        local response
        response=$(curl -s -X POST "http://$domain_url/api/auth/register" \
            -H "Content-Type: application/json" \
            -H "X-Forwarded-For: 127.0.0.1" \
            -H "X-Forwarded-Proto: https" \
            -d "$register_data" 2>/dev/null)

        token=$(echo "$response" | jq -r '.response.accessToken // empty' 2>/dev/null)

        if [ -z "$token" ]; then
            # Попытка логина если уже зарегистрирован
            local login_data='{"username":"'"$username"'","password":"'"$password"'"}'
            response=$(curl -s -X POST "http://$domain_url/api/auth/login" \
                -H "Content-Type: application/json" \
                -H "X-Forwarded-For: 127.0.0.1" \
                -H "X-Forwarded-Proto: https" \
                -d "$login_data" 2>/dev/null)
            token=$(echo "$response" | jq -r '.response.accessToken // empty' 2>/dev/null)
        fi

        if [ -z "$token" ]; then
            sleep 3
            ((attempt++))
        fi
    done

    echo "$token"
}

get_public_key() {
    local domain_url=$1
    local token=$2
    local target_dir=$3

    local response
    response=$(make_api_request "GET" "$domain_url/api/keygen" "$token")
    local pubkey
    pubkey=$(echo "$response" | jq -r '.response.pubKey // empty' 2>/dev/null)

    if [ -z "$pubkey" ]; then
        print_error "Не удалось получить публичный ключ из API"
        return 1
    fi

    sed -i "s|SECRET_KEY=.*|SECRET_KEY=\"$pubkey\"|" "$target_dir/docker-compose.yml" 2>/dev/null
    return 0
}

generate_xray_keys() {
    local domain_url=$1
    local token=$2

    local response
    response=$(make_api_request "GET" "$domain_url/api/system/tools/x25519/generate" "$token")
    local private_key
    private_key=$(echo "$response" | jq -r '.response.keypairs[0].privateKey // empty' 2>/dev/null)

    if [ -z "$private_key" ] || [ "$private_key" = "null" ]; then
        # Fallback - возможно другая версия API
        private_key=$(echo "$response" | jq -r '.response.privateKey // empty' 2>/dev/null)
    fi

    echo "$private_key"
}

create_config_profile() {
    local domain_url=$1
    local token=$2
    local name=$3
    local domain=$4
    local private_key=$5
    local inbound_tag="${6:-Steal}"

    local short_id
    short_id=$(openssl rand -hex 8)

    local request_body
    request_body=$(jq -n --arg name "$name" --arg domain "$domain" \
        --arg private_key "$private_key" --arg short_id "$short_id" \
        --arg inbound_tag "$inbound_tag" '{
        name: $name,
        config: {
            log: { loglevel: "warning" },
            dns: {
                queryStrategy: "UseIPv4",
                servers: [{ address: "https://dns.google/dns-query", skipFallback: false }]
            },
            inbounds: [{
                tag: $inbound_tag,
                port: 443,
                protocol: "vless",
                settings: { clients: [], decryption: "none" },
                sniffing: { enabled: true, destOverride: ["http", "tls", "quic"] },
                streamSettings: {
                    network: "tcp",
                    security: "reality",
                    realitySettings: {
                        show: false,
                        xver: 1,
                        dest: "/dev/shm/nginx.sock",
                        spiderX: "",
                        shortIds: [$short_id],
                        privateKey: $private_key,
                        serverNames: [$domain]
                    }
                }
            }],
            outbounds: [
                { tag: "DIRECT", protocol: "freedom" },
                { tag: "BLOCK", protocol: "blackhole" }
            ],
            routing: {
                rules: [
                    { ip: ["geoip:private"], type: "field", outboundTag: "BLOCK" },
                    { type: "field", protocol: ["bittorrent"], outboundTag: "BLOCK" }
                ]
            }
        }
    }')

    local response
    response=$(make_api_request "POST" "$domain_url/api/config-profiles" "$token" "$request_body")

    local config_uuid
    config_uuid=$(echo "$response" | jq -r '.response.uuid // empty' 2>/dev/null)
    local inbound_uuid
    inbound_uuid=$(echo "$response" | jq -r '.response.inbounds[0].uuid // empty' 2>/dev/null)

    if [ -z "$config_uuid" ] || [ "$config_uuid" = "null" ] || \
       [ -z "$inbound_uuid" ] || [ "$inbound_uuid" = "null" ]; then
        echo "ERROR" >&2
        return 1
    fi

    echo "$config_uuid $inbound_uuid"
}

delete_config_profile() {
    local domain_url=$1
    local token=$2

    local response
    response=$(make_api_request "GET" "$domain_url/api/config-profiles" "$token")

    local config_uuids
    config_uuids=$(echo "$response" | jq -r '.response.configProfiles[].uuid // empty' 2>/dev/null)

    if [ -n "$config_uuids" ]; then
        while IFS= read -r uuid; do
            [ -z "$uuid" ] && continue
            make_api_request "DELETE" "$domain_url/api/config-profiles/$uuid" "$token" >/dev/null 2>&1
        done <<< "$config_uuids"
    fi
}

create_node() {
    local domain_url=$1
    local token=$2
    local config_profile_uuid=$3
    local inbound_uuid=$4
    local node_address="${5:-172.30.0.1}"
    local node_name="${6:-Steal}"

    local request_body
    request_body=$(jq -n --arg name "$node_name" --arg address "$node_address" \
        --arg config_uuid "$config_profile_uuid" --arg inbound "$inbound_uuid" '{
        name: $name,
        address: $address,
        port: 2222,
        configProfile: {
            activeConfigProfileUuid: $config_uuid,
            activeInbounds: [$inbound]
        },
        isTrafficTrackingActive: false,
        trafficLimitBytes: 0,
        notifyPercent: 0,
        trafficResetDay: 31,
        excludedInbounds: [],
        countryCode: "XX",
        consumptionMultiplier: 1.0
    }')

    local response
    response=$(make_api_request "POST" "$domain_url/api/nodes" "$token" "$request_body")

    if echo "$response" | jq -e '.response.uuid' >/dev/null 2>&1; then
        return 0
    else
        echo "ERROR: $response" >&2
        return 1
    fi
}

create_host() {
    local domain_url=$1
    local token=$2
    local config_uuid=$3
    local inbound_uuid=$4
    local remark=$5
    local address=$6

    local request_body
    request_body=$(jq -n --arg config_uuid "$config_uuid" --arg inbound_uuid "$inbound_uuid" \
        --arg remark "$remark" --arg address "$address" '{
        inbound: {
            configProfileUuid: $config_uuid,
            configProfileInboundUuid: $inbound_uuid
        },
        remark: $remark,
        address: $address,
        port: 443,
        path: "",
        sni: $address,
        host: "",
        alpn: null,
        fingerprint: "chrome",
        allowInsecure: false,
        isDisabled: false,
        securityLayer: "DEFAULT"
    }')

    make_api_request "POST" "$domain_url/api/hosts" "$token" "$request_body" >/dev/null
}

get_default_squad() {
    local domain_url=$1
    local token=$2

    local response
    response=$(make_api_request "GET" "$domain_url/api/internal-squads" "$token")
    echo "$response" | jq -r '.response.internalSquads[].uuid // empty' 2>/dev/null
}

update_squad() {
    local domain_url=$1
    local token=$2
    local squad_uuid=$3
    local inbound_uuid=$4

    local current
    current=$(make_api_request "GET" "$domain_url/api/internal-squads" "$token")

    # Получаем текущие inbounds сквада
    local current_inbounds
    current_inbounds=$(echo "$current" | jq -r --arg uuid "$squad_uuid" \
        '[.response.internalSquads[] | select(.uuid == $uuid) | .inbounds[].uuid] // []' 2>/dev/null)

    # Добавляем новый inbound к существующим
    local inbounds_array
    inbounds_array=$(echo "$current_inbounds" | jq --arg inbound "$inbound_uuid" \
        '. + [$inbound] | unique | map({uuid: .})' 2>/dev/null)

    local request_body
    request_body=$(jq -n --arg uuid "$squad_uuid" --argjson inbounds "$inbounds_array" '{
        uuid: $uuid,
        inbounds: $inbounds
    }')

    make_api_request "PATCH" "$domain_url/api/internal-squads" "$token" "$request_body" >/dev/null
}

create_api_token() {
    local domain_url=$1
    local token=$2
    local target_dir=${3:-${DIR_PANEL}}

    local request_body='{"tokenName":"subscription-page"}'
    local response
    response=$(make_api_request "POST" "$domain_url/api/tokens" "$token" "$request_body")

    local api_token
    api_token=$(echo "$response" | jq -r '.response.token // empty' 2>/dev/null)

    if [ -z "$api_token" ] || [ "$api_token" = "null" ]; then
        print_error "Не удалось создать API токен: $(echo "$response" | jq -r '.message // "Unknown error"')"
        return 1
    fi

    if grep -q "^REMNAWAVE_API_TOKEN=" "$target_dir/.env" 2>/dev/null; then
        sed -i "s|^REMNAWAVE_API_TOKEN=.*|REMNAWAVE_API_TOKEN=$api_token|" "$target_dir/.env"
    else
        echo "REMNAWAVE_API_TOKEN=$api_token" >> "$target_dir/.env"
    fi
    print_success "Регистрация API токена"
}

# ═══════════════════════════════════════════════
# ПОДКЛЮЧИТЬ НОДУ В ПАНЕЛЬ (РЕГИСТРАЦИЯ В ПАНЕЛИ)
# ═══════════════════════════════════════════════
add_node_to_panel() {
    # Проверяем, что панель установлена на этом сервере
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
    echo -e "${GREEN}   ➕ ПОДКЛЮЧИТЬ НОДУ В ПАНЕЛЬ${NC}"
    echo -e "${BLUE}══════════════════════════════════════${NC}"
    echo
    echo -e "${DARKGRAY}Регистрация ноды на удалённом сервере в панели.${NC}"
    echo -e "${DARKGRAY}После регистрации установите ноду на целевом сервере${NC}"
    echo -e "${DARKGRAY}через \"Только нода\".${NC}"

    # Получаем токен
    echo
    get_panel_token
    if [ $? -ne 0 ]; then
        print_error "Не удалось получить токен"
        echo
        read -s -n 1 -p "$(echo -e "${DARKGRAY}Нажмите любую клавишу для продолжения...${NC}")"
        echo
        return
    fi
    local token
    token=$(cat "${DIR_REMNAWAVE}/token")

    # Запрашиваем домен ноды с проверкой уникальности
    local SELFSTEAL_DOMAIN
    while true; do
        reading_inline "Введите selfsteal домен для ноды (например, node.example.com):" SELFSTEAL_DOMAIN
        check_node_domain "$domain_url" "$token" "$SELFSTEAL_DOMAIN"
        if [ $? -eq 0 ]; then
            break
        fi
        echo -e "${YELLOW}Пожалуйста, используйте другой домен${NC}"
    done

    # Запрашиваем имя ноды
    local entity_name
    while true; do
        reading_inline "Введите имя для вашей ноды (например, Germany):" entity_name
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
    done

    # ─── API: регистрация ноды ───
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
    config_result=$(create_config_profile "$domain_url" "$token" "$entity_name" "$SELFSTEAL_DOMAIN" "$private_key" "$entity_name")
    if [ $? -ne 0 ]; then
        print_error "Не удалось создать конфигурационный профиль"
        return 1
    fi
    read config_profile_uuid inbound_uuid <<< "$config_result"
    print_success "Конфигурационный профиль: $entity_name"

    print_action "Создание ноды ($entity_name)..."
    create_node "$domain_url" "$token" "$config_profile_uuid" "$inbound_uuid" "$SELFSTEAL_DOMAIN" "$entity_name"
    if [ $? -eq 0 ]; then
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

    # ─── Финал ───
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


# ═══════════════════════════════════════════════
# ШАБЛОНЫ SELFSTEAL
# ═══════════════════════════════════════════════

# Список шаблонов: ID|Название
get_templates_list() {
    echo "1|NexCore - Корпоративный портал"
    echo "2|DevForge - Технологический хаб"
    echo "3|Nimbus - Облачные сервисы"
    echo "4|PayVault - Финтех платформа"
    echo "5|LearnHub - Образовательная платформа"
    echo "6|StreamBox - Медиа портал"
    echo "7|ShopWave - E-commerce"
    echo "8|NeonArena - Игровой портал"
    echo "9|ConnectMe - Социальная сеть"
    echo "10|DataPulse - Аналитический центр"
    echo "11|CryptoNex - Крипто биржа"
    echo "12|WanderWorld - Туристическое агентство"
    echo "13|IronPulse - Фитнес платформа"
    echo "14|ВестникПРО - Новостной портал"
    echo "15|SoundWave - Музыкальный сервис"
    echo "16|HomeNest - Недвижимость"
    echo "17|FastBite - Доставка еды"
    echo "18|AutoElite - Автомобильный портал"
    echo "19|Prisma Studio - Дизайн студия"
    echo "20|Vertex Advisory - Консалтинг центр"
}

# Применить конкретный шаблон (скачивание с GitHub)
apply_template() {
    local template_id=$1
    
    local template_data=$(get_templates_list | grep "^${template_id}|")
    if [ -z "$template_data" ]; then
        echo -e "${RED}✖${NC} Шаблон #${template_id} не найден"
        return 1
    fi
    
    IFS='|' read -r id name <<< "$template_data"
    
    echo ""
    
    # Очищаем директорию (кроме метаданных)
    find /var/www/html/ -mindepth 1 -not -name '.current_template' -not -name '.template_changed' -delete 2>/dev/null
    
    # Скачиваем шаблон с GitHub
    local base_url="https://raw.githubusercontent.com/DanteFuaran/dfc-remna-install/dev/templates/${template_id}"
    local cache_bust="?t=$(date +%s)"
    
    if curl -fsSL "${base_url}/index.html${cache_bust}" -o /var/www/html/index.html; then
        echo "$name" > /var/www/.current_template
        echo "$(date '+%Y-%m-%d %H:%M:%S')" > /var/www/.template_changed
        echo -e "${GREEN}✅${NC} Установлен шаблон: ${WHITE}${name}${NC}"
    else
        echo -e "${RED}✖${NC} Ошибка загрузки шаблона. Проверьте интернет-соединение."
        # Создаём заглушку на случай ошибки
        echo "<html><body><h1>Site under maintenance</h1></body></html>" > /var/www/html/index.html
        return 1
    fi
}

# Случайный шаблон
randomhtml() {
    local random_id=$((RANDOM % 20 + 1))
    apply_template "$random_id"
}

# ═══════════════════════════════════════════════
# ГЕНЕРАЦИЯ .ENV
# ═══════════════════════════════════════════════
generate_env_file() {
    local panel_domain=$1
    local sub_domain=$2

    local jwt_auth_secret
    jwt_auth_secret=$(generate_secret)
    local jwt_api_secret
    jwt_api_secret=$(generate_secret)
    local webhook_secret
    webhook_secret=$(generate_webhook_secret)
    local metrics_user
    metrics_user=$(generate_username)
    local metrics_pass
    metrics_pass=$(generate_password)

    cat > /opt/remnawave/.env <<EOL
### APP ###
APP_PORT=3000
METRICS_PORT=3001

### API ###
# Possible values: max (start instances on all cores), number (start instances on number of cores), -1 (start instances on all cores - 1)
# !!! Do not set this value more than physical cores count in your machine !!!
# Review documentation: https://remna.st/docs/install/environment-variables#scaling-api
API_INSTANCES=1

### DATABASE ###
# FORMAT: postgresql://{user}:{password}@{host}:{port}/{database}
DATABASE_URL="postgresql://postgres:postgres@remnawave-db:5432/postgres"

### REDIS ###
REDIS_HOST=remnawave-redis
REDIS_PORT=6379

### JWT ###
JWT_AUTH_SECRET=$jwt_auth_secret
JWT_API_TOKENS_SECRET=$jwt_api_secret

# Set the session idle timeout in the panel to avoid daily logins.
# Value in hours: 12–168
JWT_AUTH_LIFETIME=168

### TELEGRAM NOTIFICATIONS ###
IS_TELEGRAM_NOTIFICATIONS_ENABLED=false
TELEGRAM_BOT_TOKEN=change_me
TELEGRAM_NOTIFY_USERS_CHAT_ID=change_me
TELEGRAM_NOTIFY_NODES_CHAT_ID=change_me
TELEGRAM_NOTIFY_CRM_CHAT_ID=change_me

# Optional
# Only set if you want to use topics
TELEGRAM_NOTIFY_USERS_THREAD_ID=
TELEGRAM_NOTIFY_NODES_THREAD_ID=
TELEGRAM_NOTIFY_CRM_THREAD_ID=

### FRONT_END ###
# Used by CORS, you can leave it as * or place your domain there
FRONT_END_DOMAIN=$panel_domain

### SUBSCRIPTION PUBLIC DOMAIN ###
### DOMAIN, WITHOUT HTTP/HTTPS, DO NOT ADD / AT THE END ###
### Used in "profile-web-page-url" response header and in UI/API ###
### Review documentation: https://remna.st/docs/install/environment-variables#domains
SUB_PUBLIC_DOMAIN=$sub_domain

### If CUSTOM_SUB_PREFIX is set in @remnawave/subscription-page, append the same path to SUB_PUBLIC_DOMAIN. Example: SUB_PUBLIC_DOMAIN=sub-page.example.com/sub ###

### SWAGGER ###
SWAGGER_PATH=/docs
SCALAR_PATH=/scalar
IS_DOCS_ENABLED=false

### PROMETHEUS ###
### Metrics are available at /api/metrics
METRICS_USER=$metrics_user
METRICS_PASS=$metrics_pass

### Webhook configuration
### Enable webhook notifications (true/false, defaults to false if not set or empty)
WEBHOOK_ENABLED=false
### Webhook URL to send notifications to (can specify multiple URLs separated by commas if needed)
### Only http:// or https:// are allowed.
WEBHOOK_URL=https://your-webhook-url.com/endpoint
### This secret is used to sign the webhook payload, must be exact 64 characters. Only a-z, 0-9, A-Z are allowed.
WEBHOOK_SECRET_HEADER=$webhook_secret

### Bandwidth usage reached notifications
BANDWIDTH_USAGE_NOTIFICATIONS_ENABLED=false
# Only in ASC order (example: [60, 80]), must be valid array of integer(min: 25, max: 95) numbers. No more than 5 values.
BANDWIDTH_USAGE_NOTIFICATIONS_THRESHOLD=[60, 80]

### CLOUDFLARE ###
# USED ONLY FOR docker-compose-prod-with-cf.yml
# NOT USED BY THE APP ITSELF
CLOUDFLARE_TOKEN=ey...

### Database ###
### For Postgres Docker container ###
# NOT USED BY THE APP ITSELF
POSTGRES_USER=postgres
POSTGRES_PASSWORD=postgres
POSTGRES_DB=postgres

### SUBSCRIPTION PAGE ###
REMNAWAVE_API_TOKEN=
EOL
}

# ═══════════════════════════════════════════════
# ГЕНЕРАЦИЯ DOCKER-COMPOSE
# ═══════════════════════════════════════════════
generate_docker_compose_full() {
    local panel_cert_domain=$1
    local sub_cert_domain=$2
    local node_cert_domain=$3

    # Проверяем, существует ли сеть remnawave-network
    local network_exists=false
    if docker network ls | grep -q "remnawave-network"; then
        network_exists=true
    fi

    cat > /opt/remnawave/docker-compose.yml <<'COMPOSE_HEAD'
services:
  remnawave-db:
    image: postgres:18.1
    container_name: 'remnawave-db'
    hostname: remnawave-db
    restart: always
    ulimits:
      nofile:
        soft: 1048576
        hard: 1048576
    env_file:
      - .env
    environment:
      - POSTGRES_USER=${POSTGRES_USER}
      - POSTGRES_PASSWORD=${POSTGRES_PASSWORD}
      - POSTGRES_DB=${POSTGRES_DB}
      - TZ=UTC
    ports:
      - '127.0.0.1:6767:5432'
    volumes:
      - remnawave-db-data:/var/lib/postgresql
    networks:
      - remnawave-network
    healthcheck:
      test: ['CMD-SHELL', 'pg_isready -U $${POSTGRES_USER} -d $${POSTGRES_DB}']
      interval: 3s
      timeout: 10s
      retries: 3
    logging:
      driver: 'json-file'
      options:
        max-size: '30m'
        max-file: '5'

  remnawave:
    image: remnawave/backend:2
    container_name: remnawave
    hostname: remnawave
    restart: always
    ulimits:
      nofile:
        soft: 1048576
        hard: 1048576
    env_file:
      - .env
    ports:
      - '127.0.0.1:3000:${APP_PORT:-3000}'
      - '127.0.0.1:3001:${METRICS_PORT:-3001}'
    networks:
      - remnawave-network
    healthcheck:
      test: ['CMD-SHELL', 'curl -f http://localhost:${METRICS_PORT:-3001}/health']
      interval: 30s
      timeout: 5s
      retries: 3
      start_period: 30s
    depends_on:
      remnawave-db:
        condition: service_healthy
      remnawave-redis:
        condition: service_healthy
    logging:
      driver: 'json-file'
      options:
        max-size: '30m'
        max-file: '5'

  remnawave-redis:
    image: valkey/valkey:9.0.0-alpine
    container_name: remnawave-redis
    hostname: remnawave-redis
    restart: always
    ulimits:
      nofile:
        soft: 1048576
        hard: 1048576
    networks:
      - remnawave-network
    command: >
      valkey-server
      --save ""
      --appendonly no
      --maxmemory-policy noeviction
      --loglevel warning
    healthcheck:
      test: ['CMD', 'valkey-cli', 'ping']
      interval: 3s
      timeout: 10s
      retries: 3
    logging:
      driver: 'json-file'
      options:
        max-size: '30m'
        max-file: '5'

  remnawave-nginx:
    image: nginx:1.28
    container_name: remnawave-nginx
    hostname: remnawave-nginx
    network_mode: host
    restart: always
    ulimits:
      nofile:
        soft: 1048576
        hard: 1048576
    volumes:
      - ./nginx.conf:/etc/nginx/conf.d/default.conf:ro
COMPOSE_HEAD

    # Монтируем сертификаты для каждого домена
    for cert in "$panel_cert_domain" "$sub_cert_domain" "$node_cert_domain"; do
        cat >> /opt/remnawave/docker-compose.yml <<COMPOSE_CERT
      - /etc/letsencrypt/live/$cert/fullchain.pem:/etc/nginx/ssl/$cert/fullchain.pem:ro
      - /etc/letsencrypt/live/$cert/privkey.pem:/etc/nginx/ssl/$cert/privkey.pem:ro
COMPOSE_CERT
    done

    cat >> /opt/remnawave/docker-compose.yml <<'COMPOSE_TAIL'
      - /dev/shm:/dev/shm:rw
      - /var/www/html:/var/www/html:ro
    command: sh -c 'rm -f /dev/shm/nginx.sock && exec nginx -g "daemon off;"'
    depends_on:
      - remnawave
      - remnawave-subscription-page
    logging:
      driver: 'json-file'
      options:
        max-size: '30m'
        max-file: '5'

  remnawave-subscription-page:
    image: remnawave/subscription-page:latest
    container_name: remnawave-subscription-page
    hostname: remnawave-subscription-page
    restart: always
    ulimits:
      nofile:
        soft: 1048576
        hard: 1048576
    depends_on:
      remnawave:
        condition: service_healthy
    environment:
      - REMNAWAVE_PANEL_URL=http://remnawave:3000
      - APP_PORT=3010
      - REMNAWAVE_API_TOKEN
    ports:
      - '127.0.0.1:3010:3010'
    networks:
      - remnawave-network
    logging:
      driver: 'json-file'
      options:
        max-size: '30m'
        max-file: '5'

  remnanode:
    image: remnawave/node:latest
    container_name: remnanode
    hostname: remnanode
    restart: always
    ulimits:
      nofile:
        soft: 1048576
        hard: 1048576
    network_mode: host
    environment:
      - NODE_PORT=2222
      - SECRET_KEY="PUBLIC KEY FROM REMNAWAVE-PANEL"
    volumes:
      - /dev/shm:/dev/shm:rw
    logging:
      driver: 'json-file'
      options:
        max-size: '30m'
        max-file: '5'

COMPOSE_TAIL

    # Добавляем networks секцию в зависимости от существования сети
    if [ "$network_exists" = true ]; then
        cat >> /opt/remnawave/docker-compose.yml <<'COMPOSE_NETWORK_EXTERNAL'
networks:
  remnawave-network:
    name: remnawave-network
    external: true

COMPOSE_NETWORK_EXTERNAL
    else
        cat >> /opt/remnawave/docker-compose.yml <<'COMPOSE_NETWORK_NEW'
networks:
  remnawave-network:
    name: remnawave-network
    driver: bridge
    ipam:
      config:
        - subnet: 172.30.0.0/16
    external: false

COMPOSE_NETWORK_NEW
    fi

    cat >> /opt/remnawave/docker-compose.yml <<'COMPOSE_VOLUMES'
volumes:
  remnawave-db-data:
    driver: local
    external: false
    name: remnawave-db-data
COMPOSE_VOLUMES
}

generate_docker_compose_panel() {
    local panel_cert_domain=$1
    local sub_cert_domain=$2

    # Проверяем, существует ли сеть remnawave-network
    local network_exists=false
    if docker network ls | grep -q "remnawave-network"; then
        network_exists=true
    fi

    cat > /opt/remnawave/docker-compose.yml <<'COMPOSE_HEAD'
services:
  remnawave-db:
    image: postgres:18.1
    container_name: 'remnawave-db'
    hostname: remnawave-db
    restart: always
    ulimits:
      nofile:
        soft: 1048576
        hard: 1048576
    env_file:
      - .env
    environment:
      - POSTGRES_USER=${POSTGRES_USER}
      - POSTGRES_PASSWORD=${POSTGRES_PASSWORD}
      - POSTGRES_DB=${POSTGRES_DB}
      - TZ=UTC
    ports:
      - '127.0.0.1:6767:5432'
    volumes:
      - remnawave-db-data:/var/lib/postgresql
    networks:
      - remnawave-network
    healthcheck:
      test: ['CMD-SHELL', 'pg_isready -U $${POSTGRES_USER} -d $${POSTGRES_DB}']
      interval: 3s
      timeout: 10s
      retries: 3
    logging:
      driver: 'json-file'
      options:
        max-size: '30m'
        max-file: '5'

  remnawave:
    image: remnawave/backend:2
    container_name: remnawave
    hostname: remnawave
    restart: always
    ulimits:
      nofile:
        soft: 1048576
        hard: 1048576
    env_file:
      - .env
    ports:
      - '127.0.0.1:3000:${APP_PORT:-3000}'
      - '127.0.0.1:3001:${METRICS_PORT:-3001}'
    networks:
      - remnawave-network
    healthcheck:
      test: ['CMD-SHELL', 'curl -f http://localhost:${METRICS_PORT:-3001}/health']
      interval: 30s
      timeout: 5s
      retries: 3
      start_period: 30s
    depends_on:
      remnawave-db:
        condition: service_healthy
      remnawave-redis:
        condition: service_healthy
    logging:
      driver: 'json-file'
      options:
        max-size: '30m'
        max-file: '5'

  remnawave-redis:
    image: valkey/valkey:9.0.0-alpine
    container_name: remnawave-redis
    hostname: remnawave-redis
    restart: always
    ulimits:
      nofile:
        soft: 1048576
        hard: 1048576
    networks:
      - remnawave-network
    command: >
      valkey-server
      --save ""
      --appendonly no
      --maxmemory-policy noeviction
      --loglevel warning
    healthcheck:
      test: ['CMD', 'valkey-cli', 'ping']
      interval: 3s
      timeout: 10s
      retries: 3
    logging:
      driver: 'json-file'
      options:
        max-size: '30m'
        max-file: '5'

  remnawave-nginx:
    image: nginx:1.28
    container_name: remnawave-nginx
    hostname: remnawave-nginx
    restart: always
    ulimits:
      nofile:
        soft: 1048576
        hard: 1048576
    volumes:
      - ./nginx.conf:/etc/nginx/conf.d/default.conf:ro
COMPOSE_HEAD

    # Монтируем сертификаты для каждого домена
    for cert in "$panel_cert_domain" "$sub_cert_domain"; do
        cat >> /opt/remnawave/docker-compose.yml <<COMPOSE_CERT
      - /etc/letsencrypt/live/$cert/fullchain.pem:/etc/nginx/ssl/$cert/fullchain.pem:ro
      - /etc/letsencrypt/live/$cert/privkey.pem:/etc/nginx/ssl/$cert/privkey.pem:ro
COMPOSE_CERT
    done

    cat >> /opt/remnawave/docker-compose.yml <<'COMPOSE_TAIL'
    network_mode: host
    depends_on:
      - remnawave
      - remnawave-subscription-page
    logging:
      driver: 'json-file'
      options:
        max-size: '30m'
        max-file: '5'

  remnawave-subscription-page:
    image: remnawave/subscription-page:latest
    container_name: remnawave-subscription-page
    hostname: remnawave-subscription-page
    restart: always
    ulimits:
      nofile:
        soft: 1048576
        hard: 1048576
    depends_on:
      remnawave:
        condition: service_healthy
    environment:
      - REMNAWAVE_PANEL_URL=http://remnawave:3000
      - APP_PORT=3010
      - REMNAWAVE_API_TOKEN
    ports:
      - '127.0.0.1:3010:3010'
    networks:
      - remnawave-network
    logging:
      driver: 'json-file'
      options:
        max-size: '30m'
        max-file: '5'

COMPOSE_TAIL

    # Добавляем networks секцию в зависимости от существования сети
    if [ "$network_exists" = true ]; then
        cat >> /opt/remnawave/docker-compose.yml <<'COMPOSE_NETWORK_EXTERNAL'
networks:
  remnawave-network:
    name: remnawave-network
    external: true

COMPOSE_NETWORK_EXTERNAL
    else
        cat >> /opt/remnawave/docker-compose.yml <<'COMPOSE_NETWORK_NEW'
networks:
  remnawave-network:
    name: remnawave-network
    driver: bridge
    external: false

COMPOSE_NETWORK_NEW
    fi

    cat >> /opt/remnawave/docker-compose.yml <<'COMPOSE_VOLUMES'
volumes:
  remnawave-db-data:
    driver: local
    external: false
    name: remnawave-db-data
COMPOSE_VOLUMES
}

# ═══════════════════════════════════════════════
# ГЕНЕРАЦИЯ NGINX.CONF
# ═══════════════════════════════════════════════
generate_nginx_conf_full() {
    local panel_domain=$1
    local sub_domain=$2
    local selfsteal_domain=$3
    local panel_cert=$4
    local sub_cert=$5
    local node_cert=$6
    local cookie_name=$7
    local cookie_value=$8

    cat > /opt/remnawave/nginx.conf <<EOL
server_names_hash_bucket_size 64;

# Не логируем частые Telegram webhook-запросы
map \$request_uri \$loggable {
    ~*/api/v1/telegram 0;
    default 1;
}

# Rate limiting для защиты от сканирования subscription page
limit_req_zone \$binary_remote_addr zone=sub_limit:10m rate=10r/s;

upstream remnawave {
    server 127.0.0.1:3000;
}

upstream json {
    server 127.0.0.1:3010;
}

map \$http_upgrade \$connection_upgrade {
    default upgrade;
    ""      close;
}

map \$http_cookie \$auth_cookie {
    default 0;
    "~*${cookie_name}=${cookie_value}" 1;
}

map \$arg_${cookie_name} \$auth_query {
    default 0;
    "${cookie_value}" 1;
}

map "\$auth_cookie\$auth_query" \$authorized {
    "~1" 1;
    default 0;
}

map \$arg_${cookie_name} \$set_cookie_header {
    "${cookie_value}" "${cookie_name}=${cookie_value}; Path=/; HttpOnly; Secure; SameSite=Strict; Max-Age=31536000";
    default "";
}

ssl_protocols TLSv1.2 TLSv1.3;
ssl_ecdh_curve X25519:prime256v1:secp384r1;
ssl_ciphers ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-ECDSA-CHACHA20-POLY1305:ECDHE-RSA-CHACHA20-POLY1305:DHE-RSA-AES128-GCM-SHA256:DHE-RSA-AES256-GCM-SHA384:DHE-RSA-CHACHA20-POLY1305;
ssl_prefer_server_ciphers on;
ssl_session_timeout 1d;
ssl_session_cache shared:MozSSL:10m;
ssl_session_tickets off;

server {
    server_name $panel_domain;
    listen unix:/dev/shm/nginx.sock ssl proxy_protocol;
    http2 on;

    ssl_certificate "/etc/nginx/ssl/$panel_cert/fullchain.pem";
    ssl_certificate_key "/etc/nginx/ssl/$panel_cert/privkey.pem";
    ssl_trusted_certificate "/etc/nginx/ssl/$panel_cert/fullchain.pem";

    access_log /dev/stdout combined if=\$loggable;

    add_header Set-Cookie \$set_cookie_header;

    location / {
        error_page 418 = @unauthorized;
        recursive_error_pages on;
        if (\$authorized = 0) {
            return 418;
        }
        proxy_http_version 1.1;
        proxy_pass http://remnawave;
        proxy_set_header Host \$host;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection \$connection_upgrade;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_set_header X-Forwarded-Host \$host;
        proxy_set_header X-Forwarded-Port \$server_port;
        proxy_send_timeout 60s;
        proxy_read_timeout 60s;
    }

    location @unauthorized {
        root /var/www/html;
        index index.html;
    }
}

server {
    server_name $sub_domain;
    listen unix:/dev/shm/nginx.sock ssl proxy_protocol;
    http2 on;

    ssl_certificate "/etc/nginx/ssl/$sub_cert/fullchain.pem";
    ssl_certificate_key "/etc/nginx/ssl/$sub_cert/privkey.pem";
    ssl_trusted_certificate "/etc/nginx/ssl/$sub_cert/fullchain.pem";

    access_log /dev/stdout combined if=\$loggable;

    location / {
        limit_req zone=sub_limit burst=20 nodelay;
        limit_req_status 444;

        proxy_http_version 1.1;
        proxy_pass http://json;
        proxy_set_header Host \$host;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection \$connection_upgrade;
        proxy_set_header X-Real-IP \$proxy_protocol_addr;
        proxy_set_header X-Forwarded-For \$proxy_protocol_addr;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_set_header X-Forwarded-Host \$host;
        proxy_set_header X-Forwarded-Port \$server_port;
        proxy_send_timeout 60s;
        proxy_read_timeout 60s;
        proxy_intercept_errors on;
        error_page 400 404 500 502 @redirect;
    }

    location @redirect {
        return 444;
    }
}

server {
    server_name $selfsteal_domain;
    listen unix:/dev/shm/nginx.sock ssl proxy_protocol;
    http2 on;

    ssl_certificate "/etc/nginx/ssl/$node_cert/fullchain.pem";
    ssl_certificate_key "/etc/nginx/ssl/$node_cert/privkey.pem";
    ssl_trusted_certificate "/etc/nginx/ssl/$node_cert/fullchain.pem";

    root /var/www/html;
    index index.html;
    add_header X-Robots-Tag "noindex, nofollow, noarchive, nosnippet, noimageindex" always;
}

server {
    listen unix:/dev/shm/nginx.sock ssl proxy_protocol default_server;
    server_name _;
    add_header X-Robots-Tag "noindex, nofollow, noarchive, nosnippet, noimageindex" always;
    ssl_reject_handshake on;
    return 444;
}
EOL
}

generate_nginx_conf_panel() {
    local panel_domain=$1
    local sub_domain=$2
    local panel_cert=$3
    local sub_cert=$4
    local cookie_name=$5
    local cookie_value=$6

    cat > /opt/remnawave/nginx.conf <<EOL
server_names_hash_bucket_size 64;

# Не логируем частые Telegram webhook-запросы
map \$request_uri \$loggable {
    ~*/api/v1/telegram 0;
    default 1;
}

# Rate limiting для защиты от сканирования subscription page
limit_req_zone \$binary_remote_addr zone=sub_limit:10m rate=10r/s;

upstream remnawave {
    server 127.0.0.1:3000;
}

upstream json {
    server 127.0.0.1:3010;
}

map \$http_upgrade \$connection_upgrade {
    default upgrade;
    ""      close;
}

map \$http_cookie \$auth_cookie {
    default 0;
    "~*${cookie_name}=${cookie_value}" 1;
}

map \$arg_${cookie_name} \$auth_query {
    default 0;
    "${cookie_value}" 1;
}

map "\$auth_cookie\$auth_query" \$authorized {
    "~1" 1;
    default 0;
}

map \$arg_${cookie_name} \$set_cookie_header {
    "${cookie_value}" "${cookie_name}=${cookie_value}; Path=/; HttpOnly; Secure; SameSite=Strict; Max-Age=31536000";
    default "";
}

ssl_protocols TLSv1.2 TLSv1.3;
ssl_ecdh_curve X25519:prime256v1:secp384r1;
ssl_ciphers ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-ECDSA-CHACHA20-POLY1305:ECDHE-RSA-CHACHA20-POLY1305:DHE-RSA-AES128-GCM-SHA256:DHE-RSA-AES256-GCM-SHA384:DHE-RSA-CHACHA20-POLY1305;
ssl_prefer_server_ciphers on;
ssl_session_timeout 1d;
ssl_session_cache shared:MozSSL:10m;

server {
    server_name $panel_domain;
    listen 443 ssl;
    http2 on;

    ssl_certificate "/etc/nginx/ssl/$panel_cert/fullchain.pem";
    ssl_certificate_key "/etc/nginx/ssl/$panel_cert/privkey.pem";
    ssl_trusted_certificate "/etc/nginx/ssl/$panel_cert/fullchain.pem";

    access_log /dev/stdout combined if=\$loggable;

    add_header Set-Cookie \$set_cookie_header;

    location / {
        if (\$authorized = 0) {
            return 444;
        }
        proxy_http_version 1.1;
        proxy_pass http://remnawave;
        proxy_set_header Host \$host;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection \$connection_upgrade;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_set_header X-Forwarded-Host \$host;
        proxy_set_header X-Forwarded-Port \$server_port;
        proxy_send_timeout 60s;
        proxy_read_timeout 60s;
    }
}

server {
    server_name $sub_domain;
    listen 443 ssl;
    http2 on;

    ssl_certificate "/etc/nginx/ssl/$sub_cert/fullchain.pem";
    ssl_certificate_key "/etc/nginx/ssl/$sub_cert/privkey.pem";
    ssl_trusted_certificate "/etc/nginx/ssl/$sub_cert/fullchain.pem";

    access_log /dev/stdout combined if=\$loggable;

    location / {
        limit_req zone=sub_limit burst=20 nodelay;
        limit_req_status 444;

        proxy_http_version 1.1;
        proxy_pass http://json;
        proxy_set_header Host \$host;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection \$connection_upgrade;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_set_header X-Forwarded-Host \$host;
        proxy_set_header X-Forwarded-Port \$server_port;
        proxy_send_timeout 60s;
        proxy_read_timeout 60s;
        proxy_intercept_errors on;
        error_page 400 404 500 502 @redirect;
    }

    location @redirect {
        return 444;
    }
}

server {
    listen 443 ssl default_server;
    server_name _;
    ssl_reject_handshake on;
}
EOL
}

generate_nginx_conf_node() {
    local selfsteal_domain=$1
    local node_cert=$2
    local target_dir="${3:-/opt/remnawave}"

    cat > "${target_dir}/nginx.conf" <<EOL
server_names_hash_bucket_size 64;

map \$http_upgrade \$connection_upgrade {
    default upgrade;
    ""      close;
}

ssl_protocols TLSv1.2 TLSv1.3;
ssl_ecdh_curve X25519:prime256v1:secp384r1;
ssl_ciphers ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-ECDSA-CHACHA20-POLY1305:ECDHE-RSA-CHACHA20-POLY1305:DHE-RSA-AES128-GCM-SHA256:DHE-RSA-AES256-GCM-SHA384:DHE-RSA-CHACHA20-POLY1305;
ssl_prefer_server_ciphers on;
ssl_session_timeout 1d;
ssl_session_cache shared:MozSSL:10m;
ssl_session_tickets off;

server {
    server_name $selfsteal_domain;
    listen unix:/dev/shm/nginx.sock ssl proxy_protocol;
    http2 on;

    ssl_certificate "/etc/nginx/ssl/$node_cert/fullchain.pem";
    ssl_certificate_key "/etc/nginx/ssl/$node_cert/privkey.pem";
    ssl_trusted_certificate "/etc/nginx/ssl/$node_cert/fullchain.pem";

    root /var/www/html;
    index index.html;
    add_header X-Robots-Tag "noindex, nofollow, noarchive, nosnippet, noimageindex" always;
}

server {
    listen unix:/dev/shm/nginx.sock ssl proxy_protocol default_server;
    server_name _;
    add_header X-Robots-Tag "noindex, nofollow, noarchive, nosnippet, noimageindex" always;
    ssl_reject_handshake on;
    return 444;
}
EOL
}

# ═══════════════════════════════════════════════
# УСТАНОВКА: ПАНЕЛЬ + НОДА
# ═══════════════════════════════════════════════
installation_full() {
    # Гарантируем валидную рабочую директорию перед началом
    cd /opt 2>/dev/null || cd / 2>/dev/null

    # Проверяем, не установлено ли уже
    if [ -f "/opt/remnawave/docker-compose.yml" ]; then
        clear
        echo
        echo -e "${BLUE}══════════════════════════════════════${NC}"
        echo -e "   ${YELLOW}⚠️  REMNAWAVE УЖЕ УСТАНОВЛЕН${NC}"
        echo -e "${BLUE}══════════════════════════════════════${NC}"
        echo
        echo -e "${WHITE}На этом сервере уже установлен Remnawave.${NC}"
        echo -e "${WHITE}Используйте опцию ${GREEN}"🔄 Переустановить"${WHITE} в главном меню.${NC}"
        echo
        read -s -n 1 -p "$(echo -e "${DARKGRAY}Нажмите любую клавишу для продолжения...${NC}")"
        echo
        return
    fi

    # Проверяем, это первичная установка?
    local is_fresh_install=false
    if [ ! -d "${DIR_PANEL}" ] || [ -z "$(ls -A "${DIR_PANEL}" 2>/dev/null)" ]; then
        is_fresh_install=true
    fi

    clear
    echo -e "${BLUE}══════════════════════════════════════${NC}"
    echo -e "${GREEN}   📦 УСТАНОВКА ПАНЕЛИ + НОДЫ${NC}"
    echo -e "${BLUE}══════════════════════════════════════${NC}"

    mkdir -p "${DIR_PANEL}" && cd "${DIR_PANEL}"

    # Устанавливаем trap для удаления при прерывании (только для первичной установки)
    if [ "$is_fresh_install" = true ]; then
        trap 'echo; echo -e "${RED}Установка прервана пользователем${NC}"; echo; rm -rf "${DIR_PANEL}" "${DIR_REMNAWAVE}" 2>/dev/null; exit 1' INT TERM
    fi

    # Домены
    prompt_domain_with_retry "Домен панели (например panel.example.com):" PANEL_DOMAIN || { [ "$is_fresh_install" = true ] && rm -rf "${DIR_PANEL}" "${DIR_REMNAWAVE}" 2>/dev/null; return; }
    prompt_domain_with_retry "Домен подписки (например sub.example.com):" SUB_DOMAIN true || { [ "$is_fresh_install" = true ] && rm -rf "${DIR_PANEL}" "${DIR_REMNAWAVE}" 2>/dev/null; return; }
    prompt_domain_with_retry "Домен selfsteal/ноды (например node.example.com):" SELFSTEAL_DOMAIN true || { [ "$is_fresh_install" = true ] && rm -rf "${DIR_PANEL}" "${DIR_REMNAWAVE}" 2>/dev/null; return; }

    # Автогенерация учётных данных администратора
    local SUPERADMIN_USERNAME
    local SUPERADMIN_PASSWORD
    SUPERADMIN_USERNAME=$(generate_admin_username)
    SUPERADMIN_PASSWORD=$(generate_admin_password)

    # Название ноды
    local entity_name=""
    while true; do
        reading "Название ноды (Пример: Germany):" entity_name
        if [[ "$entity_name" =~ ^[a-zA-Z0-9-]+$ ]]; then
            if [ ${#entity_name} -ge 3 ] && [ ${#entity_name} -le 20 ]; then
                break
            else
                print_error "Название должно быть от 3 до 20 символов"
            fi
        else
            print_error "Допустимы только символы: a-zA-Z0-9 и дефис"
        fi
    done

    # Сертификаты
    declare -A domains_to_check
    domains_to_check["$PANEL_DOMAIN"]=1
    domains_to_check["$SUB_DOMAIN"]=1
    domains_to_check["$SELFSTEAL_DOMAIN"]=1

    if check_if_certificates_needed domains_to_check; then
        echo
        show_arrow_menu "🔐 МЕТОД ПОЛУЧЕНИЯ СЕРТИФИКАТОВ" \
            "☁️   Cloudflare DNS-01 (wildcard)" \
            "🌐  ACME HTTP-01 (Let's Encrypt)" \
            "──────────────────────────────────────" \
            "❌  Назад"
        local cert_choice=$?

        case $cert_choice in
            0) CERT_METHOD=1 ;;
            1) CERT_METHOD=2 ;;
            2) continue ;;
            3) return ;;
        esac

        reading "Email для Let's Encrypt:" LETSENCRYPT_EMAIL
        echo

        if [ "$CERT_METHOD" -eq 1 ]; then
            setup_cloudflare_credentials || return
        fi

        handle_certificates domains_to_check "$CERT_METHOD" "$LETSENCRYPT_EMAIL"
    else
        CERT_METHOD=$(detect_cert_method "$PANEL_DOMAIN")
        echo
        for domain in "${!domains_to_check[@]}"; do
            print_success "Сертификат для $domain уже существует"
        done
    fi

    # Определяем домены сертификатов
    local PANEL_CERT_DOMAIN SUB_CERT_DOMAIN NODE_CERT_DOMAIN
    if [ "$CERT_METHOD" -eq 1 ]; then
        PANEL_CERT_DOMAIN=$(extract_domain "$PANEL_DOMAIN")
        SUB_CERT_DOMAIN=$(extract_domain "$SUB_DOMAIN")
        NODE_CERT_DOMAIN=$(extract_domain "$SELFSTEAL_DOMAIN")
    else
        PANEL_CERT_DOMAIN="$PANEL_DOMAIN"
        SUB_CERT_DOMAIN="$SUB_DOMAIN"
        NODE_CERT_DOMAIN="$SELFSTEAL_DOMAIN"
    fi

    # Генерируем конфиги
    echo
    print_action "Генерация конфигурации..."

    # Генерируем cookie для защиты панели
    local COOKIE_NAME COOKIE_VALUE
    COOKIE_NAME=$(generate_cookie_key)
    COOKIE_VALUE=$(generate_cookie_key)

    (
        generate_env_file "$PANEL_DOMAIN" "$SUB_DOMAIN"
    ) &
    show_spinner "Создание .env файла"

    (
        generate_docker_compose_full "$PANEL_CERT_DOMAIN" "$SUB_CERT_DOMAIN" "$NODE_CERT_DOMAIN"
    ) &
    show_spinner "Создание docker-compose.yml"

    (
        generate_nginx_conf_full "$PANEL_DOMAIN" "$SUB_DOMAIN" "$SELFSTEAL_DOMAIN" \
            "$PANEL_CERT_DOMAIN" "$SUB_CERT_DOMAIN" "$NODE_CERT_DOMAIN" \
            "$COOKIE_NAME" "$COOKIE_VALUE"
    ) &
    show_spinner "Создание nginx.conf"

    # UFW для ноды
    (
        remnawave_network_subnet=172.30.0.0/16
        ufw allow from "$remnawave_network_subnet" to any port 2222 proto tcp >/dev/null 2>&1
    ) &
    show_spinner "Настройка файрвола"

    # Запуск
    echo
    print_action "Запуск сервисов..."

    (
        cd /opt/remnawave
        docker compose up -d >/dev/null 2>&1
    ) &
    show_spinner "Запуск Docker контейнеров"

    # Ожидание готовности
    show_spinner_timer 20 "Ожидание запуска Remnawave" "Запуск Remnawave"

    local domain_url="127.0.0.1:3000"
    local target_dir="${DIR_PANEL}"

    show_spinner_until_ready "http://$domain_url/api/auth/status" "Проверка доступности API" 120
    if [ $? -ne 0 ]; then
        print_error "API не отвечает. Проверьте: docker compose -f /opt/remnawave/docker-compose.yml logs"
        return
    fi

    # ═══════════════════════════════════════════
    # АВТОНАСТРОЙКА: РЕГИСТРАЦИЯ И СОЗДАНИЕ НОДЫ
    # ═══════════════════════════════════════════
    echo
    print_action "Автонастройка панели и ноды..."

    # 1. Регистрация суперадмина → получение токена
    print_action "Регистрация администратора..."
    local token
    token=$(register_remnawave "$domain_url" "$SUPERADMIN_USERNAME" "$SUPERADMIN_PASSWORD")

    if [ -z "$token" ]; then
        print_error "Не удалось получить токен авторизации"
        print_error "Настройте ноду вручную через панель: https://$PANEL_DOMAIN"
        randomhtml
        echo
        echo -e "${BLUE}══════════════════════════════════════${NC}"
        echo -e "${GREEN}   ⚠️  УСТАНОВКА ЧАСТИЧНО ЗАВЕРШЕНА${NC}"
        echo -e "${BLUE}══════════════════════════════════════${NC}"
        echo
        echo -e "${WHITE}Панель:${NC}       https://$PANEL_DOMAIN"
        echo -e "${WHITE}Подписка:${NC}     https://$SUB_DOMAIN"
        echo -e "${WHITE}SelfSteal:${NC}    https://$SELFSTEAL_DOMAIN"
        echo
        echo -e "${YELLOW}👤 ЛОГИН:${NC}    ${WHITE}$SUPERADMIN_USERNAME${NC}"
        echo -e "${YELLOW}🔑 ПАРОЛЬ:${NC}   ${WHITE}$SUPERADMIN_PASSWORD${NC}"
        echo
        echo -e "${RED}⚠️  Нода не настроена автоматически. Настройте вручную.${NC}"
        echo
        echo -e "${RED}⚠️  ОБЯЗАТЕЛЬНО СКОПИРУЙТЕ И СОХРАНИТЕ ЭТИ ДАННЫЕ!${NC}"
        echo
        read -s -n 1 -p "$(echo -e "${DARKGRAY}Нажмите любую клавишу для продолжения...${NC}")"
        echo
        return
    fi

    # 2. Получение публичного ключа → SECRET_KEY для ноды
    print_action "Получение публичного ключа панели..."
    get_public_key "$domain_url" "$token" "$target_dir"

    # Проверяем, что SECRET_KEY реально обновлён
    if grep -q 'PUBLIC KEY FROM REMNAWAVE-PANEL' "$target_dir/docker-compose.yml" 2>/dev/null; then
        print_error "Не удалось установить публичный ключ"
        return
    fi
    print_success "Установка публичного ключа"

    # 3. Генерация ключей x25519 (REALITY)
    print_action "Генерация REALITY ключей..."
    local private_key
    private_key=$(generate_xray_keys "$domain_url" "$token")

    if [ -z "$private_key" ]; then
        print_error "Не удалось сгенерировать REALITY ключи"
        return
    fi

    # 4. Удаление дефолтного config profile
    print_action "Удаление дефолтного конфиг-профиля..."
    delete_config_profile "$domain_url" "$token"

    # 5. Создание config profile с VLESS REALITY
    print_action "Создание конфиг-профиля ($entity_name)..."
    local config_result
    config_result=$(create_config_profile "$domain_url" "$token" "$entity_name" "$SELFSTEAL_DOMAIN" "$private_key" "$entity_name")

    local config_profile_uuid inbound_uuid
    read config_profile_uuid inbound_uuid <<< "$config_result"

    if [ -z "$config_profile_uuid" ] || [ "$config_profile_uuid" = "ERROR" ] || \
       [ -z "$inbound_uuid" ]; then
        print_error "Не удалось создать конфиг-профиль"
        return
    fi

    # 6. Создание ноды
    print_action "Создание ноды ($entity_name)..."
    create_node "$domain_url" "$token" "$config_profile_uuid" "$inbound_uuid" "172.30.0.1" "$entity_name"
    if [ $? -eq 0 ]; then
        print_success "Создание ноды"
    else
        print_error "Не удалось создать ноду"
    fi

    # 7. Создание хоста
    print_action "Создание хоста ($SELFSTEAL_DOMAIN)..."
    create_host "$domain_url" "$token" "$config_profile_uuid" "$inbound_uuid" "$entity_name" "$SELFSTEAL_DOMAIN"
    print_success "Регистрация хоста"

    # 8. Получение и обновление сквадов
    print_action "Настройка сквадов..."
    local squad_uuids
    squad_uuids=$(get_default_squad "$domain_url" "$token")

    if [ -n "$squad_uuids" ]; then
        while IFS= read -r squad_uuid; do
            [ -z "$squad_uuid" ] && continue
            update_squad "$domain_url" "$token" "$squad_uuid" "$inbound_uuid"
        done <<< "$squad_uuids"
        print_success "Обновление сквадов"
    else
        echo -e "${YELLOW}⚠️  Сквады не найдены (будут настроены при создании пользователей)${NC}"
    fi

    # 9. Создание API токена для subscription-page
    print_action "Создание API токена для страницы подписки..."
    create_api_token "$domain_url" "$token" "$target_dir"

    # 10. Перезапуск Docker Compose (с обновлённым docker-compose.yml)
    print_action "Перезапуск сервисов с обновлённой конфигурацией..."
    (
        cd /opt/remnawave
        docker compose down >/dev/null 2>&1
        docker compose up -d >/dev/null 2>&1
    ) &
    show_spinner "Запуск контейнеров"

    # 11. Шаблон selfsteal
    randomhtml

    # Ожидаем готовность после перезапуска
    show_spinner_timer 15 "Ожидание запуска сервисов" "Запуск сервисов"

    show_spinner_until_ready "http://$domain_url/api/auth/status" "Проверка доступности панели" 120

    # Верификация: ждём пока remnanode запустит xray на порту 443
    print_action "Ожидание подключения ноды (xray → порт 443)..."
    local verify_ok=false
    local verify_elapsed=0
    local verify_timeout=60
    while [ $verify_elapsed -lt $verify_timeout ]; do
        if ss -tuln 2>/dev/null | grep -q ':443 '; then
            verify_ok=true
            break
        fi
        sleep 2
        ((verify_elapsed+=2))
    done
    if [ "$verify_ok" = true ]; then
        print_success "Порт 443 активен — xray (remnanode) работает"
    else
        echo -e "${YELLOW}⚠️  Порт 443 пока не активен — нода может ещё подключаться${NC}"
    fi

    # 12. Сброс суперадмина — при первом входе пользователь задаст свои данные
    print_action "Сброс суперадмина для первого входа..."
    docker exec -i remnawave-db psql -U postgres -d postgres -c "DELETE FROM admin;" >/dev/null 2>&1
    if [ $? -eq 0 ]; then
        print_success "Суперадмин сброшен"
    else
        print_error "Не удалось сбросить суперадмина"
    fi

    # Удаляем trap при успешном завершении
    if [ "$is_fresh_install" = true ]; then
        trap - INT TERM
    fi

    # Автоматически включаем доступ по 8443 для panel+node
    auto_enable_panel_access_8443 "$PANEL_DOMAIN" "$COOKIE_NAME" "$COOKIE_VALUE"

    # Итог
    clear
    tput civis 2>/dev/null
    echo
    echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}"
    echo -e "                   ${GREEN}🎉 УСТАНОВКА ЗАВЕРШЕНА!${NC}"
    echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}"
    echo
    echo -e "${YELLOW}⚠️  ВАЖНО: XRAY (selfsteal) занимает порт 443 для работы VPN.${NC}"
    echo -e "${WHITE}   Панель доступна через порт 8443 (автоматически включен).${NC}"
    echo
    echo -e "${YELLOW}🔗 Ссылка для входа в панель:${NC}"
    echo -e "${WHITE}https://${PANEL_DOMAIN}:8443/auth/login?${COOKIE_NAME}=${COOKIE_VALUE}${NC}"
    echo
    echo -e "${YELLOW}📋 Команды запуска меню управления:${NC}"
    echo -e "${GREEN}dfc-remna-install${NC} или ${GREEN}dfc-ri${NC}"
    echo
    echo -e "${DARKGRAY}───────────────────────────────────────────────────────────${NC}"
    echo
    echo -e "${YELLOW}⚠️  При первом входе в панель произойдет создание администратора.${NC}"
    echo -e "${YELLOW}   Сбросить данные администратора и куки для входа можно в любое${NC}"
    echo -e "${YELLOW}   время через главное меню скрипта.${NC}"
    echo
    echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}"
    echo
    read -s -n 1 -p "$(echo -e "${DARKGRAY}Нажмите любую клавишу для продолжения...${NC}")"
        echo
}

# ═══════════════════════════════════════════════
# УСТАНОВКА: ТОЛЬКО ПАНЕЛЬ
# ═══════════════════════════════════════════════
installation_panel() {
    # Гарантируем валидную рабочую директорию перед началом
    cd /opt 2>/dev/null || cd / 2>/dev/null

    # Проверяем, не установлена ли уже панель
    if [ -f "/opt/remnawave/docker-compose.yml" ]; then
        clear
        echo
        echo -e "${BLUE}══════════════════════════════════════${NC}"
        echo -e "   ${YELLOW}⚠️  ПАНЕЛЬ УЖЕ УСТАНОВЛЕНА${NC}"
        echo -e "${BLUE}══════════════════════════════════════${NC}"
        echo
        echo -e "${WHITE}На этом сервере уже установлена панель.${NC}"
        echo -e "${WHITE}Используйте опцию ${GREEN}"🔄 Переустановить"${WHITE} в главном меню.${NC}"
        echo
        read -s -n 1 -p "$(echo -e "${DARKGRAY}Нажмите любую клавишу для продолжения...${NC}")"
        echo
        return
    fi

    # Проверяем, это первичная установка?
    local is_fresh_install=false
    if [ ! -d "${DIR_PANEL}" ] || [ -z "$(ls -A "${DIR_PANEL}" 2>/dev/null)" ]; then
        is_fresh_install=true
    fi

    clear
    echo -e "${BLUE}══════════════════════════════════════${NC}"
    echo -e "${GREEN}   📦 УСТАНОВКА ТОЛЬКО ПАНЕЛИ${NC}"
    echo -e "${BLUE}══════════════════════════════════════${NC}"
    mkdir -p "${DIR_PANEL}" && cd "${DIR_PANEL}"

    # Устанавливаем trap для удаления при прерывании (только для первичной установки)
    if [ "$is_fresh_install" = true ]; then
        trap 'echo; echo -e "${RED}Установка прервана пользователем${NC}"; echo; rm -rf "${DIR_PANEL}" "${DIR_REMNAWAVE}" 2>/dev/null; exit 1' INT TERM
    fi

    prompt_domain_with_retry "Домен панели (например panel.example.com):" PANEL_DOMAIN || return
    prompt_domain_with_retry "Домен подписки (например sub.example.com):" SUB_DOMAIN true || return
    prompt_domain_with_retry "SelfSteal домен для ноды (например node.example.com):" SELFSTEAL_DOMAIN false true || return

    # Автогенерация учётных данных администратора
    local SUPERADMIN_USERNAME
    local SUPERADMIN_PASSWORD
    SUPERADMIN_USERNAME=$(generate_admin_username)
    SUPERADMIN_PASSWORD=$(generate_admin_password)

    declare -A domains_to_check
    domains_to_check["$PANEL_DOMAIN"]=1
    domains_to_check["$SUB_DOMAIN"]=1

    if check_if_certificates_needed domains_to_check; then
        echo
        show_arrow_menu "🔐 МЕТОД ПОЛУЧЕНИЯ СЕРТИФИКАТОВ" \
            "☁️   Cloudflare DNS-01 (wildcard)" \
            "🌐  ACME HTTP-01 (Let's Encrypt)" \
            "──────────────────────────────────────" \
            "❌  Назад"
        local cert_choice=$?

        case $cert_choice in
            0) CERT_METHOD=1 ;;
            1) CERT_METHOD=2 ;;
            2) continue ;;
            3) return ;;
        esac

        reading "Email для Let's Encrypt:" LETSENCRYPT_EMAIL
        echo

        if [ "$CERT_METHOD" -eq 1 ]; then
            setup_cloudflare_credentials || return
        fi

        handle_certificates domains_to_check "$CERT_METHOD" "$LETSENCRYPT_EMAIL"
    else
        CERT_METHOD=$(detect_cert_method "$PANEL_DOMAIN")
        echo
        for domain in "${!domains_to_check[@]}"; do
            print_success "Сертификат для $domain уже существует"
        done
        echo
    fi

    local PANEL_CERT_DOMAIN SUB_CERT_DOMAIN
    if [ "$CERT_METHOD" -eq 1 ]; then
        PANEL_CERT_DOMAIN=$(extract_domain "$PANEL_DOMAIN")
        SUB_CERT_DOMAIN=$(extract_domain "$SUB_DOMAIN")
    else
        PANEL_CERT_DOMAIN="$PANEL_DOMAIN"
        SUB_CERT_DOMAIN="$SUB_DOMAIN"
    fi

    # Генерируем cookie для защиты панели
    local COOKIE_NAME COOKIE_VALUE
    COOKIE_NAME=$(generate_cookie_key)
    COOKIE_VALUE=$(generate_cookie_key)

    (generate_env_file "$PANEL_DOMAIN" "$SUB_DOMAIN") &
    show_spinner "Создание .env файла"

    (generate_docker_compose_panel "$PANEL_CERT_DOMAIN" "$SUB_CERT_DOMAIN") &
    show_spinner "Создание docker-compose.yml"

    (generate_nginx_conf_panel "$PANEL_DOMAIN" "$SUB_DOMAIN" "$PANEL_CERT_DOMAIN" "$SUB_CERT_DOMAIN" \
        "$COOKIE_NAME" "$COOKIE_VALUE") &
    show_spinner "Создание nginx.conf"

    (setup_firewall) &
    show_spinner "Настройка файрвола"

    echo
    (
        cd /opt/remnawave
        docker compose up -d >/dev/null 2>&1
    ) &
    show_spinner "Запуск Docker контейнеров"

    show_spinner_timer 20 "Ожидание запуска Remnawave" "Запуск Remnawave"

    local domain_url="127.0.0.1:3000"
    local target_dir="${DIR_PANEL}"

    show_spinner_until_ready "http://$domain_url/api/auth/status" "Проверка доступности API" 120
    if [ $? -ne 0 ]; then
        print_error "API не отвечает"
        return
    fi

    # ═══════════════════════════════════════════
    # АВТОНАСТРОЙКА: РЕГИСТРАЦИЯ И СОЗДАНИЕ API
    # ═══════════════════════════════════════════
    echo
    print_action "Автонастройка панели..."

    # 1. Регистрация суперадмина → получение токена
    print_action "Регистрация администратора..."
    local token
    token=$(register_remnawave "$domain_url" "$SUPERADMIN_USERNAME" "$SUPERADMIN_PASSWORD")

    if [ -z "$token" ]; then
        print_error "Не удалось получить токен авторизации"
        print_error "Создайте API токен вручную через панель: https://$PANEL_DOMAIN"
        clear
        echo
        echo -e "${BLUE}══════════════════════════════════════${NC}"
        echo -e "   ${GREEN}⚠️  УСТАНОВКА ЧАСТИЧНО ЗАВЕРШЕНА${NC}"
        echo -e "${BLUE}══════════════════════════════════════${NC}"
        echo
        echo -e "${YELLOW}🔗 ССЫЛКА ВХОДА В ПАНЕЛЬ:${NC}"
        echo -e "${WHITE}https://${PANEL_DOMAIN}/auth/login?${COOKIE_NAME}=${COOKIE_VALUE}${NC}"
        echo
        echo -e "${YELLOW}👤 ЛОГИН:${NC}    ${WHITE}$SUPERADMIN_USERNAME${NC}"
        echo -e "${YELLOW}🔑 ПАРОЛЬ:${NC}   ${WHITE}$SUPERADMIN_PASSWORD${NC}"
        echo
        echo -e "${RED}⚠️  API токен не создан автоматически. Создайте вручную.${NC}"
        echo
        echo -e "${RED}⚠️  ОБЯЗАТЕЛЬНО СКОПИРУЙТЕ И СОХРАНИТЕ ЭТИ ДАННЫЕ!${NC}"
        echo
        read -s -n 1 -p "$(echo -e "${DARKGRAY}Нажмите любую клавишу для продолжения...${NC}")"
        echo
        return
    fi

    # 2. Генерация ключей REALITY и создание xray профиля
    print_action "Генерация REALITY ключей..."
    local private_key
    private_key=$(generate_xray_keys "$domain_url" "$token")

    if [ -n "$private_key" ]; then
        print_action "Удаление дефолтного конфиг-профиля..."
        delete_config_profile "$domain_url" "$token"

        print_action "Создание конфиг-профиля (StealConfig)..."
        local config_result config_profile_uuid inbound_uuid
        config_result=$(create_config_profile "$domain_url" "$token" "StealConfig" "$SELFSTEAL_DOMAIN" "$private_key")
        read config_profile_uuid inbound_uuid <<< "$config_result"

        if [ -n "$config_profile_uuid" ] && [ -n "$inbound_uuid" ]; then
            print_action "Создание ноды ($SELFSTEAL_DOMAIN)..."
            create_node "$domain_url" "$token" "$config_profile_uuid" "$inbound_uuid" "$SELFSTEAL_DOMAIN"

            print_action "Создание хоста ($SELFSTEAL_DOMAIN)..."
            create_host "$domain_url" "$token" "$config_profile_uuid" "$inbound_uuid" "StealConfig" "$SELFSTEAL_DOMAIN"

            print_action "Настройка сквадов..."
            local squad_uuids
            squad_uuids=$(get_default_squad "$domain_url" "$token")
            if [ -n "$squad_uuids" ]; then
                while IFS= read -r squad_uuid; do
                    [ -z "$squad_uuid" ] && continue
                    update_squad "$domain_url" "$token" "$squad_uuid" "$inbound_uuid"
                done <<< "$squad_uuids"
                print_success "Сквады обновлены"
            fi
        fi
    fi

    # 3. Создание API токена для subscription-page
    print_action "Создание API токена для страницы подписки..."
    create_api_token "$domain_url" "$token" "$target_dir"

    # 4. Перезапуск Docker Compose (с обновлённым docker-compose.yml)
    print_action "Перезапуск сервисов с обновлённой конфигурацией..."
    (
        cd /opt/remnawave
        docker compose down >/dev/null 2>&1
        docker compose up -d >/dev/null 2>&1
    ) &
    show_spinner "Запуск контейнеров"

    # Ожидаем готовность после перезапуска
    show_spinner_timer 10 "Ожидание запуска сервисов" "Запуск сервисов"

    # 4. Сброс суперадмина — при первом входе пользователь задаст свои данные
    print_action "Сброс суперадмина для первого входа..."
    docker exec -i remnawave-db psql -U postgres -d postgres -c "DELETE FROM admin;" >/dev/null 2>&1
    if [ $? -eq 0 ]; then
        print_success "Суперадмин сброшен"
    else
        print_error "Не удалось сбросить суперадмина"
    fi

    # Удаляем trap при успешном завершении
    if [ "$is_fresh_install" = true ]; then
        trap - INT TERM
    fi

    clear
    tput civis 2>/dev/null
    echo
    echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}"
    echo -e "                   ${GREEN}🎉 ПАНЕЛЬ УСТАНОВЛЕНА!${NC}"
    echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}"
    echo
    echo -e "${YELLOW}🔗 Ссылка для первого входа в панель:${NC}"
    echo -e "${WHITE}https://${PANEL_DOMAIN}/auth/login?${COOKIE_NAME}=${COOKIE_VALUE}${NC}"
    echo
    echo -e "${YELLOW}📋 Команды запуска меню управления:${NC}"
    echo -e "${GREEN}dfc-remna-install${NC} или ${GREEN}dfc-ri${NC}"
    echo
    echo -e "${DARKGRAY}───────────────────────────────────────────────────────────${NC}"
    echo
    echo -e "${YELLOW}⚠️  При первом входе в панель произойдет создание администратора.${NC}"
    echo -e "${YELLOW}   Сбросить данные администратора и куки для входа можно в любое${NC}"
    echo -e "${YELLOW}   время через главное меню скрипта.${NC}"
    echo
    echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}"
    echo
    read -s -n 1 -p "$(echo -e "${DARKGRAY}Нажмите любую клавишу для продолжения...${NC}")"
        echo
}

# ═══════════════════════════════════════════════
# УСТАНОВКА: ТОЛЬКО НОДА
# ═══════════════════════════════════════════════
installation_node() {
    # Гарантируем валидную рабочую директорию перед началом
    cd /opt 2>/dev/null || cd / 2>/dev/null

    # Проверяем, не установлена ли уже нода
    if [ -f "/opt/remnawave/docker-compose.yml" ] && grep -q "remnanode" /opt/remnawave/docker-compose.yml; then
        clear
        echo
        echo -e "${BLUE}══════════════════════════════════════${NC}"
        echo -e "   ${YELLOW}⚠️  НОДА УЖЕ УСТАНОВЛЕНА${NC}"
        echo -e "${BLUE}══════════════════════════════════════${NC}"
        echo
        echo -e "${WHITE}На этом сервере уже установлена нода.${NC}"
        echo -e "${WHITE}Используйте опцию ${GREEN}"🔄 Переустановить"${WHITE} в главном меню.${NC}"
        echo
        read -s -n 1 -p "$(echo -e "${DARKGRAY}Нажмите любую клавишу для продолжения...${NC}")"
        echo
        return
    fi

    # ─── Определяем режим: локальная панель или удалённая ───
    local is_local_panel=false
    if [ -f "/opt/remnawave/docker-compose.yml" ] && [ -f "/opt/remnawave/nginx.conf" ] && \
       grep -q "remnawave:" /opt/remnawave/docker-compose.yml 2>/dev/null && \
       ! grep -q "remnanode" /opt/remnawave/docker-compose.yml 2>/dev/null; then
        is_local_panel=true
    fi

    if [ "$is_local_panel" = true ]; then
        installation_node_local
    else
        installation_node_remote
    fi
}

# ─── Установка ноды на сервер с панелью (автодетект) ───
installation_node_local() {
    clear
    echo -e "${BLUE}══════════════════════════════════════${NC}"
    echo -e "${GREEN}   🌐 ДОБАВЛЕНИЕ НОДЫ НА СЕРВЕР ПАНЕЛИ${NC}"
    echo -e "${BLUE}══════════════════════════════════════${NC}"

    # Проверяем пакеты
    if [ ! -f "${DIR_REMNAWAVE}install_packages" ] || ! command -v docker >/dev/null 2>&1; then
        install_packages
    fi

    local domain_url="127.0.0.1:3000"
    local target_dir="${DIR_PANEL}"

    # ─── Сохраняем бэкап конфигов для восстановления при отмене ───
    local backup_compose="" backup_nginx=""
    backup_compose=$(cat /opt/remnawave/docker-compose.yml 2>/dev/null)
    backup_nginx=$(cat /opt/remnawave/nginx.conf 2>/dev/null)

    # Функция восстановления при отмене (до изменения конфигов)
    _restore_panel_config() {
        if [ -n "$backup_compose" ]; then
            echo "$backup_compose" > /opt/remnawave/docker-compose.yml
        fi
        if [ -n "$backup_nginx" ]; then
            echo "$backup_nginx" > /opt/remnawave/nginx.conf
        fi
        # Перезапускаем панель с оригинальными конфигами
        (
            cd /opt/remnawave
            docker compose down >/dev/null 2>&1
            docker compose up -d >/dev/null 2>&1
        ) &
        show_spinner "Восстановление конфигурации панели"
        show_spinner_timer 10 "Ожидание запуска сервисов" "Запуск сервисов"
    }

    # ─── Автоопределение конфигурации из существующей панели ───
    echo
    print_action "Определение конфигурации панели..."

    # Извлекаем домены из nginx.conf
    local panel_domain sub_domain
    panel_domain=$(grep -oP 'server_name\s+\K[^;]+' /opt/remnawave/nginx.conf | sed -n '1p')
    sub_domain=$(grep -oP 'server_name\s+\K[^;]+' /opt/remnawave/nginx.conf | sed -n '2p')

    if [ -z "$panel_domain" ] || [ -z "$sub_domain" ]; then
        print_error "Не удалось определить домены из nginx.conf"
        echo
        read -s -n 1 -p "$(echo -e "${DARKGRAY}Нажмите любую клавишу для продолжения...${NC}")"
        echo
        return
    fi

    # Извлекаем cookie
    local COOKIE_NAME COOKIE_VALUE
    get_cookie_from_nginx
    if [ $? -ne 0 ]; then
        print_error "Не удалось извлечь cookie из nginx.conf"
        echo
        read -s -n 1 -p "$(echo -e "${DARKGRAY}Нажмите любую клавишу для продолжения...${NC}")"
        echo
        return
    fi

    # Извлекаем API токен
    local existing_api_token
    existing_api_token=$(grep -oP '^REMNAWAVE_API_TOKEN=\K\S+' /opt/remnawave/.env 2>/dev/null | head -1)

    # Определяем домены сертификатов
    local panel_cert_domain sub_cert_domain
    panel_cert_domain=$(grep -A5 "server_name ${panel_domain};" /opt/remnawave/nginx.conf | grep -oP '/ssl/\K[^/]+' | head -1)
    sub_cert_domain=$(grep -A5 "server_name ${sub_domain};" /opt/remnawave/nginx.conf | grep -oP '/ssl/\K[^/]+' | head -1)
    if [ -z "$panel_cert_domain" ]; then
        panel_cert_domain=$(grep -A5 "server_name ${panel_domain};" /opt/remnawave/nginx.conf | grep -oP 'live/\K[^/]+' | head -1)
    fi
    if [ -z "$sub_cert_domain" ]; then
        sub_cert_domain=$(grep -A5 "server_name ${sub_domain};" /opt/remnawave/nginx.conf | grep -oP 'live/\K[^/]+' | head -1)
    fi
    [ -z "$panel_cert_domain" ] && panel_cert_domain="$panel_domain"
    [ -z "$sub_cert_domain" ] && sub_cert_domain="$sub_domain"

    # Автоопределяем метод сертификации
    local AUTO_CERT_METHOD
    AUTO_CERT_METHOD=$(detect_cert_method "$panel_domain")

    print_success "Панель: $panel_domain"
    print_success "Подписка: $sub_domain"
    print_success "Метод сертификатов: $([ "$AUTO_CERT_METHOD" = "1" ] && echo "Cloudflare DNS-01" || echo "ACME HTTP-01")"
    echo -e "${BLUE}──────────────────────────────────────${NC}"
    # ─── Запрашиваем selfsteal домен ───

    local SELFSTEAL_DOMAIN
    prompt_domain_with_retry "Домен selfsteal ноды (например node.example.com):" SELFSTEAL_DOMAIN true || return

    # ─── Запрашиваем имя ноды ───
    local entity_name
    while true; do
        reading_inline "Введите имя для ноды (например, Germany):" entity_name
        if [[ "$entity_name" =~ ^[a-zA-Z0-9-]+$ ]]; then
            if [ ${#entity_name} -ge 3 ] && [ ${#entity_name} -le 20 ]; then
                break
            else
                print_error "Имя должно содержать от 3 до 20 символов"
            fi
        else
            print_error "Имя должно содержать только английские буквы, цифры и дефис"
        fi
    done

    # ─── Авторизация в панели (до изменения конфигов) ───
    get_panel_token
    if [ $? -ne 0 ]; then
        echo -e "${YELLOW}Установка отменена${NC}"
        echo
        read -s -n 1 -p "$(echo -e "${DARKGRAY}Нажмите любую клавишу для продолжения...${NC}")"
        echo
        return
    fi
    local token
    token=$(cat "${DIR_REMNAWAVE}/token")

    # ─── Проверка уникальности домена/имени в API (до изменения конфигов) ───
    check_node_domain "$domain_url" "$token" "$SELFSTEAL_DOMAIN"
    if [ $? -ne 0 ]; then
        print_error "Домен $SELFSTEAL_DOMAIN уже используется в панели"
        echo
        read -s -n 1 -p "$(echo -e "${DARKGRAY}Нажмите любую клавишу для продолжения...${NC}")"
        echo
        return
    fi

    local response
    response=$(make_api_request "GET" "$domain_url/api/config-profiles" "$token")
    if echo "$response" | jq -e ".response.configProfiles[] | select(.name == \"$entity_name\")" >/dev/null 2>&1; then
        print_error "Имя конфигурационного профиля '$entity_name' уже используется"
        echo
        read -s -n 1 -p "$(echo -e "${DARKGRAY}Нажмите любую клавишу для продолжения...${NC}")"
        echo
        return
    fi

    # ─── Получаем сертификат для selfsteal домена ───
    local CERT_METHOD="$AUTO_CERT_METHOD"
    local LETSENCRYPT_EMAIL=""

    declare -A domains_to_check
    domains_to_check["$SELFSTEAL_DOMAIN"]=1

    if check_if_certificates_needed domains_to_check; then
        echo

        if [ "$CERT_METHOD" = "1" ]; then
            if [ ! -f "/etc/letsencrypt/cloudflare.ini" ]; then
                show_arrow_menu "🔐 МЕТОД ПОЛУЧЕНИЯ СЕРТИФИКАТА ДЛЯ НОДЫ" \
                    "☁️   Cloudflare DNS-01 (wildcard)" \
                    "🌐  ACME HTTP-01 (Let's Encrypt)" \
                    "──────────────────────────────────────" \
                    "❌  Назад"
                local cert_choice=$?
                case $cert_choice in
                    0) CERT_METHOD=1 ;;
                    1) CERT_METHOD=2 ;;
                    *) return ;;
                esac
                setup_cloudflare_credentials || return
            fi
        fi

        LETSENCRYPT_EMAIL=$(grep -r "email" /etc/letsencrypt/accounts/ 2>/dev/null | grep -oP '"[^@]+@[^"]+' | head -1 | tr -d '"')
        if [ -z "$LETSENCRYPT_EMAIL" ]; then
            reading "Email для Let's Encrypt:" LETSENCRYPT_EMAIL
        else
            echo -e "${GREEN}✅${NC} Email для сертификата: $LETSENCRYPT_EMAIL"
        fi
        echo

        handle_certificates domains_to_check "$CERT_METHOD" "$LETSENCRYPT_EMAIL"
    else
        echo -e "${BLUE}──────────────────────────────────────${NC}"
        print_success "Сертификат для $SELFSTEAL_DOMAIN уже существует"
        echo
    fi

    local NODE_CERT_DOMAIN
    if [ "$CERT_METHOD" = "1" ]; then
        NODE_CERT_DOMAIN=$(extract_domain "$SELFSTEAL_DOMAIN")
    else
        NODE_CERT_DOMAIN="$SELFSTEAL_DOMAIN"
    fi

    # ─── Остановка сервисов и обновление конфигов ───
    echo
    print_action "Обновление конфигурации..."

    (
        cd /opt/remnawave
        docker compose down >/dev/null 2>&1
    ) &
    show_spinner "Остановка сервисов"

    mkdir -p /var/www/html

    # ─── Перегенерация docker-compose.yml (full: с нодой) ───
    (generate_docker_compose_full "$panel_cert_domain" "$sub_cert_domain" "$NODE_CERT_DOMAIN") &
    show_spinner "Обновление docker-compose.yml"

    # Восстанавливаем API токен
    if [ -n "$existing_api_token" ]; then
        sed -i "s|^REMNAWAVE_API_TOKEN=.*|REMNAWAVE_API_TOKEN=$existing_api_token|" /opt/remnawave/.env
    fi

    # ─── Перегенерация nginx.conf (full: с selfsteal) ───
    (generate_nginx_conf_full "$panel_domain" "$sub_domain" "$SELFSTEAL_DOMAIN" \
        "$panel_cert_domain" "$sub_cert_domain" "$NODE_CERT_DOMAIN" \
        "$COOKIE_NAME" "$COOKIE_VALUE") &
    show_spinner "Обновление nginx.conf"

    # ─── UFW для ноды ───
    (
        remnawave_network_subnet=172.30.0.0/16
        ufw allow from "$remnawave_network_subnet" to any port 2222 proto tcp >/dev/null 2>&1
    ) &
    show_spinner "Настройка файрвола"

    # ─── Запуск сервисов ───
    echo
    print_action "Запуск сервисов..."

    (
        cd /opt/remnawave
        docker compose up -d >/dev/null 2>&1
    ) &
    show_spinner "Запуск Docker контейнеров"

    show_spinner_timer 20 "Ожидание запуска Remnawave" "Запуск Remnawave"

    show_spinner_until_ready "http://$domain_url/api/auth/status" "Проверка доступности API" 120
    if [ $? -ne 0 ]; then
        print_error "API не отвечает. Восстановление конфигурации..."
        _restore_panel_config
        echo
        read -s -n 1 -p "$(echo -e "${DARKGRAY}Нажмите любую клавишу для продолжения...${NC}")"
        echo
        return
    fi

    # ─── Публичный ключ → SECRET_KEY ───
    print_action "Получение публичного ключа панели..."
    get_public_key "$domain_url" "$token" "$target_dir"

    # Проверяем, что SECRET_KEY реально обновлён (не остался плейсхолдером)
    if grep -q 'PUBLIC KEY FROM REMNAWAVE-PANEL' "$target_dir/docker-compose.yml" 2>/dev/null; then
        print_error "Не удалось установить публичный ключ. Восстановление конфигурации..."
        _restore_panel_config
        echo
        read -s -n 1 -p "$(echo -e "${DARKGRAY}Нажмите любую клавишу для продолжения...${NC}")"
        echo
        return
    fi
    print_success "Установка публичного ключа"

    # ─── API: регистрация ноды ───
    echo
    print_action "Генерация REALITY ключей..."
    local private_key
    private_key=$(generate_xray_keys "$domain_url" "$token")
    if [ -z "$private_key" ]; then
        print_error "Не удалось сгенерировать ключи. Восстановление конфигурации..."
        _restore_panel_config
        echo
        read -s -n 1 -p "$(echo -e "${DARKGRAY}Нажмите любую клавишу для продолжения...${NC}")"
        echo
        return
    fi
    print_success "Ключи сгенерированы"

    print_action "Создание конфиг-профиля ($entity_name)..."
    local config_result config_profile_uuid inbound_uuid
    config_result=$(create_config_profile "$domain_url" "$token" "$entity_name" "$SELFSTEAL_DOMAIN" "$private_key" "$entity_name")
    if [ $? -ne 0 ]; then
        print_error "Не удалось создать конфигурационный профиль. Восстановление конфигурации..."
        _restore_panel_config
        echo
        read -s -n 1 -p "$(echo -e "${DARKGRAY}Нажмите любую клавишу для продолжения...${NC}")"
        echo
        return
    fi
    read config_profile_uuid inbound_uuid <<< "$config_result"
    print_success "Конфигурационный профиль: $entity_name"

    print_action "Создание ноды ($entity_name)..."
    create_node "$domain_url" "$token" "$config_profile_uuid" "$inbound_uuid" "172.30.0.1" "$entity_name"
    if [ $? -eq 0 ]; then
        print_success "Нода создана"
    else
        print_error "Не удалось создать ноду. Восстановление конфигурации..."
        _restore_panel_config
        echo
        read -s -n 1 -p "$(echo -e "${DARKGRAY}Нажмите любую клавишу для продолжения...${NC}")"
        echo
        return
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

    # ─── Финальный перезапуск (с обновлённым SECRET_KEY) ───
    print_action "Перезапуск сервисов..."
    (
        cd /opt/remnawave
        docker compose down >/dev/null 2>&1
        docker compose up -d >/dev/null 2>&1
    ) &
    show_spinner "Запуск контейнеров"

    randomhtml

    # Ожидаем готовность панели после перезапуска
    show_spinner_timer 15 "Ожидание запуска сервисов" "Запуск сервисов"

    show_spinner_until_ready "http://$domain_url/api/auth/status" "Проверка доступности панели" 120
    if [ $? -ne 0 ]; then
        print_error "Панель не отвечает после перезапуска. Восстановление..."
        _restore_panel_config
        echo
        read -s -n 1 -p "$(echo -e "${DARKGRAY}Нажмите любую клавишу для продолжения...${NC}")"
        echo
        return
    fi

    # ─── API: создание токена для subscription-page (если не было) ───
    if [ -z "$existing_api_token" ] || [ "$existing_api_token" = "\$api_token" ]; then
        print_action "Создание API токена для подписок..."
        create_api_token "$domain_url" "$token" "/opt/remnawave"
        if [ $? -eq 0 ]; then
            print_success "API токен создан"
            # Перезапускаем subscription-page с новым токеном
            (cd /opt/remnawave && docker compose up -d remnawave-subscription-page >/dev/null 2>&1) &
            show_spinner "Перезапуск subscription-page"
        else
            print_error "Не удалось создать API токен"
            echo -e "${YELLOW}⚠️  Subscription-page может не работать. Создайте токен вручную:${NC}"
            echo -e "   ${WHITE}Remnawave Dashboard → Settings → API Tokens${NC}"
        fi
    fi

    # ─── Верификация: ждём пока remnanode запустит xray на порту 443 ───
    print_action "Ожидание подключения ноды (xray → порт 443)..."
    local verify_ok=false
    local verify_elapsed=0
    local verify_timeout=60
    while [ $verify_elapsed -lt $verify_timeout ]; do
        if ss -tuln 2>/dev/null | grep -q ':443 '; then
            verify_ok=true
            break
        fi
        sleep 2
        ((verify_elapsed+=2))
    done

    if [ "$verify_ok" = true ]; then
        print_success "Порт 443 активен — xray (remnanode) работает"
    else
        echo -e "${YELLOW}⚠️  Порт 443 не активен через ${verify_timeout} сек. Диагностика:${NC}"
        echo

        # Проверяем контейнер remnanode
        if docker ps --format '{{.Names}}' 2>/dev/null | grep -q '^remnanode$'; then
            echo -e "${GREEN}  ✓${NC} Контейнер remnanode запущен"
            echo -e "${DARKGRAY}  Логи remnanode (последние 10 строк):${NC}"
            docker logs --tail 10 remnanode 2>&1 | while IFS= read -r line; do
                echo -e "${DARKGRAY}    $line${NC}"
            done
        else
            echo -e "${RED}  ✗${NC} Контейнер remnanode НЕ запущен"
        fi

        echo
        echo -e "${YELLOW}  Возможные причины:${NC}"
        echo -e "${WHITE}  1. Нода ещё подключается к панели (подождите 1-2 мин)${NC}"
        echo -e "${WHITE}  2. Панель не смогла передать конфиг ноде${NC}"
        echo -e "${WHITE}  3. Проверьте: ${GREEN}docker logs remnanode${NC}"
        echo -e "${WHITE}  4. Проверьте: ${GREEN}docker logs remnawave${NC}"
        echo
        echo -e "${YELLOW}  Конфигурация НЕ откачена — нода создана в панели.${NC}"
        echo -e "${YELLOW}  Попробуйте: ${GREEN}cd /opt/remnawave && docker compose restart${NC}"
        echo
    fi

    # Автоматически включаем доступ по 8443 (нода занимает 443)
    local local_cookie_name="$COOKIE_NAME"
    local local_cookie_value="$COOKIE_VALUE"
    if [ -z "$local_cookie_name" ] || [ -z "$local_cookie_value" ]; then
        get_cookie_from_nginx
        local_cookie_name="$COOKIE_NAME"
        local_cookie_value="$COOKIE_VALUE"
    fi
    auto_enable_panel_access_8443 "$panel_domain" "$local_cookie_name" "$local_cookie_value"

    # ─── Итог ───
    clear
    echo
    echo -e "${BLUE}══════════════════════════════════════${NC}"
    echo -e "    ${GREEN}🎉 Нода добавлена на сервер панели${NC}"
    echo -e "${BLUE}══════════════════════════════════════${NC}"
    echo
    echo -e "${WHITE}Панель:${NC}       https://$panel_domain:8443"
    echo -e "${WHITE}Подписка:${NC}     https://$sub_domain"
    echo -e "${WHITE}SelfSteal:${NC}    https://$SELFSTEAL_DOMAIN"
    echo
    echo -e "${BLUE}──────────────────────────────────────${NC}"
    echo
    echo -e "${GREEN}✅ Нода зарегистрирована в панели${NC}"
    echo -e "${GREEN}✅ Docker Compose обновлён (nginx + remnanode)${NC}"
    echo -e "${GREEN}✅ Nginx перенастроен (unix socket + proxy_protocol)${NC}"
    echo -e "${GREEN}✅ Доступ к панели по порту 8443 автоматически включён${NC}"
    if [ "$verify_ok" = true ]; then
        echo -e "${GREEN}✅ Порт 443 активен — xray (remnanode) работает${NC}"
    else
        echo -e "${YELLOW}⚠️  Порт 443 пока не активен — проверьте логи ноды${NC}"
    fi
    echo
    echo -e "${DARKGRAY}Архитектура: Xray (порт 443) → unix socket → Nginx → панель${NC}"
    echo -e "${DARKGRAY}Панель доступна по порту 8443 (XRAY занимает 443)${NC}"
    echo
    echo -e "${BLUE}══════════════════════════════════════${NC}"
    read -s -n 1 -p "$(echo -e "${DARKGRAY}Нажмите любую клавишу для продолжения...${NC}")"
    echo
}

# ─── Установка ноды на отдельный сервер (удалённая панель) ───
installation_node_remote() {
    # Узнаём куда устанавливать: /opt/remnanode (отдельная нода)
    local NODE_INSTALL_DIR="/opt/remnanode"

    # Проверяем, это первичная установка?
    local is_fresh_install=false
    if [ ! -d "${NODE_INSTALL_DIR}" ] || [ -z "$(ls -A "${NODE_INSTALL_DIR}" 2>/dev/null)" ]; then
        is_fresh_install=true
    fi

    clear
    echo -e "${BLUE}══════════════════════════════════════${NC}"
    echo -e "${GREEN}   📦 УСТАНОВКА ТОЛЬКО НОДЫ${NC}"
    echo -e "${BLUE}══════════════════════════════════════${NC}"

    mkdir -p "${NODE_INSTALL_DIR}" && cd "${NODE_INSTALL_DIR}"

    # Устанавливаем trap для удаления при прерывании (только для первичной установки)
    if [ "$is_fresh_install" = true ]; then
        trap 'echo; echo -e "${RED}Установка прервана пользователем${NC}"; echo; rm -rf "'"${NODE_INSTALL_DIR}"'" "${DIR_REMNAWAVE}" 2>/dev/null; exit 1' INT TERM
    fi

    prompt_domain_with_retry "Домен selfsteal/ноды (например node.example.com):" SELFSTEAL_DOMAIN || { [ "$is_fresh_install" = true ] && rm -rf "${NODE_INSTALL_DIR}" "${DIR_REMNAWAVE}" 2>/dev/null; return; }

    local PANEL_IP
    while true; do
        reading_inline "IP адрес сервера панели:" PANEL_IP
        if echo "$PANEL_IP" | grep -E '^([0-9]{1,3}\.){3}[0-9]{1,3}$' >/dev/null; then
            break
        fi
        print_error "Некорректный IP адрес"
    done

    echo
    echo -e "${BLUE}➜${NC}  ${YELLOW}Вставьте сертификат (SECRET_KEY) из панели и нажмите Enter дважды:${NC}"
    local CERTIFICATE=""
    while IFS= read -r line; do
        if [ -z "$line" ] && [ -n "$CERTIFICATE" ]; then
            break
        fi
        CERTIFICATE="$CERTIFICATE$line\n"
    done

    declare -A domains_to_check
    domains_to_check["$SELFSTEAL_DOMAIN"]=1

    if check_if_certificates_needed domains_to_check; then
        echo
        show_arrow_menu "🔐 МЕТОД ПОЛУЧЕНИЯ СЕРТИФИКАТОВ" \
            "☁️   Cloudflare DNS-01 (wildcard)" \
            "🌐  ACME HTTP-01 (Let's Encrypt)" \
            "──────────────────────────────────────" \
            "❌  Назад"
        local cert_choice=$?

        case $cert_choice in
            0) CERT_METHOD=1 ;;
            1) CERT_METHOD=2 ;;
            2) continue ;;
            3) return ;;
        esac

        reading "Email для Let's Encrypt:" LETSENCRYPT_EMAIL

        if [ "$CERT_METHOD" -eq 1 ]; then
            setup_cloudflare_credentials || return
        fi

        handle_certificates domains_to_check "$CERT_METHOD" "$LETSENCRYPT_EMAIL"
    else
        CERT_METHOD=$(detect_cert_method "$SELFSTEAL_DOMAIN")
        echo
        print_success "Сертификат для $SELFSTEAL_DOMAIN уже существует"
        echo
    fi

    local NODE_CERT_DOMAIN
    if [ "$CERT_METHOD" -eq 1 ]; then
        NODE_CERT_DOMAIN=$(extract_domain "$SELFSTEAL_DOMAIN")
    else
        NODE_CERT_DOMAIN="$SELFSTEAL_DOMAIN"
    fi

    # Docker-compose для ноды
    (
        cat > "${NODE_INSTALL_DIR}/docker-compose.yml" <<EOL
services:
  remnawave-nginx:
    image: nginx:1.28
    container_name: remnawave-nginx
    hostname: remnawave-nginx
    restart: always
    ulimits:
      nofile:
        soft: 1048576
        hard: 1048576
    volumes:
      - ./nginx.conf:/etc/nginx/conf.d/default.conf:ro
      - /etc/letsencrypt/live/$NODE_CERT_DOMAIN/fullchain.pem:/etc/nginx/ssl/$NODE_CERT_DOMAIN/fullchain.pem:ro
      - /etc/letsencrypt/live/$NODE_CERT_DOMAIN/privkey.pem:/etc/nginx/ssl/$NODE_CERT_DOMAIN/privkey.pem:ro
      - /dev/shm:/dev/shm:rw
      - /var/www/html:/var/www/html:ro
    command: sh -c 'rm -f /dev/shm/nginx.sock && exec nginx -g "daemon off;"'
    network_mode: host
    depends_on:
      - remnanode
    logging:
      driver: 'json-file'
      options:
        max-size: '30m'
        max-file: '5'

  remnanode:
    image: remnawave/node:latest
    container_name: remnanode
    hostname: remnanode
    restart: always
    ulimits:
      nofile:
        soft: 1048576
        hard: 1048576
    network_mode: host
    environment:
      - NODE_PORT=2222
      - SECRET_KEY=$(echo -e "$CERTIFICATE")
    volumes:
      - /dev/shm:/dev/shm:rw
    logging:
      driver: 'json-file'
      options:
        max-size: '30m'
        max-file: '5'
EOL
    ) &
    show_spinner "Создание docker-compose.yml"

    (generate_nginx_conf_node "$SELFSTEAL_DOMAIN" "$NODE_CERT_DOMAIN" "$NODE_INSTALL_DIR") &
    show_spinner "Создание nginx.conf"

    (
        ufw allow from "$PANEL_IP" to any port 2222 >/dev/null 2>&1
        ufw reload >/dev/null 2>&1
    ) &
    show_spinner "Настройка файрвола"

    (
        cd "${NODE_INSTALL_DIR}"
        docker compose up -d >/dev/null 2>&1
    ) &
    show_spinner "Запуск Docker контейнеров"

    show_spinner_timer 5 "Ожидание запуска ноды" "Запуск ноды"

    randomhtml

    # Удаляем trap при успешном завершении
    if [ "$is_fresh_install" = true ]; then
        trap - INT TERM
    fi

    echo
    echo -e "${BLUE}══════════════════════════════════════${NC}"
    echo -e "${GREEN}   🎉 НОДА УСТАНОВЛЕНА!${NC}"
    echo -e "${BLUE}══════════════════════════════════════${NC}"
    echo
    echo -e "${WHITE}Директория:${NC}   ${NODE_INSTALL_DIR}"
    echo -e "${WHITE}SelfSteal:${NC}    https://$SELFSTEAL_DOMAIN"
    echo -e "${WHITE}IP панели:${NC}    $PANEL_IP"
    echo
    echo -e "${YELLOW}Проверьте подключение ноды в панели Remnawave${NC}"
    echo
    read -s -n 1 -p "$(echo -e "${DARKGRAY}Нажмите Enter для продолжения${NC}")"
    echo
}

# ═══════════════════════════════════════════════
# УПРАВЛЕНИЕ
# ═══════════════════════════════════════════════
change_credentials() {
    clear
    echo -e "${BLUE}══════════════════════════════════════${NC}"
    echo -e "${GREEN}   🔐 СБРОС СУПЕРАДМИНА${NC}"
    echo -e "${BLUE}══════════════════════════════════════${NC}"
    echo
    echo -e "${YELLOW}⚠️  ВНИМАНИЕ!${NC}"
    echo -e "${WHITE}Эта операция удалит текущего суперадмина из базы данных.${NC}"
    echo -e "${WHITE}При следующем входе в панель вам будет предложено${NC}"
    echo -e "${WHITE}создать нового суперадмина.${NC}"

    if ! confirm_action; then
        print_error "Операция отменена"
        sleep 2
        return
    fi

    echo
    print_action "Сброс суперадмина..."

    # Останавливаем панель
    (
        cd /opt/remnawave
        docker compose stop remnawave >/dev/null 2>&1
    ) &
    show_spinner "Остановка панели"

    # Подключаемся к базе и удаляем всех администраторов
    docker exec -i remnawave-db psql -U postgres -d postgres <<'EOSQL' >/dev/null 2>&1
DELETE FROM admin;
EOSQL

    if [ $? -eq 0 ]; then
        print_success "Суперадмин удалён из базы данных"
    else
        print_error "Не удалось удалить суперадмина"
        # Запускаем панель обратно
        (
            cd /opt/remnawave
            docker compose start remnawave >/dev/null 2>&1
        ) &
        show_spinner "Запуск панели"
        sleep 2
        return
    fi

    # Запускаем панель обратно
    (
        cd /opt/remnawave
        docker compose start remnawave >/dev/null 2>&1
    ) &
    show_spinner "Запуск панели"

    # Ждём готовности
    show_spinner_timer 10 "Ожидание запуска панели" "Запуск панели"

    echo
    echo -e "${GREEN}✅ Сброс выполнен успешно!${NC}"
    echo
    echo -e "${WHITE}При следующем входе в панель вы сможете создать${NC}"
    echo -e "${WHITE}нового суперадмина с любым логином и паролем.${NC}"
    echo
    read -s -n 1 -p "$(echo -e "${DARKGRAY}Нажмите Enter для возврата${NC}")"
        echo
}

regenerate_cookies() {
    clear
    tput civis 2>/dev/null
    echo -e "${BLUE}══════════════════════════════════════${NC}"
    echo -e "${GREEN}   🍪 СМЕНА COOKIE ДОСТУПА${NC}"
    echo -e "${BLUE}══════════════════════════════════════${NC}"
    echo

    if [ ! -f /opt/remnawave/nginx.conf ]; then
        print_error "Файл nginx.conf не найден"
        sleep 2
        tput cnorm 2>/dev/null
        return
    fi

    # Читаем старые cookie из nginx.conf
    local COOKIE_NAME COOKIE_VALUE
    if ! get_cookie_from_nginx; then
        print_error "Не удалось извлечь cookie из nginx.conf"
        sleep 2
        tput cnorm 2>/dev/null
        return
    fi
    local OLD_NAME="$COOKIE_NAME"
    local OLD_VALUE="$COOKIE_VALUE"

    echo -e "${YELLOW}⚠️  Текущие cookie будут заменены на новые.${NC}"
    echo

    if ! confirm_action; then
        print_error "Операция отменена"
        sleep 2
        tput cnorm 2>/dev/null
        return
    fi

    # Генерируем новые cookie
    local NEW_NAME NEW_VALUE
    NEW_NAME=$(generate_cookie_key)
    NEW_VALUE=$(generate_cookie_key)

    echo
    print_action "Обновление cookie..."

    # Заменяем cookie в nginx.conf
    sed -i "s|~\*${OLD_NAME}=${OLD_VALUE}|~*${NEW_NAME}=${NEW_VALUE}|g" /opt/remnawave/nginx.conf
    sed -i "s|\$arg_${OLD_NAME}|\$arg_${NEW_NAME}|g" /opt/remnawave/nginx.conf
    sed -i "s|    \"[^\"]*\" \"${OLD_NAME}=${OLD_VALUE}; Path=|    \"${NEW_VALUE}\" \"${NEW_NAME}=${NEW_VALUE}; Path=|g" /opt/remnawave/nginx.conf
    sed -i "s|\"${OLD_VALUE}\" 1|\"${NEW_VALUE}\" 1|g" /opt/remnawave/nginx.conf

    print_success "Cookie успешно обновлены!"

    # Перезапускаем контейнеры для применения изменений
    (
        cd /opt/remnawave
        docker compose down >/dev/null 2>&1
        docker compose up -d >/dev/null 2>&1
    ) &
    show_spinner "Перезапуск nginx"

    # Показываем новую ссылку
    local panel_domain
    panel_domain=$(grep -oP 'server_name\s+\K[^;]+' /opt/remnawave/nginx.conf | head -1)

    echo
    echo -e "${DARKGRAY}──────────────────────────────────────${NC}"
    echo
    echo -e "${YELLOW}🔐 НОВАЯ ССЫЛКА ДОСТУПА К ПАНЕЛИ:${NC}"
    echo -e "${WHITE}https://${panel_domain}/auth/login?${NEW_NAME}=${NEW_VALUE}${NC}"
    echo
    echo -e "${BLUE}══════════════════════════════════════${NC}"
    read -s -n 1 -p "$(echo -e "${DARKGRAY}Нажмите Enter для возврата${NC}")"
        echo
    tput cnorm 2>/dev/null
}

