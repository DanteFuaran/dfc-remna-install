
# ═══════════════════════════════════════════════════
# SWAP
# ═══════════════════════════════════════════════════
manage_swap() {
    clear
    echo -e "${BLUE}══════════════════════════════════════${NC}"
    echo -e "${GREEN}   💾 УПРАВЛЕНИЕ SWAP${NC}"
    echo -e "${BLUE}══════════════════════════════════════${NC}"
    echo

    # Определяем текущий объём RAM
    local ram_kb
    ram_kb=$(grep MemTotal /proc/meminfo | awk '{print $2}')
    local ram_mb=$((ram_kb / 1024))
    local ram_gb=$((ram_mb / 1024))

    # Определяем оптимальный размер SWAP
    local swap_size_gb
    if [ "$ram_mb" -le 2048 ]; then
        swap_size_gb=2
    elif [ "$ram_mb" -le 4096 ]; then
        swap_size_gb=2
    elif [ "$ram_mb" -le 8192 ]; then
        swap_size_gb=4
    else
        swap_size_gb=8
    fi

    echo -e "${DARKGRAY}RAM на сервере: ${WHITE}${ram_mb} MB (~${ram_gb} GB)${NC}"
    echo -e "${DARKGRAY}Рекомендуемый размер SWAP: ${WHITE}${swap_size_gb} GB${NC}"
    echo

    # Проверяем текущий SWAP
    local current_swap
    current_swap=$(swapon --show --noheadings 2>/dev/null)
    if [ -n "$current_swap" ]; then
        local swap_total
        swap_total=$(free -h | awk '/Swap:/ {print $2}')
        print_success "SWAP уже активен (${swap_total})"
        echo
        echo -e "${DARKGRAY}Текущие SWAP-устройства:${NC}"
        swapon --show 2>/dev/null
        echo

        show_arrow_menu "SWAP" \
            "💾  Пересоздать SWAP (${swap_size_gb} GB)" \
            "🗑️   Удалить SWAP" \
            "──────────────────────────────────────" \
            "❌  Назад"
        local choice=$?

        case $choice in
            0)
                # Удаляем текущий swap, потом создаём новый
                echo
                (
                    swapoff -a 2>/dev/null
                    rm -f /swapfile 2>/dev/null
                    sed -i '/\/swapfile/d' /etc/fstab 2>/dev/null
                ) &
                show_spinner "Удаление текущего SWAP"
                ;;
            1)
                # Только удаляем
                echo
                if ! confirm_action; then
                    print_error "Операция отменена"
                    sleep 2
                    return 1
                fi
                echo
                (
                    swapoff -a 2>/dev/null
                    rm -f /swapfile 2>/dev/null
                    sed -i '/\/swapfile/d' /etc/fstab 2>/dev/null
                    sed -i '/vm.swappiness/d' /etc/sysctl.conf 2>/dev/null
                ) &
                show_spinner "Удаление SWAP"
                echo
                print_success "SWAP удалён"
                echo
                echo -e "${BLUE}══════════════════════════════════════${NC}"
                read -s -n 1 -p "$(echo -e "${DARKGRAY}Нажмите любую клавишу для продолжения...${NC}")"
                echo
                return
                ;;
            2) return ;;
            3) return ;;
        esac
    else
        echo -e "${YELLOW}⚠️  SWAP не настроен на сервере${NC}"
        echo

        show_arrow_menu "SWAP" \
            "💾  Создать SWAP (${swap_size_gb} GB)" \
            "──────────────────────────────────────" \
            "❌  Назад"
        local choice=$?

        case $choice in
            0) ;; # продолжаем создание
            1) return ;;
            2) return ;;
        esac
    fi

    clear
    echo -e "${BLUE}══════════════════════════════════════${NC}"
    echo -e "${GREEN}   💾 СОЗДАНИЕ SWAP (${swap_size_gb} GB)${NC}"
    echo -e "${BLUE}══════════════════════════════════════${NC}"
    echo

    # Проверяем свободное место
    local free_space_kb
    free_space_kb=$(df / --output=avail | tail -1)
    local needed_kb=$((swap_size_gb * 1024 * 1024))
    if [ "$free_space_kb" -lt "$needed_kb" ]; then
        print_error "Недостаточно места на диске для создания SWAP"
        echo -e "${DARKGRAY}Свободно: $((free_space_kb / 1024)) MB, требуется: $((needed_kb / 1024)) MB${NC}"
        echo
        read -s -n 1 -p "$(echo -e "${DARKGRAY}Нажмите любую клавишу для продолжения...${NC}")"
        echo
        return 1
    fi

    # Создаём swapfile
    (
        fallocate -l "${swap_size_gb}G" /swapfile 2>/dev/null || dd if=/dev/zero of=/swapfile bs=1M count=$((swap_size_gb * 1024)) status=none 2>/dev/null
        chmod 600 /swapfile
        mkswap /swapfile >/dev/null 2>&1
        swapon /swapfile 2>/dev/null
    ) &
    show_spinner "Создание SWAP-файла (${swap_size_gb} GB)"

    # Добавляем в fstab если нет
    if ! grep -q '/swapfile' /etc/fstab 2>/dev/null; then
        echo '/swapfile none swap sw 0 0' >> /etc/fstab
        print_success "Добавлено в /etc/fstab"
    fi

    # Настройка swappiness
    sysctl vm.swappiness=10 >/dev/null 2>&1
    if ! grep -q 'vm.swappiness' /etc/sysctl.conf 2>/dev/null; then
        echo 'vm.swappiness=10' >> /etc/sysctl.conf
    else
        sed -i 's/vm.swappiness=.*/vm.swappiness=10/' /etc/sysctl.conf
    fi
    print_success "Swappiness установлен на 10"

    # Проверяем результат
    if swapon --show | grep -q '/swapfile'; then
        echo
        print_success "SWAP (${swap_size_gb} GB) успешно создан и активирован"
    else
        echo
        print_error "Не удалось активировать SWAP"
    fi

    echo
    echo -e "${BLUE}══════════════════════════════════════${NC}"
    read -s -n 1 -p "$(echo -e "${DARKGRAY}Нажмите любую клавишу для продолжения...${NC}")"
    echo
}

