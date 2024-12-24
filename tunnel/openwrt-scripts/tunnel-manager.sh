#!/bin/sh

# SSH 隧道管理脚本 - OpenWRT 版本
# 用途：管理多个 SSH 隧道连接
# 作者：xuzhijvn
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
NAME=ssh-tunnels
EXTRA_COMMANDS="status check restart_tunnel stop_tunnel"
EXTRA_HELP="        restart_tunnel     Restart a specific tunnel
        stop_tunnel        Stop a specific tunnel"

start_tunnel() {
    local config="$1"
    . "$config"
    
    # 添加调试日志
    logger -t ssh-tunnels "Starting tunnel: $TUNNEL_NAME"
    
    # 启动 SSH 隧道
    case "$TUNNEL_MODE" in
        L)
            ssh -N -g -L "${LOCAL_PORT}:${REMOTE_HOST}:${REMOTE_PORT}" \
                -o "ServerAliveInterval=30" \
                -o "ServerAliveCountMax=3" \
                -o "ExitOnForwardFailure=yes" \
                -o "TCPKeepAlive=yes" \
                -o "StrictHostKeyChecking=no" \
                -o "IdentityFile=${SSH_KEY}" \
                ${SSH_SERVER} >> /var/log/ssh-tunnels/${TUNNEL_NAME}.log 2>&1 &
            
            echo $! > "/var/run/ssh-tunnel-${TUNNEL_NAME}.pid"
            ;;
        R)
            ssh -N -R "${LOCAL_PORT}:${REMOTE_HOST}:${REMOTE_PORT}" \
                -o "ServerAliveInterval=30" \
                -o "ServerAliveCountMax=3" \
                -o "ExitOnForwardFailure=yes" \
                -o "TCPKeepAlive=yes" \
                -o "StrictHostKeyChecking=no" \
                -o "IdentityFile=${SSH_KEY}" \
                ${SSH_SERVER} >> /var/log/ssh-tunnels/${TUNNEL_NAME}.log 2>&1 &
            
            echo $! > "/var/run/ssh-tunnel-${TUNNEL_NAME}.pid"
            ;;
        D)
            ssh -N -D "${LOCAL_PORT}" \
                -o "ServerAliveInterval=30" \
                -o "ServerAliveCountMax=3" \
                -o "ExitOnForwardFailure=yes" \
                -o "TCPKeepAlive=yes" \
                -o "StrictHostKeyChecking=no" \
                -o "IdentityFile=${SSH_KEY}" \
                ${SSH_SERVER} >> /var/log/ssh-tunnels/${TUNNEL_NAME}.log 2>&1 &
            
            echo $! > "/var/run/ssh-tunnel-${TUNNEL_NAME}.pid"
            ;;
    esac
    
    logger -t ssh-tunnels "Tunnel $TUNNEL_NAME started"
}

stop_tunnel() {
    local tunnel_name="$1"
    local pid_file="/var/run/ssh-tunnel-${tunnel_name}.pid"
    
    if [ -f "$pid_file" ]; then
        kill $(cat "$pid_file") 2>/dev/null
        rm -f "$pid_file"
    fi
}

restart_tunnel() {
    local tunnel_name="$1"
    local config="/etc/ssh-tunnels/configs/${tunnel_name}.conf"
    
    if [ -f "$config" ]; then
        stop_tunnel "$tunnel_name"
        start_tunnel "$config"
    else
        echo "Tunnel configuration not found: $tunnel_name"
        return 1
    fi
}

