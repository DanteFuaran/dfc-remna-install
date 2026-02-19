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