# ═══════════════════════════════════════════════════
# FAIL2BAN
# ═══════════════════════════════════════════════════
manage_fail2ban() {
    clear
    echo -e "${BLUE}══════════════════════════════════════${NC}"
    echo -e "${GREEN}         🛡️  FAIL 2 BAN${NC}"
    echo -e "${BLUE}══════════════════════════════════════${NC}"
    echo

    local f2b_installed=false
    if command -v fail2ban-client >/dev/null 2>&1; then
        f2b_installed=true
        local f2b_status
        f2b_status=$(systemctl is-active fail2ban 2>/dev/null || echo "inactive")
        if [ "$f2b_status" = "active" ]; then
            print_success "Fail2ban установлен и активен"
        else
            print_warning "Fail2ban установлен, но не запущен (${f2b_status})"
        fi

        # Показываем статистику
        echo
        echo -e "${DARKGRAY}Статус jail'ов:${NC}"
        fail2ban-client status 2>/dev/null | grep "Jail list" | sed 's/.*://;s/,/\n/g' | while read -r jail; do
            jail=$(echo "$jail" | xargs)
            if [ -n "$jail" ]; then
                local banned
                banned=$(fail2ban-client status "$jail" 2>/dev/null | grep "Currently banned" | awk '{print $NF}')
                echo -e "  ${WHITE}${jail}${NC}: ${YELLOW}${banned:-0}${NC} заблокировано"
            fi
        done
        echo

        show_arrow_menu "FAIL2BAN" \
            "⚙️   Настройки" \
            "🔄  Перезапустить Fail2ban" \
            "🗑️   Удалить Fail2ban" \
            "──────────────────────────────────────" \
            "❌  Назад"
        local choice=$?

        case $choice in
            0)
                # Настройки Fail2ban
                clear
                echo -e "${BLUE}══════════════════════════════════════${NC}"
                echo -e "${GREEN}         ⚙️  НАСТРОЙКИ FAIL2BAN${NC}"
                echo -e "${BLUE}══════════════════════════════════════${NC}"
                echo

                # Читаем текущие значения из jail.local
                local cur_maxretry cur_bantime_sec cur_findtime_sec
                cur_maxretry=$(grep -m1 '^maxretry' /etc/fail2ban/jail.local 2>/dev/null | awk '{print $3}')
                cur_bantime_sec=$(grep -m1 '^bantime' /etc/fail2ban/jail.local 2>/dev/null | awk '{print $3}')
                cur_findtime_sec=$(grep -m1 '^findtime' /etc/fail2ban/jail.local 2>/dev/null | awk '{print $3}')
                cur_maxretry=${cur_maxretry:-5}
                local cur_bantime_min=$(( ${cur_bantime_sec:-3600} / 60 ))
                local cur_findtime_min=$(( ${cur_findtime_sec:-600} / 60 ))

                echo -e "${DARKGRAY}Текущие настройки SSH jail:${NC}"
                echo -e "  ${WHITE}Количество:${NC}   ${YELLOW}${cur_maxretry}${NC} попыток"
                echo -e "  ${WHITE}Длит. бана:${NC}   ${YELLOW}${cur_bantime_min}${NC} мин"
                echo -e "  ${WHITE}Окно поиска:${NC}  ${YELLOW}${cur_findtime_min}${NC} мин"
                echo

                local new_maxretry new_bantime_min new_findtime_min
                reading_inline "Количество попыток (сейчас ${cur_maxretry}):" new_maxretry
                if [ -z "$new_maxretry" ] || ! [[ "$new_maxretry" =~ ^[0-9]+$ ]]; then
                    new_maxretry=$cur_maxretry
                fi
                reading_inline "Длительность бана в минутах (сейчас ${cur_bantime_min}):" new_bantime_min
                if [ -z "$new_bantime_min" ] || ! [[ "$new_bantime_min" =~ ^[0-9]+$ ]]; then
                    new_bantime_min=$cur_bantime_min
                fi
                reading_inline "Окно поиска в минутах (сейчас ${cur_findtime_min}):" new_findtime_min
                if [ -z "$new_findtime_min" ] || ! [[ "$new_findtime_min" =~ ^[0-9]+$ ]]; then
                    new_findtime_min=$cur_findtime_min
                fi

                local new_bantime_sec=$(( new_bantime_min * 60 ))
                local new_findtime_sec=$(( new_findtime_min * 60 ))

                (
                    cat > /etc/fail2ban/jail.local <<JAIL_EOF
[DEFAULT]
bantime  = ${new_bantime_sec}
findtime = ${new_findtime_sec}
maxretry = ${new_maxretry}
banaction = iptables-multiport

[sshd]
enabled  = true
port     = ssh
filter   = sshd
logpath  = /var/log/auth.log
maxretry = ${new_maxretry}
JAIL_EOF
                    systemctl restart fail2ban >/dev/null 2>&1
                ) >/dev/null 2>&1 &
                wait
                
                echo
                echo -e "${DARKGRAY}──────────────────────────────────────${NC}"
                echo
                echo -e "${DARKGRAY}Настройки обновлены:${NC}"
                echo -e "  ${WHITE}Количество:${NC}   ${YELLOW}${new_maxretry}${NC} попыток"
                echo -e "  ${WHITE}Длит. бана:${NC}   ${YELLOW}${new_bantime_min}${NC} мин"
                echo -e "  ${WHITE}Окно поиска:${NC}  ${YELLOW}${new_findtime_min}${NC} мин"
                echo
                echo -e "${BLUE}════════════════════════════════${NC}"
                read -p "$(echo -e "${DARKGRAY}Нажмите Enter для продолжения${NC}")"
                return
                ;;
            1)
                echo
                (
                    systemctl restart fail2ban >/dev/null 2>&1
                ) &
                show_spinner "Перезапуск Fail2ban"
                print_success "Fail2ban перезапущен"
                echo
                read -s -n 1 -p "$(echo -e "${DARKGRAY}Нажмите любую клавишу для продолжения...${NC}")"
                echo
                return
                ;;
            2)
                echo
                if ! confirm_action; then
                    print_error "Операция отменена"
                    sleep 2
                    return 1
                fi
                echo
                (
                    systemctl stop fail2ban >/dev/null 2>&1
                    systemctl disable fail2ban >/dev/null 2>&1
                    apt-get remove --purge -y fail2ban >/dev/null 2>&1
                    rm -rf /etc/fail2ban 2>/dev/null
                ) &
                show_spinner "Удаление Fail2ban"
                print_success "Fail2ban удалён"
                echo
                read -s -n 1 -p "$(echo -e "${DARKGRAY}Нажмите любую клавишу для продолжения...${NC}")"
                echo
                return
                ;;
            3) return ;;
            4) return ;;
        esac
    else
        echo -e "${YELLOW}⚠️  Fail2ban не установлен${NC}"
        echo
        echo -e "${DARKGRAY}Fail2ban защищает сервер от брутфорс-атак,${NC}"
        echo -e "${DARKGRAY}блокируя IP-адреса после нескольких неудачных попыток входа.${NC}"
        echo

        show_arrow_menu "FAIL2BAN" \
            "📥  Установить Fail2ban" \
            "──────────────────────────────────────" \
            "❌  Назад"
        local choice=$?

        case $choice in
            0) ;; # продолжаем установку
            1) return ;;
            2) return ;;
        esac

        clear
        echo -e "${BLUE}══════════════════════════════════════${NC}"
        echo -e "${GREEN}   📥 УСТАНОВКА FAIL2BAN${NC}"
        echo -e "${BLUE}══════════════════════════════════════${NC}"
        echo

        # Установка
        (
            apt-get update -qq >/dev/null 2>&1
            apt-get install -y -qq fail2ban >/dev/null 2>&1
        ) &
        show_spinner "Установка Fail2ban"

        if ! command -v fail2ban-client >/dev/null 2>&1; then
            print_error "Не удалось установить Fail2ban"
            echo
            read -s -n 1 -p "$(echo -e "${DARKGRAY}Нажмите любую клавишу для продолжения...${NC}")"
            echo
            return 1
        fi

        # Создаём jail.local для SSH
        cat > /etc/fail2ban/jail.local <<'JAIL_EOF'