start() {
    # 确保日志目录存在
    mkdir -p /var/log/ssh-tunnels
    
    # 启动监控脚本
    /usr/bin/ssh-tunnels/monitor.sh >> /var/log/ssh-tunnels/monitor.log 2>&1 &
    local monitor_pid=$!
    
    # 等待确认监控脚本启动
    sleep 2
    if kill -0 $monitor_pid 2>/dev/null; then
        echo $monitor_pid > "/var/run/ssh-tunnels-monitor.pid"
        logger -t ssh-tunnels "Monitor script started successfully (PID: $monitor_pid)"
    else
        logger -t ssh-tunnels "Failed to start monitor script"
        return 1
    fi
    
    # 启动所有隧道
    for config in /etc/ssh-tunnels/configs/*.conf; do
        [ -f "$config" ] && start_tunnel "$config"
    done
}

stop() {
    # 停止监控脚本
    [ -f "/var/run/ssh-tunnels-monitor.pid" ] && {
        kill $(cat "/var/run/ssh-tunnels-monitor.pid") 2>/dev/null
        rm -f "/var/run/ssh-tunnels-monitor.pid"
    }
    
    # 停止所有隧道
    for pid_file in /var/run/ssh-tunnel-*.pid; do
        [ -f "$pid_file" ] && {
            kill $(cat "$pid_file") 2>/dev/null
            rm -f "$pid_file"
        }
    done
}

status() {
    local running=0
    # 检查监控脚本
    if [ -f "/var/run/ssh-tunnels-monitor.pid" ] && kill -0 $(cat "/var/run/ssh-tunnels-monitor.pid") 2>/dev/null; then
        echo "Monitor script is running"
        running=1
    else
        echo "Monitor script is not running"
    fi
    
    # 检查所有隧道
    for pid_file in /var/run/ssh-tunnel-*.pid; do
        if [ -f "$pid_file" ]; then
            name=$(basename "$pid_file" | sed 's/ssh-tunnel-\(.*\).pid/\1/')
            if kill -0 $(cat "$pid_file") 2>/dev/null; then
                echo "Tunnel $name is running"
                running=1
            else
                echo "Tunnel $name is not running"
            fi
        fi
    done
    
    [ $running -eq 1 ] && return 0 || return 1
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
    # 确保目录存在
    mkdir -p /usr/bin/ssh-tunnels
    
    # 先删除已存在的监控脚本
    rm -f /usr/bin/ssh-tunnels/monitor.sh

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

check_setup() {
    local status=0
    
    # 检查必要的目录
    for dir in "$TUNNEL_CONFIG_DIR" "$LOG_DIR" "$KEYS_DIR"; do
        if [ ! -d "$dir" ]; then
            echo "错误: 目录 $dir 不存在"
            status=1
        fi
    done
    
    # 检查必要的脚本和服务
    if [ ! -f "/etc/init.d/ssh-tunnels" ]; then
        echo "错误: init.d 脚本不存在"
        status=1
    fi
    
    if [ ! -x "/usr/bin/ssh-tunnels/monitor.sh" ]; then
        echo "错误: 监控脚本不存在或不可执行"
        status=1
    fi
    
    # 检查服务状态
    if ! /etc/init.d/ssh-tunnels enabled; then
        echo "错误: ssh-tunnels 服务未启用"
        status=1
    fi
    
    return $status
}

test_tunnel() {
    local test_name="test_tunnel"
    local test_port="12345"
    echo "开始测试 SSH 隧道管理系统..."
    
    # 1. 确保 Dropbear 在运行
    echo "1. 检查 Dropbear 服务..."
    if ! /etc/init.d/dropbear status >/dev/null 2>&1; then
        echo "启动 Dropbear 服务..."
        /etc/init.d/dropbear start
        sleep 2
    fi
    
    # 获取 Dropbear 监听的 IP 地址
    local ssh_ip=$(netstat -tln | grep ':22[^0-9]' | awk '{print $4}' | cut -d: -f1)
    if [ -z "$ssh_ip" ]; then
        echo "❌ 无法获取 Dropbear 监听地址"
        return 1
    fi
    echo "✓ Dropbear 服务正常运行在 $ssh_ip:22"
    
    # 2. 确保监控脚本在运行
    echo "2. 检查监控脚本..."
    if ! pgrep -f "/usr/bin/ssh-tunnels/monitor.sh" >/dev/null; then
        echo "启动监控脚本..."
        /etc/init.d/ssh-tunnels start
        sleep 2
        if ! pgrep -f "/usr/bin/ssh-tunnels/monitor.sh" >/dev/null; then
            echo "❌ 监控脚本启动失败"
            return 1
        fi
    fi
    echo "✓ 监控脚本正在运行"
    
    # 3. 生成测试密钥
    echo "3. 生成测试密钥..."
    if [ ! -f "/etc/ssh-tunnels/keys/test_key" ]; then
        ssh-keygen -t ed25519 -f /etc/ssh-tunnels/keys/test_key -N "" || {
            echo "❌ 生成测试密钥失败"
            return 1
        }
        
        # 添加到本地的 authorized_keys
        mkdir -p /etc/dropbear
        chmod 700 /etc/dropbear
        cat /etc/ssh-tunnels/keys/test_key.pub >> /etc/dropbear/authorized_keys
        chmod 600 /etc/dropbear/authorized_keys
        
        echo "✓ 生成测试密钥并添加到 authorized_keys 成功"
    else
        echo "✓ 测试密钥已存在"
    fi
    
    # 4. 测试添加隧道
    echo "4. 测试添加隧道..."
    setup_tunnel "$test_name" "L" "$test_port" "$ssh_ip" "22" "root@$ssh_ip" "/etc/ssh-tunnels/keys/test_key" || {
        echo "❌ 添加隧道失败"
        return 1
    }
    echo "✓ 添加隧道成功"
    
    # 5. 等待隧道建立
    echo "5. 等待隧道建立..."
    for i in $(seq 1 10); do
        if netstat -tln | grep -q ":$test_port"; then
            echo "✓ 隧道端口正常监听"
            break
        fi
        if [ $i -eq 10 ]; then
            echo "❌ 隧道端口未监听"
            # 显示详细错误信息
            echo "调试信息："
            /etc/init.d/ssh-tunnels status
            logread | grep "ssh-tunnels" | tail -n 20
            return 1
        fi
        echo "  等待端口监听 ($i/10)..."
        sleep 1
    done
    
    # 6. 测试停止隧道
    echo "6. 测试停止隧道..."
    /etc/init.d/ssh-tunnels stop_tunnel "$test_name"
    sleep 2
    if ! netstat -tln | grep -q ":$test_port"; then
        echo "✓ 隧道成功停止"
    else
        echo "❌ 隧道停止失败"
        return 1
    fi
    
    # 7. 测试重启隧道
    echo "7. 测试重启隧道..."
    /etc/init.d/ssh-tunnels restart_tunnel "$test_name"
    for i in $(seq 1 10); do
        if netstat -tln | grep -q ":$test_port"; then
            echo "✓ 隧道成功重启"
            break
        fi
        if [ $i -eq 10 ]; then
            echo "❌ 隧道重启失败"
            return 1
        fi
        echo "  等待端口监听 ($i/10)..."
        sleep 1
    done
    
    # 8. 测试删除隧道
    echo "8. 测试删除隧道..."
    tunnel-manager.sh remove "$test_name"
    if [ ! -f "${TUNNEL_CONFIG_DIR}/${test_name}.conf" ]; then
        echo "✓ 隧道成功删除"
    else
        echo "❌ 隧道删除失败"
        return 1
    fi
    
    # 9. 清理测试密钥
    echo "9. 清理测试密钥..."
    rm -f "/etc/ssh-tunnels/keys/test_key" "/etc/ssh-tunnels/keys/test_key.pub"
    echo "✓ 测试密钥已清理"
    
    echo
    echo "所有测试完成！✓"
    return 0
}

# 添加一个辅助函数来确保进程停止
ensure_process_stopped() {
    local pattern="$1"
    local max_attempts=5
    local attempt=1
    
    while [ $attempt -le $max_attempts ]; do
        if ! pgrep -f "$pattern" >/dev/null 2>&1; then
            return 0
        fi
        echo "尝试停止进程 ($attempt/$max_attempts)..."
        pkill -f "$pattern" 2>/dev/null
        [ $attempt -eq $max_attempts ] && pkill -9 -f "$pattern" 2>/dev/null
        attempt=$((attempt + 1))
        sleep 1
    done
    
    # 检查是否还有进程存在
    if pgrep -f "$pattern" >/dev/null 2>&1; then
        echo "无法停止进程: $pattern"
        return 1
    fi
    return 0
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
        echo "开始设置 SSH 隧道管理系统..."
        
        # 1. 确保旧的服务和进程已停止
        echo "停止现有服务和进程..."
        /etc/init.d/ssh-tunnels stop 2>/dev/null
        /etc/init.d/ssh-tunnels disable 2>/dev/null
        ensure_process_stopped "/usr/bin/ssh-tunnels/monitor.sh" || {
            echo "无法停止监控脚本，请手动检查进程"
            exit 1
        }
        
        # 2. 清理旧文件
        echo "清理旧文件..."
        rm -f /etc/init.d/ssh-tunnels
        rm -f /usr/bin/ssh-tunnels/monitor.sh
        
        # 3. 创建新的服务和脚本
        echo "创建新的服务和脚本..."
        create_init_script
        create_monitor_script
        
        # 4. 添加系统级监控
        echo "添加系统级监控..."
        echo '*/5 * * * * if ! pgrep -f "/usr/bin/ssh-tunnels/monitor.sh" >/dev/null; then /etc/init.d/ssh-tunnels start; fi' >> /etc/crontabs/root
        /etc/init.d/cron restart
        
        # 5. 启动服务
        echo "启动服务..."
        /etc/init.d/ssh-tunnels enable
        /etc/init.d/ssh-tunnels start
        
        # 6. 验证设置
        if check_setup; then
            echo "✓ 创建目录结构成功"
            echo "✓ 创建 init.d 服务脚本成功"
            echo "✓ 创建监控脚本成功"
            echo "✓ 添加系统级监控成功"
            echo "✓ 启用服务成功"
            echo "✓ 启动服务成功"
            echo
            echo "SSH 隧道管理系统设置完成！"
            echo "您现在可以使用以下命令添加隧道："
            echo "  $0 add <name> <mode> <local_port> <remote_host> <remote_port> <ssh_server> <ssh_key> [extra_opts]"
        else
            echo
            echo "设置过程中发生错误，请检查以上错误信息并修复。"
            exit 1
        fi
        ;;
    status)
        /etc/init.d/ssh-tunnels status
        ;;
    clean)
        echo "正在清理所有 SSH 隧道及相关文件..."
        
        # 1. 停止并禁用服务
        /etc/init.d/ssh-tunnels stop 2>/dev/null
        /etc/init.d/ssh-tunnels disable 2>/dev/null
        
        # 2. 确保监控脚本已停止
        pkill -f "/usr/bin/ssh-tunnels/monitor.sh" 2>/dev/null
        
        # 3. 删除系统级监控
        sed -i '/ssh-tunnels\/monitor.sh/d' /etc/crontabs/root
        /etc/init.d/cron restart
        
        # 4. 删除所有文件
        rm -f /etc/init.d/ssh-tunnels
        rm -rf /usr/bin/ssh-tunnels
        rm -rf /etc/ssh-tunnels
        rm -rf /var/log/ssh-tunnels
        
        echo "清理完成"
        ;;
    check)
        echo "检查 SSH 隧道管理系统配置..."

        echo
        echo "当前使用的系统目录："
        echo "  配置目录: $TUNNEL_CONFIG_DIR"
        echo "  日志目录: $LOG_DIR"
        echo "  密钥目录: $KEYS_DIR"
        echo "  服务目录: /etc/init.d"
        echo "  脚本目录: /usr/bin/ssh-tunnels"
        echo

        if check_setup; then
            echo "✓ 所有组件检查通过"
            echo "系统配置正常，可以正常使用。"
            exit 0
        else
            echo
            echo "系统配置存在问题，请根据以上错误信息进行修复。"
            echo "您可以尝试运行 '$0 setup' 重新安装。"
            exit 1
        fi
        
        return $status
        ;;
    test)
        if ! check_setup; then
            echo "系统配置检查失败，请先运行 setup"
            exit 1
        fi
        test_tunnel
        ;;
    *)
        echo "Usage:"
        echo "  $0 add <name> <mode> <local_port> <remote_host> <remote_port> <ssh_server> <ssh_key> [extra_opts]"
        echo "  $0 remove <name>"
        echo "  $0 list"
        echo "  $0 setup"
        echo "  $0 check           # 检查系统配置状态"
        echo "  $0 test            # 测试系统功能"
        echo "  $0 status"
        echo "  $0 stop [name]      # 停止所有隧道或指定隧道"
        echo "  $0 restart [name]   # 重启所有隧道或指定隧道"
        echo "  $0 clean           # 清理所有隧道及相关文件"
        ;;
esac 