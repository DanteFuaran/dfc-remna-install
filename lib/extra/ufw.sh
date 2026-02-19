# ═══════════════════════════════════════════════════
# FIREWALL (UFW)
# ═══════════════════════════════════════════════════
manage_ufw() {
    while true; do
        # Проверяем установлен ли ufw
        local ufw_installed=0
        command -v ufw >/dev/null 2>&1 && ufw_installed=1

        if [ "$ufw_installed" -eq 0 ]; then
            show_arrow_menu "FIREWALL (UFW)" \
                "🛡️   Установить Firewall (ufw)" \
                "──────────────────────────────────────" \
                "📋  Показать открытые порты" \
                "➕  Открыть порт" \
                "➖  Удалить правило" \
                "──────────────────────────────────────" \
                "❌  Назад"
            local choice=$?

            # Индекс 0 — установить ufw
            if [ "$choice" -eq 0 ]; then
                (apt-get install -y ufw >/dev/null 2>&1) &
                show_spinner "Установка UFW"
                if command -v ufw >/dev/null 2>&1; then
                    print_success "UFW успешно установлен"
                else
                    print_error "Не удалось установить UFW"
                fi
                echo
                read -s -n 1 -p "$(echo -e "${DARKGRAY}Нажмите любую клавишу для продолжения...${NC}")"
                echo
                continue
            fi
            # Разделитель (index 1) — пропускаем, остальные сдвинуты на 2
            [ "$choice" -eq 1 ] && continue
            choice=$((choice - 2))
        else
            # Статус UFW
            clear
            echo -e "${BLUE}══════════════════════════════════════${NC}"
            echo -e "${GREEN}        🔥 FIREWALL (UFW)${NC}"
            echo -e "${BLUE}══════════════════════════════════════${NC}"
            echo

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
                "🗑️   Удалить Firewall (ufw)" \
                "──────────────────────────────────────" \
                "❌  Назад"
            local choice=$?
        fi

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
            4)
                # Удалить UFW
                echo
                echo -e "${YELLOW}Вы уверены, что хотите удалить UFW?${NC}"
                if ! confirm_action; then
                    print_error "Операция отменена"
                    sleep 2
                    continue
                fi
                echo
                (
                    ufw disable >/dev/null 2>&1 || true
                    apt-get remove -y ufw >/dev/null 2>&1
                ) &
                show_spinner "Удаление UFW"
                if ! command -v ufw >/dev/null 2>&1; then
                    print_success "UFW успешно удалён"
                else
                    print_error "Не удалось удалить UFW"
                fi
                echo
                read -s -n 1 -p "$(echo -e "${DARKGRAY}Нажмите любую клавишу для продолжения...${NC}")"
                echo
                ;;
            5) continue ;;
            6) return ;;
        esac
    done
}