[DEFAULT]
bantime  = 3600
findtime = 600
maxretry = 5
banaction = iptables-multiport

[sshd]
enabled  = true
port     = ssh
filter   = sshd
logpath  = /var/log/auth.log
maxretry = 5
JAIL_EOF
        print_success "Конфигурация SSH jail создана"

        # Включаем и запускаем
        (
            systemctl enable fail2ban >/dev/null 2>&1
            systemctl restart fail2ban >/dev/null 2>&1
        ) &
        show_spinner "Запуск Fail2ban"

        if systemctl is-active --quiet fail2ban 2>/dev/null; then
            echo
            print_success "Fail2ban успешно установлен и запущен"
            echo
            echo -e "${DARKGRAY}Настройки SSH jail:${NC}"
            echo -e "  ${WHITE}Количество:${NC}   5 попыток"
            echo -e "  ${WHITE}Длит. бана:${NC}   60 мин"
            echo -e "  ${WHITE}Окно поиска:${NC}  10 мин"
        else
            print_error "Fail2ban установлен, но не удалось запустить"
        fi

        echo
        echo -e "${BLUE}══════════════════════════════════════${NC}"
        read -p "$(echo -e "${DARKGRAY}Нажмите Enter для продолжения${NC}")"
    fi
}

# ═══════════════════════════════════════════════════
# BBR
# ═══════════════════════════════════════════════════
manage_bbr() {
    clear
    echo -e "${BLUE}══════════════════════════════════════${NC}"
    echo -e "${GREEN}            🚀 BBR${NC}"
    echo -e "${BLUE}══════════════════════════════════════${NC}"
    echo

    # Проверяем текущий статус BBR
    local current_cc
    current_cc=$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null)
    local qdisc
    qdisc=$(sysctl -n net.core.default_qdisc 2>/dev/null)

    if [ "$current_cc" = "bbr" ]; then
        print_success "BBR активен"
        echo -e "  ${WHITE}tcp_congestion_control${NC}: ${YELLOW}${current_cc}${NC}"
        echo -e "  ${WHITE}default_qdisc${NC}: ${YELLOW}${qdisc}${NC}"
    else
        print_warning "BBR не активен (текущий: ${current_cc:-unknown})"
    fi
    echo

    show_arrow_menu "BBR" \
        "✅  Включить BBR" \
        "❌  Выключить BBR" \
        "──────────────────────────────────────" \
        "↩️   Назад"
    local choice=$?

    case $choice in
        0)
            echo
            (
                sysctl -w net.core.default_qdisc=fq >/dev/null 2>&1
                sysctl -w net.ipv4.tcp_congestion_control=bbr >/dev/null 2>&1
                # Сохраняем в sysctl.conf
                sed -i '/net.core.default_qdisc/d' /etc/sysctl.conf 2>/dev/null
                sed -i '/net.ipv4.tcp_congestion_control/d' /etc/sysctl.conf 2>/dev/null
                echo 'net.core.default_qdisc=fq' >> /etc/sysctl.conf
                echo 'net.ipv4.tcp_congestion_control=bbr' >> /etc/sysctl.conf
                sysctl -p >/dev/null 2>&1
            ) &
            show_spinner "Включение BBR"

            local new_cc
            new_cc=$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null)
            if [ "$new_cc" = "bbr" ]; then
                print_success "BBR успешно включён"
            else
                print_error "Не удалось включить BBR"
            fi
            echo
            echo -e "${BLUE}══════════════════════════════════════${NC}"
            read -s -n 1 -p "$(echo -e "${DARKGRAY}Нажмите любую клавишу для продолжения...${NC}")"
            echo
            ;;
        1)
            echo
            (
                sysctl -w net.core.default_qdisc=pfifo_fast >/dev/null 2>&1
                sysctl -w net.ipv4.tcp_congestion_control=cubic >/dev/null 2>&1
                sed -i '/net.core.default_qdisc/d' /etc/sysctl.conf 2>/dev/null
                sed -i '/net.ipv4.tcp_congestion_control/d' /etc/sysctl.conf 2>/dev/null
                sysctl -p >/dev/null 2>&1
            ) &
            show_spinner "Выключение BBR"

            local new_cc
            new_cc=$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null)
            if [ "$new_cc" = "cubic" ]; then
                print_success "BBR выключен (переключено на cubic)"
            else
                print_error "Не удалось выключить BBR"
            fi
            echo
            echo -e "${BLUE}══════════════════════════════════════${NC}"
            read -s -n 1 -p "$(echo -e "${DARKGRAY}Нажмите любую клавишу для продолжения...${NC}")"
            echo
            ;;
        2) return ;;
        3) return ;;
    esac
}

