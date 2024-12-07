#!/bin/sh

# SSH 隧道管理脚本 - OpenWRT 版本
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

create_init_script() {
    cat > /etc/init.d/ssh-tunnels << 'EOF'
#!/bin/sh /etc/rc.common

START=99
USE_PROCD=1
EXTRA_COMMANDS="status check restart_tunnel"
EXTRA_HELP="        restart_tunnel     Restart a specific tunnel"

start_tunnel() {
    local config="$1"
    . "$config"
    
    procd_open_instance "$TUNNEL_NAME"
    procd_set_param command /usr/bin/ssh
    procd_append_param command -N
    procd_append_param command -o "ServerAliveInterval=30"
    procd_append_param command -o "ServerAliveCountMax=3"
    procd_append_param command -o "ExitOnForwardFailure=yes"
    procd_append_param command -o "TCPKeepAlive=yes"
    procd_append_param command -o "ConnectTimeout=10"
    procd_append_param command -o "IdentityFile=${SSH_KEY}"
    [ -n "$EXTRA_SSH_OPTS" ] && procd_append_param command ${EXTRA_SSH_OPTS}
    
    case "$TUNNEL_MODE" in
        L)
            procd_append_param command -L "${LOCAL_PORT}:${REMOTE_HOST}:${REMOTE_PORT}"
            ;;
        R)
            procd_append_param command -R "${LOCAL_PORT}:${REMOTE_HOST}:${REMOTE_PORT}"
            ;;
        D)
            procd_append_param command -D "${LOCAL_PORT}"
            ;;
    esac
    
    procd_append_param command "${SSH_SERVER}"
    
    procd_set_param respawn ${respawn_threshold:-3600} ${respawn_timeout:-5} ${respawn_retry:-5}
    procd_set_param stderr 1
    procd_set_param stdout 1
    procd_close_instance
}

stop_tunnel() {
    local tunnel_name="$1"
    local pids=$(pgrep -f "ssh.*${tunnel_name}")
    [ -n "$pids" ] && kill $pids
}

restart_tunnel() {
    local tunnel_name="$1"
    local config="/etc/ssh-tunnels/configs/${tunnel_name}.conf"
    
    if [ -f "$config" ]; then
        stop_tunnel "$tunnel_name"
        start_tunnel "$config"
        procd_commit
    else
        echo "Tunnel configuration not found: $tunnel_name"
        return 1
    fi
}

