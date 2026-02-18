#!/bin/bash

SCRIPT_VERSION="0.4.38"
DIR_REMNAWAVE="/usr/local/dfc-remna-install/"
DIR_PANEL="/opt/remnawave/"
DIR_NODE="/opt/remnanode/"
SCRIPT_URL="https://raw.githubusercontent.com/DanteFuaran/dfc-remna-install/refs/heads/dev/install_remnawave.sh"
# Файлы кэша проверки обновлений (в стабильной директории, а не в /tmp)
UPDATE_AVAILABLE_FILE="${DIR_REMNAWAVE}update_available"
UPDATE_CHECK_TIME_FILE="${DIR_REMNAWAVE}last_update_check"

# Сохраняем исходное состояние терминала (до любых изменений)
ORIGINAL_STTY=$(stty -g 2>/dev/null || echo "")

# ═══════════════════════════════════════════════
# ВОССТАНОВЛЕНИЕ ТЕРМИНАЛА И ОБРАБОТКА ПРЕРЫВАНИЙ
# ═══════════════════════════════════════════════
cleanup_terminal() {
    # Полное восстановление терминала
    tput cnorm 2>/dev/null || true
    tput sgr0 2>/dev/null || true
    printf "\033[0m\033[?25h" 2>/dev/null || true
    if [ -n "$ORIGINAL_STTY" ]; then
        stty "$ORIGINAL_STTY" 2>/dev/null || stty sane 2>/dev/null || true
    else
        stty sane 2>/dev/null || true
    fi
}

# Удаление старых алиасов и команд
cleanup_old_aliases() {
    # Удаляем старый алиас ri
    sed -i "/alias ri='remna_install'/d" /etc/bash.bashrc 2>/dev/null
    sed -i "/alias ri='remna_install'/d" /etc/bashrc 2>/dev/null
    sed -i "/alias ri='remna_install'/d" /root/.bashrc 2>/dev/null
    sed -i "/alias ri='remna_install'/d" /root/.bash_aliases 2>/dev/null
    if [ -n "$HOME" ] && [ "$HOME" != "/root" ]; then
        sed -i "/alias ri='remna_install'/d" "$HOME/.bashrc" 2>/dev/null
        sed -i "/alias ri='remna_install'/d" "$HOME/.bash_aliases" 2>/dev/null
    fi
    rm -f /etc/profile.d/remna_install.sh 2>/dev/null
    rm -f /usr/local/bin/remna_install 2>/dev/null
    unalias ri 2>/dev/null || true
}

# Тихая самоочистка если ничего не установлено
cleanup_uninstalled() {
    if [ ! -f "/opt/remnawave/docker-compose.yml" ]; then
        rm -f /usr/local/bin/dfc-remna-install
        rm -f /usr/local/bin/dfc-ri
        rm -rf "${DIR_REMNAWAVE:-/usr/local/dfc-remna-install/}"
        rm -f "${UPDATE_AVAILABLE_FILE}" "${UPDATE_CHECK_TIME_FILE}" 2>/dev/null
        cleanup_old_aliases
    fi
}

handle_interrupt() {
    cleanup_terminal
    echo
    echo -e "${RED}⚠️  Скрипт был остановлен пользователем${NC}"
    echo
    cleanup_uninstalled
    exit 130
}

trap cleanup_terminal EXIT
trap handle_interrupt INT TERM

