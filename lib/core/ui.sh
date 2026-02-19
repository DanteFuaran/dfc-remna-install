# ═══════════════════════════════════════════════
# УТИЛИТЫ ВЫВОДА
# ═══════════════════════════════════════════════

print_action()  { :; }
print_error()   { printf "${RED}✖ %b${NC}\n" "$1"; }
print_success() { printf "${GREEN}✅${NC} %b\n" "$1"; }
print_warning() { printf "${YELLOW}⚠️  %b${NC}\n" "$1"; }

# ═══════════════════════════════════════════════
# СПИННЕРЫ
# ═══════════════════════════════════════════════

show_spinner() {
    local pid=$!
    local delay=0.08
    local spin=('⠋' '⠙' '⠹' '⠸' '⠼' '⠴' '⠦' '⠧' '⠇' '⠏')
    local i=0 msg="$1"
    tput civis 2>/dev/null || true
    while kill -0 $pid 2>/dev/null; do
        printf "\r${GREEN}%s${NC}  %s" "${spin[$i]}" "$msg"
        i=$(( (i+1) % 10 ))
        sleep $delay
    done
    wait $pid 2>/dev/null || true
    printf "\r${GREEN}✅${NC} %s\n" "$msg"
    tput cnorm 2>/dev/null || true
}

show_spinner_timer() {
    local seconds=$1
    local msg="$2"
    local done_msg="${3:-$msg}"
    local spin=('⠋' '⠙' '⠹' '⠸' '⠼' '⠴' '⠦' '⠧' '⠇' '⠏')
    local i=0
    local delay=0.08
    local elapsed=0
    tput civis 2>/dev/null || true
    while [ $elapsed -lt $seconds ]; do
        local remaining=$((seconds - elapsed))
        for ((j=0; j<12; j++)); do
            printf "\r\033[K${DARKGRAY}%s  %s (%d сек)${NC}" "${spin[$i]}" "$msg" "$remaining"
            sleep $delay
            i=$(( (i+1) % 10 ))
        done
        ((elapsed++))
    done
    printf "\r\033[K${GREEN}✅${NC} %s\n" "$done_msg"
    tput cnorm 2>/dev/null || true
}

show_spinner_until_ready() {
    local url="$1"
    local msg="$2"
    local timeout=${3:-120}
    local spin=('⠋' '⠙' '⠹' '⠸' '⠼' '⠴' '⠦' '⠧' '⠇' '⠏')
    local i=0 elapsed=0 delay=0.08 loop_count=0
    tput civis 2>/dev/null || true
    while [ $elapsed -lt $timeout ]; do
        printf "\r${DARKGRAY}%s  %s${NC}" "${spin[$i]}" "$msg"
        i=$(( (i+1) % 10 ))
        sleep $delay
        ((loop_count++))
        if [ $((loop_count % 12)) -eq 0 ]; then
            ((elapsed++))
            if curl -s -f --max-time 5 "$url" \
                --header 'X-Forwarded-For: 127.0.0.1' \
                --header 'X-Forwarded-Proto: https' \
                > /dev/null 2>&1; then
                printf "\r${GREEN}✅${NC} %s\n" "$msg"
                tput cnorm 2>/dev/null || true
                return 0
            fi
        fi
    done
    printf "\r${YELLOW}⚠️${NC}  %s (таймаут)\n" "$msg"
    tput cnorm 2>/dev/null || true
    return 1
}

# ═══════════════════════════════════════════════
# МЕНЮ СО СТРЕЛОЧКАМИ
# ═══════════════════════════════════════════════

