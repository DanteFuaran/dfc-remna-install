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

    if [ "$current_cc" = "bbr" ]; then
        # BBR включён — показываем только "Выключить"
        show_arrow_menu "🚀  BBR" \
            "❌  Выключить BBR" \
            "──────────────────────────────────────" \
            "↩️   Назад"
        local choice=$?
        case $choice in
            0)
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
                show_continue_prompt || return 1
                ;;
            *) return ;;
        esac
    else
        # BBR выключен — показываем только "Включить"
        show_arrow_menu "🚀  BBR" \
            "✅  Включить BBR" \
            "──────────────────────────────────────" \
            "↩️   Назад"
        local choice=$?
        case $choice in
            0)
                echo
                (
                    sysctl -w net.core.default_qdisc=fq >/dev/null 2>&1
                    sysctl -w net.ipv4.tcp_congestion_control=bbr >/dev/null 2>&1
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
                show_continue_prompt || return 1
                ;;
            *) return ;;
        esac
    fi
}