# ═══════════════════════════════════════════════
# ЦВЕТА
# ═══════════════════════════════════════════════
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[1;34m'
WHITE='\033[1;37m'
GRAY='\033[0;37m'
NC='\033[0m'
DARKGRAY='\033[1;30m'

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
    local original_stty
    original_stty=$(stty -g 2>/dev/null)

    # Скрываем курсор
    tput civis 2>/dev/null || true

    # Отключаем canonical mode и echo, включаем чтение отдельных символов
    stty -icanon -echo min 1 time 0 2>/dev/null || true

    # Функция восстановления терминала
    _restore_term() {
        stty "$original_stty" 2>/dev/null || stty sane 2>/dev/null || true
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
                echo -e "${options[$i]}"
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

# Ввод текста с подсказкой
reading() {
    local prompt="$1"
    local var_name="$2"
    local input
    echo
    read -e -p "$(echo -e "${BLUE}➜${NC}  ${YELLOW}$prompt${NC} ")" input
    eval "$var_name='$input'"
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
    eval "$var_name='$input'"
}

confirm_action() {
    echo
    echo -e "${YELLOW}⚠️  Нажмите Enter для подтверждения, или Esc для отмены.${NC}"
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

# ═══════════════════════════════════════════════
# ПРОВЕРКИ СИСТЕМЫ
# ═══════════════════════════════════════════════
check_root() {
    if [ "$(id -u)" -ne 0 ]; then
        print_error "Скрипт нужно запускать с правами root"
        exit 1
    fi
}

check_os() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        case "$ID" in
            debian)
                if [[ "$VERSION_ID" != "11" && "$VERSION_ID" != "12" ]]; then
                    print_error "Поддержка только Debian 11/12 и Ubuntu 22.04/24.04"
                    exit 1
                fi
                ;;
            ubuntu)
                if [[ "$VERSION_ID" != "22.04" && "$VERSION_ID" != "24.04" ]]; then
                    print_error "Поддержка только Debian 11/12 и Ubuntu 22.04/24.04"
                    exit 1
                fi
                ;;
            *)
                print_error "Поддержка только Debian 11/12 и Ubuntu 22.04/24.04"
                exit 1
                ;;
        esac
    else
        print_error "Не удалось определить ОС"
        exit 1
    fi
}

