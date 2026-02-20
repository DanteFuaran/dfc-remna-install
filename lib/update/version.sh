# ═══════════════════════════════════════════════
# ПРОВЕРКА ВЕРСИИ
# ═══════════════════════════════════════════════

get_installed_version() {
    if [ -f "${DIR_REMNAWAVE}lib/core/constants.sh" ]; then
        grep -m 1 'SCRIPT_VERSION=' "${DIR_REMNAWAVE}lib/core/constants.sh" 2>/dev/null | cut -d'"' -f2
    else
        echo ""
    fi
}

get_remote_version() {
    local latest_sha
    latest_sha=$(curl -sL --max-time 5 "https://api.github.com/repos/DanteFuaran/dfc-remna-install/commits/main" 2>/dev/null | grep -m 1 '"sha"' | cut -d'"' -f4 || true)

    if [ -n "$latest_sha" ]; then
        curl -sL --max-time 5 "https://raw.githubusercontent.com/DanteFuaran/dfc-remna-install/$latest_sha/lib/core/constants.sh" 2>/dev/null | grep -m 1 'SCRIPT_VERSION=' | cut -d'"' -f2 || true
    else
        curl -sL --max-time 5 "https://raw.githubusercontent.com/DanteFuaran/dfc-remna-install/main/lib/core/constants.sh" 2>/dev/null | grep -m 1 'SCRIPT_VERSION=' | cut -d'"' -f2 || true
    fi
}

check_for_updates() {
    local remote_version
    remote_version=$(get_remote_version)
    
    if [ -z "$remote_version" ]; then
        return 1
    fi
    
    local local_version
    local_version=$(get_installed_version)
    if [ -z "$local_version" ]; then
        local_version="$SCRIPT_VERSION"
    fi

    if [ "$remote_version" != "$local_version" ]; then
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