# ═══════════════════════════════════════════════════
# FIREWALL (UFW)
# ═══════════════════════════════════════════════════
manage_ufw() {
    while true; do
        clear
        echo -e "${BLUE}══════════════════════════════════════${NC}"
        echo -e "${GREEN}        🔥 FIREWALL (UFW)${NC}"
        echo -e "${BLUE}══════════════════════════════════════${NC}"
        echo

        # Статус UFW
        local ufw_status
        ufw_status=$(ufw status 2>/dev/null | head -1)
        if echo "$ufw_status" | grep -q "active"; then
            print_success "UFW активен"
        else
            print_warning "UFW не активен"
        fi
        echo

        show_arrow_menu "FIREWALL (UFW)" \
            "📋  Показать открытые порты" \
            "➕  Открыть порт" \
            "➖  Удалить правило" \
            "──────────────────────────────────────" \
            "❌  Назад"
        local choice=$?

        case $choice in
            0)
                # Показать открытые порты
                clear
                echo -e "${BLUE}══════════════════════════════════════${NC}"
                echo -e "${GREEN}     📋 ОТКРЫТЫЕ ПОРТЫ (UFW)${NC}"
                echo -e "${BLUE}══════════════════════════════════════${NC}"
                echo
                ufw status numbered 2>/dev/null | tail -n +4
                echo
                echo -e "${BLUE}══════════════════════════════════════${NC}"
                read -s -n 1 -p "$(echo -e "${DARKGRAY}Нажмите любую клавишу для продолжения...${NC}")"
                echo
                ;;
            1)
                # Открыть порт
                clear
                echo -e "${BLUE}══════════════════════════════════════${NC}"
                echo -e "${GREEN}        ➕ ОТКРЫТЬ ПОРТ${NC}"
                echo -e "${BLUE}══════════════════════════════════════${NC}"
                echo

                local ufw_port ufw_proto ufw_comment ufw_ip

                reading_inline "Порт (обязательно):" ufw_port
                if [ -z "$ufw_port" ] || ! [[ "$ufw_port" =~ ^[0-9]+$ ]]; then
                    print_error "Порт не указан или некорректен"
                    echo
                    read -s -n 1 -p "$(echo -e "${DARKGRAY}Нажмите любую клавишу для продолжения...${NC}")"
                    echo
                    continue
                fi

                reading_inline "Протокол (tcp/пусто для any):" ufw_proto
                reading_inline "Комментарий (Enter для пропуска):" ufw_comment
                reading_inline "IP-адрес (Enter для всех):" ufw_ip

                echo

                # Формируем правило
                local ufw_cmd="ufw allow"
                if [ -n "$ufw_ip" ]; then
                    ufw_cmd+=" from $ufw_ip to any"
                fi
                ufw_cmd+=" port $ufw_port"
                if [ -n "$ufw_proto" ]; then
                    ufw_cmd+=" proto $ufw_proto"
                fi
                if [ -n "$ufw_comment" ]; then
                    ufw_cmd+=" comment '$ufw_comment'"
                fi

                (
                    eval "$ufw_cmd" >/dev/null 2>&1
                ) &
                show_spinner "Открытие порта $ufw_port"

                print_success "Порт $ufw_port открыт"
                [ -n "$ufw_proto" ] && echo -e "  ${DARKGRAY}Протокол: ${WHITE}${ufw_proto}${NC}"
                [ -n "$ufw_ip" ] && echo -e "  ${DARKGRAY}Для IP: ${WHITE}${ufw_ip}${NC}"
                [ -n "$ufw_comment" ] && echo -e "  ${DARKGRAY}Комментарий: ${WHITE}${ufw_comment}${NC}"
                echo
                echo -e "${BLUE}══════════════════════════════════════${NC}"
                read -s -n 1 -p "$(echo -e "${DARKGRAY}Нажмите любую клавишу для продолжения...${NC}")"
                echo
                ;;
            2)
                # Удалить правило
                clear
                echo -e "${BLUE}══════════════════════════════════════${NC}"
                echo -e "${GREEN}       ➖ УДАЛИТЬ ПРАВИЛО${NC}"
                echo -e "${BLUE}══════════════════════════════════════${NC}"
                echo

                # Собираем правила в массив
                local rules=()
                while IFS= read -r line; do
                    # Убираем номер в скобках, оставляем описание правила
                    local rule_text
                    rule_text=$(echo "$line" | sed 's/^\[\s*[0-9]*\]\s*//')
                    [ -n "$rule_text" ] && rules+=("$rule_text")
                done < <(ufw status numbered 2>/dev/null | grep '^\[')

                if [ ${#rules[@]} -eq 0 ]; then
                    print_warning "Нет правил для удаления"
                    echo
                    read -s -n 1 -p "$(echo -e "${DARKGRAY}Нажмите любую клавишу для продолжения...${NC}")"
                    echo
                    continue
                fi

                # Добавляем кнопку "Назад"
                local menu_items=()
                for r in "${rules[@]}"; do
                    menu_items+=("$r")
                done
                menu_items+=("──────────────────────────────────────")
                menu_items+=("❌  Назад")

                show_arrow_menu "УДАЛИТЬ ПРАВИЛО" "${menu_items[@]}"
                local del_choice=$?

                # Проверяем что не разделитель и не "Назад"
                local total_rules=${#rules[@]}
                if [ "$del_choice" -ge "$total_rules" ]; then
                    continue
                fi

                local rule_num=$((del_choice + 1))
                echo
                echo -e "${YELLOW}Удалить: ${WHITE}${rules[$del_choice]}${NC}"
                if ! confirm_action; then
                    print_error "Операция отменена"
                    sleep 2
                    continue
                fi

                echo
                (
                    echo "y" | ufw delete "$rule_num" >/dev/null 2>&1
                ) &
                show_spinner "Удаление правила"
                print_success "Правило удалено: ${rules[$del_choice]}"
                echo
                echo -e "${BLUE}══════════════════════════════════════${NC}"
                read -s -n 1 -p "$(echo -e "${DARKGRAY}Нажмите любую клавишу для продолжения...${NC}")"
                echo
                ;;
            3) continue ;;
            4) return ;;
        esac
    done
}

