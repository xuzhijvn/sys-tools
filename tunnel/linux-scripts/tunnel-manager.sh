#!/bin/bash

# SSH 隧道管理脚本 - Linux 版本
# 用途：管理多个 SSH 隧道连接
# 作者：Your Name
# 版本：1.0.0

TUNNEL_CONFIG_DIR="/etc/ssh-tunnels/configs"
LOG_DIR="/var/log/ssh-tunnels"
KEYS_DIR="/etc/ssh-tunnels/keys"

# 确保目录存在
[ -d "$TUNNEL_CONFIG_DIR" ] || mkdir -p "$TUNNEL_CONFIG_DIR"
[ -d "$LOG_DIR" ] || mkdir -p "$LOG_DIR"
[ -d "$KEYS_DIR" ] || mkdir -p "$KEYS_DIR"

create_systemd_service() {
    cat > /etc/systemd/system/ssh-tunnel@.service << 'EOF'
[Unit]
Description=SSH Tunnel Service for %i
After=network.target
StartLimitIntervalSec=0

[Service]
Type=simple
Environment="SSH_AUTH_SOCK=/run/user/0/keyring/ssh"
EnvironmentFile=/etc/ssh-tunnels/configs/%i.conf

ExecStart=/bin/bash -c '\
    /usr/bin/ssh -N \
    -o "ServerAliveInterval=30" \
    -o "ServerAliveCountMax=3" \
    -o "ExitOnForwardFailure=yes" \
    -o "TCPKeepAlive=yes" \
    -o "StrictHostKeyChecking=accept-new" \
    -o "ConnectTimeout=10" \
    -o "ConnectionAttempts=3" \
    -o "IdentityFile=${SSH_KEY}" \
    ${EXTRA_SSH_OPTS} \
    ${TUNNEL_MODE:0:1} "${LOCAL_PORT}${REMOTE_HOST:+:$REMOTE_HOST}${REMOTE_PORT:+:$REMOTE_PORT}" \
    ${SSH_SERVER}'

Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF
}

create_monitor_service() {
    cat > /etc/systemd/system/tunnel-monitor.service << 'EOF'
[Unit]
Description=SSH Tunnels Monitor
After=network.target

[Service]
Type=simple
ExecStart=/usr/local/bin/tunnel-monitor.sh
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF
}