start_service() {
    for config in /etc/ssh-tunnels/configs/*.conf; do
        [ -f "$config" ] && start_tunnel "$config"
    done
}

service_triggers() {
    procd_add_reload_trigger "ssh-tunnels"
}
EOF

    chmod +x /etc/init.d/ssh-tunnels
}

setup_tunnel() {
    local name="$1"
    local mode="$2"
    local local_port="$3"
    local remote_host="$4"
    local remote_port="$5"
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
    
    # 确保服务已启用
    /etc/init.d/ssh-tunnels enable
    
    # 只重启特定的隧道
    /etc/init.d/ssh-tunnels restart_tunnel "$name"
}

create_monitor_script() {
    cat > /usr/bin/ssh-tunnels/monitor.sh << 'EOF'
#!/bin/sh

LOG_FILE="/var/log/ssh-tunnels/monitor.log"
CONFIG_DIR="/etc/ssh-tunnels/configs"
CHECK_INTERVAL=30
MAX_FAILURES=3
FAILURE_COUNTS=""

log() {
    local message="$1"
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $message" >> "$LOG_FILE"
    logger -t ssh-tunnels "$message"
}

get_failure_count() {
    local tunnel_name="$1"
    local count=0
    for item in $FAILURE_COUNTS; do
        local name="${item%%:*}"
        local value="${item#*:}"
        if [ "$name" = "$tunnel_name" ]; then
            count=$value
            break
        fi
    done
    echo "$count"
}

set_failure_count() {
    local tunnel_name="$1"
    local new_count="$2"
    local new_counts=""
    local found=0
    
    for item in $FAILURE_COUNTS; do
        local name="${item%%:*}"
        local value="${item#*:}"
        if [ "$name" = "$tunnel_name" ]; then
            new_counts="$new_counts $name:$new_count"
            found=1
        else
            new_counts="$new_counts $item"
        fi
    done
    
    if [ "$found" -eq 0 ]; then
        new_counts="$new_counts $tunnel_name:$new_count"
    fi
    
    FAILURE_COUNTS="$new_counts"
}

check_tunnel() {
    local config="$1"
    . "$config"
    
    if ! netstat -tln | grep -q ":${LOCAL_PORT}"; then
        local count=$(get_failure_count "$TUNNEL_NAME")
        count=$((count + 1))
        set_failure_count "$TUNNEL_NAME" "$count"
        log "Tunnel $TUNNEL_NAME (port $LOCAL_PORT) check failed. Failure count: $count"
        
        if [ "$count" -ge "$MAX_FAILURES" ]; then
            log "Max failures reached for $TUNNEL_NAME. Restarting tunnel..."
            /etc/init.d/ssh-tunnels restart_tunnel "$TUNNEL_NAME"
            set_failure_count "$TUNNEL_NAME" 0
            
            sleep 5
            if netstat -tln | grep -q ":${LOCAL_PORT}"; then
                log "Tunnel $TUNNEL_NAME restored successfully"
            else
                log "Failed to restore tunnel $TUNNEL_NAME"
            fi
        fi
    else
        set_failure_count "$TUNNEL_NAME" 0
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

    chmod +x /usr/bin/ssh-tunnels/monitor.sh
}

case "$1" in
    add)
        shift
        setup_tunnel "$@"
        ;;
    remove)
        name="$2"
        /etc/init.d/ssh-tunnels stop_tunnel "$name"
        rm -f "${TUNNEL_CONFIG_DIR}/${name}.conf"
        ;;
    list)
        for conf in "$TUNNEL_CONFIG_DIR"/*.conf; do
            if [ -f "$conf" ]; then
                . "$conf"
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
            /etc/init.d/ssh-tunnels stop
        else
            # 停止特定隧道
            /etc/init.d/ssh-tunnels stop_tunnel "$name"
        fi
        ;;
    restart)
        name="$2"
        if [ -z "$name" ]; then
            # 重启所有隧道
            /etc/init.d/ssh-tunnels restart
        else
            # 重启特定隧道
            /etc/init.d/ssh-tunnels restart_tunnel "$name"
        fi
        ;;
    setup)
        create_init_script
        create_monitor_script
        setup_monitoring
        /etc/init.d/ssh-tunnels enable
        /etc/init.d/ssh-tunnels start
        ;;
    status)
        /etc/init.d/ssh-tunnels status
        ;;
    clean)
        echo "正在清理所有 SSH 隧道及相关文件..."
        
        # 1. 停止所有隧道服务
        echo "停止所有服务"
        /etc/init.d/ssh-tunnels stop
        /etc/init.d/ssh-tunnels disable
        
        # 2. 删除 init.d 脚本
        echo "删除服务脚本"
        rm -f /etc/init.d/ssh-tunnels
        
        # 3. 删除 hotplug 脚本
        echo "删除 hotplug 脚本"
        rm -f /etc/hotplug.d/iface/30-ssh-tunnels
        
        # 4. 删除监控脚本
        echo "删除监控脚本"
        rm -f /usr/bin/ssh-tunnels/monitor.sh
        rm -rf /usr/bin/ssh-tunnels
        
        # 5. 删除配置目录
        echo "删除配置目录"
        rm -rf /etc/ssh-tunnels
        
        # 6. 删除日志文件
        echo "删除日志文件"
        rm -rf /var/log/ssh-tunnels
        
        # 7. 删除 cron 任务
        echo "删除定时任务"
        sed -i '/ssh-tunnels\/monitor.sh/d' /etc/crontabs/root
        /etc/init.d/cron restart
        
        # 8. 删除持久化配置（如果存在）
        if [ -d "/overlay/etc/ssh-tunnels" ]; then
            echo "删除持久化配置"
            rm -rf /overlay/etc/ssh-tunnels
            sed -i '/ssh-tunnels/d' /etc/rc.local
        fi
        
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