# ═══════════════════════════════════════════════════
# LOGROTATE
# ═══════════════════════════════════════════════════
manage_logrotate() {
    clear
    echo -e "${BLUE}══════════════════════════════════════${NC}"
    echo -e "${GREEN}          📝 LOGROTATE${NC}"
    echo -e "${BLUE}══════════════════════════════════════${NC}"
    echo

    # Docker log settings
    local docker_max_size docker_max_file
    docker_max_size=$(grep -oP '"max-size"\s*:\s*"\K[^"]+' /etc/docker/daemon.json 2>/dev/null)
    docker_max_file=$(grep -oP '"max-file"\s*:\s*"\K[^"]+' /etc/docker/daemon.json 2>/dev/null)
    docker_max_size=${docker_max_size:-не настроено}
    docker_max_file=${docker_max_file:-не настроено}

    # Текущий cron интервал (если настроен)
    local cur_hours="не настроено"
    if [ -f /etc/cron.d/logrotate-custom ]; then
        local cron_h
        cron_h=$(grep -oP '^\*/\K[0-9]+' /etc/cron.d/logrotate-custom 2>/dev/null)
        if [ -n "$cron_h" ]; then
            cur_hours="${cron_h}ч"
        fi
    fi

    echo -e "${DARKGRAY}Системные логи:${NC}"
    echo -e "  ${WHITE}Ротация каждые${NC}: ${YELLOW}${cur_hours}${NC}"
    echo
    echo -e "${DARKGRAY}Docker логи (daemon.json):${NC}"
    echo -e "  ${WHITE}max-size${NC}: ${YELLOW}${docker_max_size}${NC}"
    echo -e "  ${WHITE}max-file${NC}: ${YELLOW}${docker_max_file}${NC}"
    echo

    show_arrow_menu "LOGROTATE" \
        "📝  Настроить ротацию системных логов" \
        "🐳  Настроить ротацию Docker логов" \
        "──────────────────────────────────────" \
        "❌  Назад"
    local choice=$?

    case $choice in
        0)
            # Ротация системных логов
            clear
            echo -e "${BLUE}══════════════════════════════════════${NC}"
            echo -e "${GREEN}     📝 СИСТЕМНЫЕ ЛОГИ${NC}"
            echo -e "${BLUE}══════════════════════════════════════${NC}"
            echo

            echo -e "${DARKGRAY}Как часто делать ротацию логов:${NC}"
            echo

            show_arrow_menu "ЧАСТОТА РОТАЦИИ" \
                "  1 час" \
                "  2 часа" \
                "  3 часа" \
                "  6 часов" \
                " 12 часов" \
                " 24 часа"
            local freq_choice=$?

            local rotate_hours
            case $freq_choice in
                0) rotate_hours=1 ;;
                1) rotate_hours=2 ;;
                2) rotate_hours=3 ;;
                3) rotate_hours=6 ;;
                4) rotate_hours=12 ;;
                5) rotate_hours=24 ;;
                *) return ;;
            esac

            echo
            local keep_count
            reading_inline "Сколько ротаций хранить (по умолчанию 7):" keep_count
            if [ -z "$keep_count" ] || ! [[ "$keep_count" =~ ^[0-9]+$ ]]; then
                keep_count=7
            fi

            echo
            (
                # Устанавливаем rotate count в logrotate.conf
                sed -i "s/^\s*rotate\s\+[0-9]*/rotate ${keep_count}/" /etc/logrotate.conf 2>/dev/null
                # Добавляем compress если не стоит
                if ! grep -q '^\s*compress' /etc/logrotate.conf 2>/dev/null; then
                    sed -i '/^\s*rotate/a compress' /etc/logrotate.conf 2>/dev/null
                fi
                # Создаём cron-задачу для ротации каждые N часов
                cat > /etc/cron.d/logrotate-custom <<CRON_EOF
*/${rotate_hours} * * * * root /usr/sbin/logrotate /etc/logrotate.conf >/dev/null 2>&1
CRON_EOF
                chmod 644 /etc/cron.d/logrotate-custom
                # Отключаем стандартный daily cron для logrotate чтобы не дублировать
                [ -f /etc/cron.daily/logrotate ] && chmod -x /etc/cron.daily/logrotate 2>/dev/null
            ) &
            show_spinner "Применение настроек"
            echo
            print_success "Ротация: каждые ${rotate_hours}ч, хранить ${keep_count} ротаций"
            echo
            echo -e "${BLUE}══════════════════════════════════════${NC}"
            read -s -n 1 -p "$(echo -e "${DARKGRAY}Нажмите любую клавишу для продолжения...${NC}")"
            echo
            ;;
        1)
            # Ротация Docker логов
            clear
            echo -e "${BLUE}══════════════════════════════════════${NC}"
            echo -e "${GREEN}     🐳 DOCKER ЛОГИ${NC}"
            echo -e "${BLUE}══════════════════════════════════════${NC}"
            echo

            echo -e "${DARKGRAY}Максимальный размер одного лог-файла:${NC}"
            echo

            show_arrow_menu "РАЗМЕР ЛОГА" \
                " 10m" \
                " 20m" \
                " 50m" \
                "100m" \
                "200m" \
                "500m"
            local size_choice=$?

            local log_size
            case $size_choice in
                0) log_size="10m" ;;
                1) log_size="20m" ;;
                2) log_size="50m" ;;
                3) log_size="100m" ;;
                4) log_size="200m" ;;
                5) log_size="500m" ;;
                *) return ;;
            esac

            echo
            local log_files
            reading_inline "Количество лог-файлов (сейчас ${docker_max_file}):" log_files
            if [ -z "$log_files" ] || ! [[ "$log_files" =~ ^[0-9]+$ ]]; then
                log_files=${docker_max_file:-3}
            fi

            echo
            (
                mkdir -p /etc/docker
                cat > /etc/docker/daemon.json <<DOCKER_EOF
{
    "log-driver": "json-file",
    "log-opts": {
        "max-size": "${log_size}",
        "max-file": "${log_files}"
    }
}
DOCKER_EOF
                systemctl restart docker >/dev/null 2>&1
            ) &
            show_spinner "Применение настроек Docker"
            echo
            print_success "Docker логи: max-size=${log_size}, max-file=${log_files}"
            echo -e "${YELLOW}⚠️  Docker перезапущен. Контейнеры будут перезапущены автоматически.${NC}"
            echo
            echo -e "${BLUE}══════════════════════════════════════${NC}"
            read -s -n 1 -p "$(echo -e "${DARKGRAY}Нажмите любую клавишу для продолжения...${NC}")"
            echo
            ;;
        2) return ;;
        3) return ;;
    esac
}

# ═══════════════════════════════════════════════════
# ДОПОЛНИТЕЛЬНЫЕ НАСТРОЙКИ
# ═══════════════════════════════════════════════════
manage_extra_settings() {
    while true; do
        clear
        echo -e "${BLUE}══════════════════════════════════════${NC}"
        echo -e "${GREEN}   ⚙️  ДОПОЛНИТЕЛЬНЫЕ НАСТРОЙКИ${NC}"
        echo -e "${BLUE}══════════════════════════════════════${NC}"
        echo

        show_arrow_menu "ДОПОЛНИТЕЛЬНЫЕ НАСТРОЙКИ" \
            "💾  SWAP" \
            "🌐  WARP" \
            "🛡️   Fail2ban" \
            "🚀  BBR" \
            "🔥  Firewall (UFW)" \
            "📝  Logrotate" \
            "──────────────────────────────────────" \
            "❌  Назад"
        local choice=$?

        case $choice in
            0) manage_swap ;;
            1) manage_warp ;;
            2) manage_fail2ban ;;
            3) manage_bbr ;;
            4) manage_ufw ;;
            5) manage_logrotate ;;
            6) continue ;;
            7) return ;;
        esac
    done
}