# ═══════════════════════════════════════════════
# УСТАНОВКА ПАКЕТОВ
# ═══════════════════════════════════════════════
install_packages() {
    (
        export DEBIAN_FRONTEND=noninteractive
        # Автоответ на вопросы dpkg: сохранить текущий конфиг пользователя
        local DPKG_OPTS='-o Dpkg::Options::=--force-confdef -o Dpkg::Options::=--force-confold'

        # Обновление и установка пакетов
        apt-get update -qq >/dev/null 2>&1
        apt-get upgrade -y -qq $DPKG_OPTS >/dev/null 2>&1
        apt-get install -y -qq $DPKG_OPTS ca-certificates curl jq ufw wget gnupg unzip nano dialog git \
            certbot python3-certbot-dns-cloudflare unattended-upgrades locales dnsutils \
            coreutils grep gawk logrotate >/dev/null 2>&1

        # Cron
        if ! dpkg -l | grep -q '^ii.*cron '; then
            apt-get install -y -qq $DPKG_OPTS cron >/dev/null 2>&1
        fi
        systemctl start cron 2>/dev/null || true
        systemctl enable cron 2>/dev/null || true

        # Logrotate
        if ! dpkg -l | grep -q '^ii.*logrotate '; then
            apt-get install -y -qq $DPKG_OPTS logrotate >/dev/null 2>&1
        fi

        # Docker
        if ! command -v docker >/dev/null 2>&1 || ! docker info >/dev/null 2>&1; then
            curl -fsSL https://get.docker.com -o /tmp/get-docker.sh
            sh /tmp/get-docker.sh >/dev/null 2>&1
            rm -f /tmp/get-docker.sh
        fi
        systemctl start docker 2>/dev/null || true
        systemctl enable docker 2>/dev/null || true

        # BBR
        if ! sysctl net.ipv4.tcp_congestion_control 2>/dev/null | grep -q bbr; then
            echo "net.core.default_qdisc=fq" >> /etc/sysctl.conf
            echo "net.ipv4.tcp_congestion_control=bbr" >> /etc/sysctl.conf
            sysctl -p >/dev/null 2>&1
        fi

        # Memory overcommit (рекомендовано для Redis/Valkey — предотвращает сбои фоновых сохранений)
        if ! sysctl vm.overcommit_memory 2>/dev/null | grep -q "= 1"; then
            sysctl -w vm.overcommit_memory=1 >/dev/null 2>&1
            if ! grep -q 'vm.overcommit_memory' /etc/sysctl.conf 2>/dev/null; then
                echo 'vm.overcommit_memory=1' >> /etc/sysctl.conf
            else
                sed -i 's/vm.overcommit_memory=.*/vm.overcommit_memory=1/' /etc/sysctl.conf
            fi
        fi

        # UFW
        ufw default deny incoming >/dev/null 2>&1
        ufw default allow outgoing >/dev/null 2>&1
        ufw allow 22/tcp >/dev/null 2>&1
        # Добавляем кастомный SSH-порт из sshd_config (если отличается от 22)
        local sshd_port
        sshd_port=$(grep -E "^Port " /etc/ssh/sshd_config 2>/dev/null | awk '{print $2}')
        if [ -n "$sshd_port" ] && [ "$sshd_port" != "22" ]; then
            ufw allow "${sshd_port}/tcp" >/dev/null 2>&1
        fi
        ufw allow 443/tcp >/dev/null 2>&1
        echo "y" | ufw enable >/dev/null 2>&1

        # Автодополнение команд UFW
        apt-get install --reinstall -y -qq bash-completion ufw >/dev/null 2>&1
        ln -sf /usr/share/bash-completion/completions/ufw /etc/bash_completion.d/ufw 2>/dev/null || true
        if ! grep -q "/usr/share/bash-completion/bash_completion" /root/.bashrc 2>/dev/null; then
            printf 'if [ -f /usr/share/bash-completion/bash_completion ]; then\n    . /usr/share/bash-completion/bash_completion\nfi\n' >> /root/.bashrc
        fi
        source /usr/share/bash-completion/bash_completion 2>/dev/null || true
        source /usr/share/bash-completion/completions/ufw 2>/dev/null || true

        # IPv6 disable
        sysctl -w net.ipv6.conf.all.disable_ipv6=1 >/dev/null 2>&1
        sysctl -w net.ipv6.conf.default.disable_ipv6=1 >/dev/null 2>&1
        if ! grep -q "net.ipv6.conf.all.disable_ipv6" /etc/sysctl.conf; then
            echo "net.ipv6.conf.all.disable_ipv6=1" >> /etc/sysctl.conf
            echo "net.ipv6.conf.default.disable_ipv6=1" >> /etc/sysctl.conf
        fi

        # Locales
        sed -i '/^#.*en_US.UTF-8/s/^#//' /etc/locale.gen 2>/dev/null || true
        locale-gen >/dev/null 2>&1 || true

        # Создаём директорию для флага, если её нет
        mkdir -p "${DIR_REMNAWAVE}" 2>/dev/null || true
        touch "${DIR_REMNAWAVE}install_packages"
    ) &
    echo
    show_spinner "Установка необходимых пакетов"
    
    # Активация автодополнения для текущей shell сессии
    source /usr/share/bash-completion/bash_completion 2>/dev/null || true
    source /usr/share/bash-completion/completions/ufw 2>/dev/null || true
}

setup_firewall() {
    ufw default deny incoming >/dev/null 2>&1 || true
    ufw default allow outgoing >/dev/null 2>&1 || true
    ufw allow 22/tcp >/dev/null 2>&1 || true
    # Добавляем кастомный SSH-порт из sshd_config (если отличается от 22)
    local sshd_port
    sshd_port=$(grep -E "^Port " /etc/ssh/sshd_config 2>/dev/null | awk '{print $2}')
    if [ -n "$sshd_port" ] && [ "$sshd_port" != "22" ]; then
        ufw allow "${sshd_port}/tcp" >/dev/null 2>&1 || true
    fi
    ufw allow 443/tcp >/dev/null 2>&1 || true
    echo "y" | ufw enable >/dev/null 2>&1 || true
}