show_arrow_menu() {
    set +e
    local title="$1"
    shift
    local options=("$@")
    local num_options=${#options[@]}
    local selected=0

    # Сохраняем настройки терминала
    local original_stty=""
    original_stty=$(stty -g 2>/dev/null || echo "")

    # Скрываем курсор
    tput civis 2>/dev/null || true

    # Отключаем canonical mode и echo, включаем чтение отдельных символов
    stty -icanon -echo min 1 time 0 2>/dev/null || true

    # Функция восстановления терминала
    _restore_term() {
        if [ -n "${original_stty:-}" ]; then
            stty "$original_stty" 2>/dev/null || stty sane 2>/dev/null || true
        else
            stty sane 2>/dev/null || true
        fi
        tput cnorm 2>/dev/null || true
    }

    # Обработчик ошибок для этой функции
    trap "_restore_term" RETURN

    while true; do
        clear
        echo -e "${BLUE}══════════════════════════════════════${NC}"
        echo -e "${GREEN}   $title${NC}"
        echo -e "${BLUE}══════════════════════════════════════${NC}"
        echo

        for i in "${!options[@]}"; do
            # Проверяем, является ли элемент разделителем
            if [[ "${options[$i]}" =~ ^[─━═\s]*$ ]]; then
                # Разделители без отступа - вровень с рамкой
                echo -e "${DARKGRAY}${options[$i]}${NC}"
            elif [ $i -eq $selected ]; then
                echo -e "${BLUE}▶${NC} ${YELLOW}${options[$i]}${NC}"
            else
                echo -e "  ${options[$i]}"
            fi
        done

        echo
        echo -e "${BLUE}══════════════════════════════════════${NC}"
        echo -e "${DARKGRAY}Используйте ↑↓ для навигации, Enter для выбора${NC}"
        echo

        local key
        read -rsn1 key 2>/dev/null || key=""

        # Проверяем escape-последовательность для стрелок
        if [[ "$key" == $'\e' ]]; then
            local seq1="" seq2=""
            read -rsn1 -t 0.1 seq1 2>/dev/null || seq1=""
            if [[ "$seq1" == '[' ]]; then
                read -rsn1 -t 0.1 seq2 2>/dev/null || seq2=""
                case "$seq2" in
                    'A')  # Стрелка вверх
                        ((selected--))
                        if [ $selected -lt 0 ]; then
                            selected=$((num_options - 1))
                        fi
                        # Пропускаем разделители вверх
                        while [[ "${options[$selected]}" =~ ^[─═\s]*$ ]]; do
                            ((selected--))
                            if [ $selected -lt 0 ]; then
                                selected=$((num_options - 1))
                            fi
                        done
                        ;;
                    'B')  # Стрелка вниз
                        ((selected++))
                        if [ $selected -ge $num_options ]; then
                            selected=0
                        fi
                        # Пропускаем разделители вниз
                        while [[ "${options[$selected]}" =~ ^[─═\s]*$ ]]; do
                            ((selected++))
                            if [ $selected -ge $num_options ]; then
                                selected=0
                            fi
                        done
                        ;;
                esac
            fi
        else
            local key_code
            if [ -n "$key" ]; then
                key_code=$(printf '%d' "'$key" 2>/dev/null || echo 0)
            else
                key_code=13
            fi

            if [ "$key_code" -eq 10 ] || [ "$key_code" -eq 13 ]; then
                # Восстанавливаем состояние терминала перед выходом
                _restore_term
                return $selected
            fi
        fi
    done
}

# ═══════════════════════════════════════════════
# ВВОД ТЕКСТА
# ═══════════════════════════════════════════════

# Ввод текста с подсказкой
reading() {
    local prompt="$1"
    local var_name="$2"
    local input
    echo
    read -e -p "$(echo -e "${BLUE}➜${NC}  ${YELLOW}$prompt${NC} ")" input
    printf -v "$var_name" '%s' "$input"
}

reading_inline() {
    local prompt="$1"
    local var_name="$2"
    local input=""
    local char
    echo -en "${BLUE}➜${NC}  ${YELLOW}${prompt}${NC} "
    while IFS= read -r -s -n1 char; do
        if [[ -z "$char" ]]; then
            break
        elif [[ "$char" == $'\x7f' ]] || [[ "$char" == $'\x08' ]]; then
            if [[ -n "$input" ]]; then
                input="${input%?}"
                echo -en "\b \b"
            fi
        elif [[ "$char" == $'\x1b' ]]; then
            local _seq=""
            while IFS= read -r -s -n1 -t 0.1 _sc; do
                _seq+="$_sc"
                [[ "$_sc" =~ [A-Za-z~] ]] && break
            done
        else
            input+="$char"
            echo -en "$char"
        fi
    done
    echo
    printf -v "$var_name" '%s' "$input"
}

confirm_action() {
    echo -e "${DARKGRAY}Enter: Подтвердить     Esc: Отмена${NC}"
    tput civis  # Скрыть курсор

    local key
    while true; do
        read -s -n 1 key
        if [[ "$key" == $'\x1b' ]]; then
            tput cnorm  # Показать курсор
            return 1
        elif [[ "$key" == "" ]]; then
            tput cnorm  # Показать курсор
            return 0
        fi
    done
}
