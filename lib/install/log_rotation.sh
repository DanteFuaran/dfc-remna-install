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