create_monitor_script() {
    cat > /usr/local/bin/tunnel-monitor.sh << 'EOF'
#!/bin/bash

LOG_FILE="/var/log/ssh-tunnels/monitor.log"
CONFIG_DIR="/etc/ssh-tunnels/configs"
CHECK_INTERVAL=30
MAX_FAILURES=3
declare -A FAILURE_COUNTS

log() {
    local message="$1"
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $message" >> "$LOG_FILE"
    logger -t ssh-tunnels "$message"
}

check_tunnel() {
    local config="$1"
    source "$config"
    
    if ! netstat -tln | grep -q ":${LOCAL_PORT}"; then
        FAILURE_COUNTS["$TUNNEL_NAME"]=$((FAILURE_COUNTS["$TUNNEL_NAME"] + 1))
        log "Tunnel $TUNNEL_NAME (port $LOCAL_PORT) check failed. Failure count: ${FAILURE_COUNTS[$TUNNEL_NAME]}"
        
        if [ "${FAILURE_COUNTS[$TUNNEL_NAME]}" -ge "$MAX_FAILURES" ]; then
            log "Max failures reached for $TUNNEL_NAME. Restarting tunnel..."
            systemctl restart "ssh-tunnel@${TUNNEL_NAME}"
            FAILURE_COUNTS["$TUNNEL_NAME"]=0
            
            sleep 5
            if netstat -tln | grep -q ":${LOCAL_PORT}"; then
                log "Tunnel $TUNNEL_NAME restored successfully"
            else
                log "Failed to restore tunnel $TUNNEL_NAME"
            fi
        fi
    else
        FAILURE_COUNTS["$TUNNEL_NAME"]=0
    fi
}

# 确保日志目录存在
mkdir -p "$(dirname "$LOG_FILE")"

# 记录启动信息
log "SSH tunnel monitor started"

# 主循环
while true; do
    for config in "$CONFIG_DIR"/*.conf; do
        [ -f "$config" ] && check_tunnel "$config"
    done
    sleep "$CHECK_INTERVAL"
done
EOF

    chmod +x /usr/local/bin/tunnel-monitor.sh
}

setup_tunnel() {
    local name="$1"
    local mode="$2"          # 新增：隧道模式 (L/R/D)
    local local_port="$3"
    local remote_host="$4"   # 对于动态转发(-D)，这个参数会被忽略
    local remote_port="$5"   # 对于动态转发(-D)，这个参数会被忽略
    local ssh_server="$6"
    local ssh_key="$7"
    local extra_opts="${8:-}"
    
    # 验证模式
    case "$mode" in
        L|R|D) ;;
        *) echo "Invalid mode. Use L for local, R for remote, or D for dynamic forwarding."; return 1 ;;
    esac
    
    # 创建配置文件
    cat > "${TUNNEL_CONFIG_DIR}/${name}.conf" << EOF
TUNNEL_NAME="$name"
TUNNEL_MODE="$mode"
LOCAL_PORT="$local_port"
REMOTE_HOST="$remote_host"
REMOTE_PORT="$remote_port"
SSH_SERVER="$ssh_server"
SSH_KEY="$ssh_key"
EXTRA_SSH_OPTS="$extra_opts"
EOF
    
    systemctl daemon-reload
    systemctl enable "ssh-tunnel@${name}"
    systemctl restart "ssh-tunnel@${name}"
}

case "$1" in
    add)
        shift
        setup_tunnel "$@"
        ;;
    remove)
        name="$2"
        systemctl stop "ssh-tunnel@${name}"
        systemctl disable "ssh-tunnel@${name}"
        rm -f "${TUNNEL_CONFIG_DIR}/${name}.conf"
        systemctl daemon-reload
        ;;
    list)
        for conf in "$TUNNEL_CONFIG_DIR"/*.conf; do
            if [ -f "$conf" ]; then
                source "$conf"
                echo "Tunnel: $TUNNEL_NAME"
                echo "  Mode: $TUNNEL_MODE"
                echo "  Local Port: $LOCAL_PORT"
                case "$TUNNEL_MODE" in
                    D)
                        echo "  Type: Dynamic SOCKS Proxy"
                        ;;
                    *)
                        echo "  Remote: $REMOTE_HOST:$REMOTE_PORT"
                        ;;
                esac
                echo "  Server: $SSH_SERVER"
                echo "---"
            fi
        done
        ;;
    stop)
        name="$2"
        if [ -z "$name" ]; then
            # 停止所有隧道
            for conf in "$TUNNEL_CONFIG_DIR"/*.conf; do
                if [ -f "$conf" ]; then
                    source "$conf"
                    systemctl stop "ssh-tunnel@${TUNNEL_NAME}"
                fi
            done
        else
            # 停止特定隧道
            systemctl stop "ssh-tunnel@${name}"
        fi
        ;;
    restart)
        name="$2"
        if [ -z "$name" ]; then
            # 重启所有隧道
            for conf in "$TUNNEL_CONFIG_DIR"/*.conf; do
                if [ -f "$conf" ]; then
                    source "$conf"
                    systemctl restart "ssh-tunnel@${TUNNEL_NAME}"
                fi
            done
        else
            # 重启特定隧道
            systemctl restart "ssh-tunnel@${name}"
        fi
        ;;
    setup)
        create_systemd_service
        create_monitor_service
        create_monitor_script
        systemctl daemon-reload
        systemctl enable tunnel-monitor
        systemctl start tunnel-monitor
        ;;
    status)
        for conf in "$TUNNEL_CONFIG_DIR"/*.conf; do
            if [ -f "$conf" ]; then
                source "$conf"
                echo -n "Tunnel $TUNNEL_NAME (port $LOCAL_PORT): "
                if systemctl is-active "ssh-tunnel@${TUNNEL_NAME}" >/dev/null 2>&1; then
                    if netstat -tln | grep -q ":${LOCAL_PORT}"; then
                        echo "ACTIVE"
                    else
                        echo "FAILED (port not listening)"
                    fi
                else
                    echo "STOPPED"
                fi
            fi
        done
        ;;
    clean)
        echo "正在清理所有 SSH 隧道及相关文件..."
        
        # 1. 停止并禁用所有隧道服务
        for conf in "$TUNNEL_CONFIG_DIR"/*.conf; do
            if [ -f "$conf" ]; then
                source "$conf"
                echo "停止隧道: $TUNNEL_NAME"
                systemctl stop "ssh-tunnel@${TUNNEL_NAME}"
                systemctl disable "ssh-tunnel@${TUNNEL_NAME}"
            fi
        done
        
        # 2. 停止并禁用监控服务
        echo "停止监控服务"
        systemctl stop tunnel-monitor
        systemctl disable tunnel-monitor
        
        # 3. 删除 systemd 服务文件
        echo "删除服务文件"
        rm -f /etc/systemd/system/ssh-tunnel@.service
        rm -f /etc/systemd/system/tunnel-monitor.service
        systemctl daemon-reload
        
        # 4. 删除脚本文件
        echo "删除脚本文件"
        rm -f /usr/local/bin/tunnel-monitor.sh
        
        # 5. 删除配置目录
        echo "删除配置目录"
        rm -rf /etc/ssh-tunnels
        
        # 6. 删除日志文件
        echo "删除日志文件"
        rm -rf /var/log/ssh-tunnels
        
        echo "清理完成"
        ;;
    *)
        echo "Usage:"
        echo "  $0 add <name> <mode> <local_port> <remote_host> <remote_port> <ssh_server> <ssh_key> [extra_opts]"
        echo "  $0 remove <name>"
        echo "  $0 list"
        echo "  $0 setup"
        echo "  $0 status"
        echo "  $0 stop [name]      # 停止所有隧道或指定隧道"
        echo "  $0 restart [name]   # 重启所有隧道或指定隧道"
        echo "  $0 clean           # 清理所有隧道及相关文件"
        ;;
esac 