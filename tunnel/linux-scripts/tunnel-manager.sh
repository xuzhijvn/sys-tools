#!/bin/bash

# SSH 隧道管理脚本 - Linux 版本
# 用途：管理多个 SSH 隧道连接
# 作者：xuzhijvn
# 版本：1.0.0

# 检查 root 权限
if [ "$(id -u)" != "0" ]; then
    echo "错误: 请使用 root 用户或 sudo 执行此脚本"
    exit 1
fi

# 固定系统目录
TUNNEL_CONFIG_DIR="/etc/ssh-tunnels/configs"
LOG_DIR="/var/log/ssh-tunnels"
KEYS_DIR="/etc/ssh-tunnels/keys"

# 创建必要的目录
mkdir -p "$TUNNEL_CONFIG_DIR"
mkdir -p "$LOG_DIR"
mkdir -p "$KEYS_DIR"

create_systemd_service() {
    cat > "/etc/systemd/system/ssh-tunnel@.service" << EOF
[Unit]
Description=SSH Tunnel Service for %i
After=network.target

[Service]
Type=simple
EnvironmentFile=/etc/ssh-tunnels/configs/%i.conf

ExecStart=/bin/bash -c 'echo "Starting SSH tunnel with following parameters:" && \
    echo "User: \$(id)" && \
    echo "Working directory: \$(pwd)" && \
    echo "SSH_KEY: \${SSH_KEY}" && \
    echo "SSH_SERVER: \${SSH_SERVER}" && \
    echo "Command to execute:" && \
    if [ "\${TUNNEL_MODE}" = "D" ]; then \
        exec ssh -N \
        -o "ServerAliveInterval=30" \
        -o "ServerAliveCountMax=3" \
        -o "ExitOnForwardFailure=yes" \
        -o "TCPKeepAlive=yes" \
        -o "StrictHostKeyChecking=no" \
        -o "UserKnownHostsFile=/dev/null" \
        -o "BatchMode=yes" \
        -o "ConnectTimeout=10" \
        -o "ConnectionAttempts=3" \
        -o "IdentityFile=\${SSH_KEY}" \
        \${EXTRA_SSH_OPTS} \
        -D \${LOCAL_PORT} \
        \${SSH_SERVER}; \
    else \
        exec ssh -N \
        -o "ServerAliveInterval=30" \
        -o "ServerAliveCountMax=3" \
        -o "ExitOnForwardFailure=yes" \
        -o "TCPKeepAlive=yes" \
        -o "StrictHostKeyChecking=no" \
        -o "UserKnownHostsFile=/dev/null" \
        -o "BatchMode=yes" \
        -o "ConnectTimeout=10" \
        -o "ConnectionAttempts=3" \
        -o "IdentityFile=\${SSH_KEY}" \
        \${EXTRA_SSH_OPTS} \
        -\${TUNNEL_MODE} \${LOCAL_PORT}:\${REMOTE_HOST}:\${REMOTE_PORT} \
        \${SSH_SERVER}; \
    fi'

Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF
}

create_monitor_service() {
    # 创建系统级监控服务
    cat > "/etc/systemd/system/tunnel-monitor.service" << 'EOF'
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
    cat > "/usr/local/bin/tunnel-monitor.sh" << EOF
#!/bin/bash

LOG_FILE="/var/log/ssh-tunnels/monitor.log"
CONFIG_DIR="/etc/ssh-tunnels/configs"
CHECK_INTERVAL=30
MAX_FAILURES=3
declare -A FAILURE_COUNTS

log() {
    local message="\$1"
    echo "\$(date '+%Y-%m-%d %H:%M:%S') - \$message" >> "\$LOG_FILE"
    logger -t ssh-tunnels "\$message"
}

check_tunnel() {
    local config="\$1"
    # shellcheck disable=SC1090
    source "\$config"

    if ! netstat -tln | grep -q ":\${LOCAL_PORT}"; then
        FAILURE_COUNTS["\$TUNNEL_NAME"]=\$((FAILURE_COUNTS["\$TUNNEL_NAME"] + 1))
        log "Tunnel \$TUNNEL_NAME (port \$LOCAL_PORT) check failed. Failure count: \${FAILURE_COUNTS[\$TUNNEL_NAME]}"

        if [ "\${FAILURE_COUNTS[\$TUNNEL_NAME]}" -ge "\$MAX_FAILURES" ]; then
            log "Max failures reached for \$TUNNEL_NAME. Restarting tunnel..."
            systemctl restart "ssh-tunnel@\${TUNNEL_NAME}"
            FAILURE_COUNTS["\$TUNNEL_NAME"]=0

            sleep 5
            if netstat -tln | grep -q ":\${LOCAL_PORT}"; then
                log "Tunnel \$TUNNEL_NAME restored successfully"
            else
                log "Failed to restore tunnel \$TUNNEL_NAME"
            fi
        fi
    else
        FAILURE_COUNTS["\$TUNNEL_NAME"]=0
    fi
}

# 确保日志目录存在
mkdir -p "\$(dirname "\$LOG_FILE")"

# 记录启动信息
log "SSH tunnel monitor started"

# 主循环
while true; do
    for conf in "\$CONFIG_DIR"/*.conf; do
        [ -f "\$conf" ] && check_tunnel "\$conf"
    done
    sleep "\$CHECK_INTERVAL"
done
EOF

    chmod +x "/usr/local/bin/tunnel-monitor.sh"
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
    if [ ! -f "/etc/systemd/system/ssh-tunnel@.service" ]; then
        echo "错误: systemd 服务模板不存在"
        status=1
    fi

    if [ ! -f "/etc/systemd/system/tunnel-monitor.service" ]; then
        echo "错误: 监控服务不存在"
        status=1
    fi

    if [ ! -x "/usr/local/bin/tunnel-monitor.sh" ]; then
        echo "错误: 监控脚本不存在或不可执行"
        status=1
    fi

    # 检查服务状态
    if ! systemctl is-enabled tunnel-monitor >/dev/null 2>&1; then
        echo "错误: tunnel-monitor 服务未启用"
        status=1
    fi

    return $status
}

setup_tunnel() {
    local name="$1"
    local mode="$2"          # 隧道模式 (L/R/D)
    local local_port="$3"

    # 动态转发模式下，后面的参数顺序要调整
    if [ "$mode" = "D" ]; then
        local ssh_server="$4"
        local ssh_key="$5"
        local extra_opts="${6:-}"
        # 动态模式不需要这两个参数
        local remote_host=""
        local remote_port=""
    else
        local remote_host="$4"   # 本地/远程转发需要这两个参数
        local remote_port="$5"
        local ssh_server="$6"
        local ssh_key="$7"
        local extra_opts="${8:-}"
    fi

    # 验证模式
    case "$mode" in
        L|R|D) ;;
        *) echo "Invalid mode. Use L for local, R for remote, or D for dynamic forwarding."; return 1 ;;
    esac

    # 检查 SSH 密钥文件
    if [ ! -f "$ssh_key" ]; then
        echo "错误: SSH 密钥文件 '$ssh_key' 不存在"
        echo "请先生成 SSH 密钥对，例如："
        echo "  ssh-keygen -t ed25519 -f $ssh_key"
        return 1
    fi

    # 检查 SSH 密钥权限
    local key_perms=$(stat -c %a "$ssh_key")
    if [ "$key_perms" != "600" ]; then
        echo "警告: SSH 密钥文件权限不正确 (当前: $key_perms, 应为: 600)"
        echo "正在修复权限..."
        chmod 600 "$ssh_key"
    fi

    # 检查公钥文件
    if [ ! -f "${ssh_key}.pub" ]; then
        echo "警告: 未找到公钥文件 '${ssh_key}.pub'"
        echo "如果目标服务器需要公钥认证，请确保已添加公钥"
    fi

    # 创建隧道配置文件
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

    # 设置配置文件权限
    chmod 600 "${TUNNEL_CONFIG_DIR}/${name}.conf"

    # 重新加载并启动服务
    systemctl daemon-reload
    systemctl enable "ssh-tunnel@${name}"
    systemctl restart "ssh-tunnel@${name}"
}

test_tunnel() {
    local test_name="test_tunnel"
    local test_port_l="12345"
    local test_port_r="12346"
    local test_port_d="12347"
    local current_user=$(who am i | awk '{print $1}')
    echo "开始测试 SSH 隧道管理系统..."

    # 确保在安全的目录中执行
    cd /tmp || exit 1

    # 1. 生成测试密钥
    echo "1. 生成测试密钥..."
    if [ ! -f "$KEYS_DIR/test_key" ]; then
        ssh-keygen -t ed25519 -f "$KEYS_DIR/test_key" -N "" || {
            echo "❌ 生成测试密钥失败"
            return 1
        }
        echo "✓ 生成测试密钥成功"
    else
        echo "✓ 测试密钥已存在"
    fi

    # 确保测试密钥被正确添加到 authorized_keys
    local user_home
    if [ "$current_user" = "root" ]; then
        user_home="/root"
    else
        user_home="/home/$current_user"
    fi

    # 设置 SSH 目录和权限
    mkdir -p "$user_home/.ssh"
    chmod 700 "$user_home/.ssh"
    touch "$user_home/.ssh/authorized_keys"
    chmod 600 "$user_home/.ssh/authorized_keys"

    # 添加测试密钥（如果不存在）
    if ! grep -qf "$KEYS_DIR/test_key.pub" "$user_home/.ssh/authorized_keys"; then
        cat "$KEYS_DIR/test_key.pub" >> "$user_home/.ssh/authorized_keys"
    fi

    # 确保所有权正确
    chown -R "$current_user:$current_user" "$user_home/.ssh"

    echo "✓ 已添加测试密钥到 authorized_keys"

    # 测试 SSH 连接
    echo "测试 SSH 连接..."
    if ! ssh -i "$KEYS_DIR/test_key" -o "StrictHostKeyChecking=no" "${current_user}@localhost" "echo 测试成功" >/dev/null 2>&1; then
        echo "❌ SSH 连接测试失败"
        echo "请检查："
        echo "1. SSH 服务是否运行："
        echo "   systemctl status sshd"
        echo "2. 是否允许 root 用户通过密钥登录："
        echo "   grep PermitRootLogin /etc/ssh/sshd_config"
        echo "3. 是否允许公钥认证："
        echo "   grep PubkeyAuthentication /etc/ssh/sshd_config"
        return 1
    fi
    echo "✓ SSH 连接测试成功"

    # 2. 测试本地转发模式
    echo "2. 测试本地转发模式 (-L)..."
    setup_tunnel "${test_name}_l" "L" "$test_port_l" "localhost" "22" "${current_user}@localhost" "$KEYS_DIR/test_key" || {
        echo "❌ 添加本地转发隧道失败"
        return 1
    }
    echo "✓ 添加本地转发隧道成功"

    # 等待本地转发隧道建立
    for i in $(seq 1 10); do
        if netstat -tln | grep -q ":$test_port_l"; then
            echo "✓ 本地转发隧道端口正常监听"
            break
        fi
        if [ $i -eq 10 ]; then
            echo "❌ 本地转发隧道端口未监听"
            echo "调试信息："
            systemctl status "ssh-tunnel@${test_name}_l"
            journalctl -u "ssh-tunnel@${test_name}_l" --no-pager -n 20
            echo "请检查："
            echo "1. SSH 服务是否运行"
            echo "2. 是否允许 root 登录"
            echo "3. 是否允许公钥认证"
            echo "4. authorized_keys 文件权限是否正确"
            return 1
        fi
        echo "  等待端口监听 ($i/10)..."
        sleep 1
    done

    # 3. 测试远程转发模式
    echo "3. 测试远程转发模式 (-R)..."
    setup_tunnel "${test_name}_r" "R" "$test_port_r" "localhost" "80" "${current_user}@localhost" "$KEYS_DIR/test_key" || {
        echo "❌ 添加远程转发隧道失败"
        return 1
    }
    echo "✓ 添加远程转发隧道成功"

    # 等待远程转发隧道建立
    for i in $(seq 1 10); do
        if netstat -tln | grep -q ":$test_port_r"; then
            echo "✓ 远程转发隧道端口正常监听"
            break
        fi
        if [ $i -eq 10 ]; then
            echo "❌ 远程转发隧道端口未监听"
            if [ "$(id -u)" = "0" ]; then
                systemctl status "ssh-tunnel@${test_name}_r"
            else
                systemctl --user status "ssh-tunnel@${test_name}_r"
            fi
            return 1
        fi
        echo "  等待端口监听 ($i/10)..."
        sleep 1
    done

    # 4. 测试动态转发模式
    echo "4. 测试动态转发模式 (-D)..."
    setup_tunnel "${test_name}_d" "D" "$test_port_d" "${current_user}@localhost" "$KEYS_DIR/test_key" || {
        echo "❌ 添加动态转发隧道失败"
        return 1
    }
    echo "✓ 添加动态转发隧道成功"

    # 等待动态转发隧道建立
    for i in $(seq 1 10); do
        if netstat -tln | grep -q ":$test_port_d"; then
            echo "✓ 动态转发隧道端口正常监听"
            break
        fi
        if [ $i -eq 10 ]; then
            echo "❌ 动态转发隧道端口未监听"
            systemctl status "ssh-tunnel@${test_name}_d"
            return 1
        fi
        echo "  等待端口监听 ($i/10)..."
        sleep 1
    done

    # 5. 测试停止所有隧道
    echo "5. 测试停止所有隧道..."
    tunnel-manager.sh stop
    sleep 2
    local failed=0
    for port in "$test_port_l" "$test_port_r" "$test_port_d"; do
        if netstat -tln | grep -q ":$port"; then
            echo "❌ 端口 $port 仍在监听"
            failed=1
        fi
    done
    [ $failed -eq 0 ] && echo "✓ 所有隧道成功停止"

    # 6. 测试重启所有隧道
    echo "6. 测试重启所有隧道..."
    tunnel-manager.sh restart
    sleep 2
    failed=0
    for port in "$test_port_l" "$test_port_r" "$test_port_d"; do
        if ! netstat -tln | grep -q ":$port"; then
            echo "❌ 端口 $port 未监听"
            failed=1
        fi
    done
    [ $failed -eq 0 ] && echo "✓ 所有隧道成功重启"

    # 7. 清理测试隧道
    echo "7. 清理测试隧道..."
    for suffix in l r d; do
        tunnel-manager.sh remove "${test_name}_${suffix}"
    done
    echo "✓ 测试隧道已清理"

    # 8. 清理测试密钥
    echo "8. 清理测试密钥..."
    rm -f "$KEYS_DIR/test_key" "$KEYS_DIR/test_key.pub"
    echo "✓ 测试密钥已清理"

    echo
    echo "所有测试完成！✓"
    return 0
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
        systemctl daemon-reload
        rm -f "${TUNNEL_CONFIG_DIR}/${name}.conf"
        ;;
    list)
        for conf in "$TUNNEL_CONFIG_DIR"/*.conf; do
            if [ -f "$conf" ]; then
                # shellcheck disable=SC1090
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
                    # shellcheck disable=SC1090
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
                    # shellcheck disable=SC1090
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
        echo "开始设置 SSH 隧道管理系统..."

        create_systemd_service
        create_monitor_service
        create_monitor_script

        systemctl daemon-reload
        systemctl enable tunnel-monitor
        systemctl start tunnel-monitor

        if check_setup; then
            echo "✓ 创建目录结构成功"
            echo "✓ 创建 systemd 服务文件成功"
            echo "✓ 创建监控脚本成功"
            echo "✓ 重新加载 systemd 配置成功"
            echo "✓ 启用监控服务成功"
            echo "✓ 启动监控服务成功"
            echo
            echo "SSH 隧道管理系统设置完成！"
            echo "您现在可以使用以下命令添加隧道："
            echo "  本地/远程转发模式:"
            echo "    $0 add <name> <L|R> <local_port> <remote_host> <remote_port> <ssh_server> <ssh_key> [extra_opts]"
            echo "  动态转发模式:"
            echo "    $0 add <name> D <local_port> <ssh_server> <ssh_key> [extra_opts]"
            echo
            echo "  $0 remove <name>"
            echo "  $0 list"
            echo "  $0 setup"
            echo "  $0 check           # 检查系统配置状态"
            echo "  $0 test            # 测试系统功能"
            echo "  $0 status"
            echo "  $0 stop [name]      # 停止所有隧道或指定隧道"
            echo "  $0 restart [name]   # 重启所有隧道或指定隧道"
            echo "  $0 clean [-f]       # 清理隧道及相关文件（-f 强制删除所有文件，默认保留密钥）"
        else
            echo
            echo "设置过程中发生错误，请检查以上错误信息并修复。"
            exit 1
        fi
        ;;
    status)
        for conf in "$TUNNEL_CONFIG_DIR"/*.conf; do
            if [ -f "$conf" ]; then
                # shellcheck disable=SC1090
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
        # 检查参数
        delete_all=0
        if [ "$2" = "-f" ]; then
            delete_all=1
        fi

        echo "正在清理 SSH 隧道及相关文件..."

        # 确保在安全目录中执行
        cd / || exit 1

        # 1. 停止并禁用所有隧道服务
        for conf in "$TUNNEL_CONFIG_DIR"/*.conf; do
            if [ -f "$conf" ]; then
                # shellcheck disable=SC1090
                source "$conf"
                systemctl stop "ssh-tunnel@${TUNNEL_NAME}" 2>/dev/null || true
                systemctl disable "ssh-tunnel@${TUNNEL_NAME}" 2>/dev/null || true
            fi
        done

        # 2. 停止并禁用监控服务
        systemctl stop tunnel-monitor 2>/dev/null || true
        systemctl disable tunnel-monitor 2>/dev/null || true

        # 3. 删除服务文件
        rm -f /etc/systemd/system/ssh-tunnel@.service
        rm -f /etc/systemd/system/tunnel-monitor.service
        systemctl daemon-reload

        # 4. 删除脚本文件
        rm -f /usr/local/bin/tunnel-monitor.sh

        if [ "$delete_all" = "1" ]; then
            # 删除所有���件
            rm -rf /etc/ssh-tunnels
            rm -rf /var/log/ssh-tunnels
            echo "✓ 所有文件已删除（包括密钥）"
        else
            # 保留密钥
            rm -rf /etc/ssh-tunnels/configs
            rm -rf /var/log/ssh-tunnels

            echo "✓ 配置和日志已删除，SSH 密钥已保留在 $KEYS_DIR"
        fi

        echo "清理完成"
        ;;
    check)
        echo "检查 SSH 隧道管理系统配置..."
        echo
        echo "当前使用的系统目录："
        echo "  配置目录: $TUNNEL_CONFIG_DIR"
        echo "  日志目录: $LOG_DIR"
        echo "  密钥目录: $KEYS_DIR"
        echo "  服务目录: /etc/systemd/system"
        echo "  脚本目录: /usr/local/bin"
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
        echo "  本地/远程转发模式:"
        echo "    $0 add <name> <L|R> <local_port> <remote_host> <remote_port> <ssh_server> <ssh_key> [extra_opts]"
        echo "  动态转发模式:"
        echo "    $0 add <name> D <local_port> <ssh_server> <ssh_key> [extra_opts]"
        echo
        echo "  $0 remove <name>"
        echo "  $0 list"
        echo "  $0 setup"
        echo "  $0 check           # 检查系统配置状态"
        echo "  $0 test            # 测试系统功能"
        echo "  $0 status"
        echo "  $0 stop [name]      # 停止所有隧道或指定隧道"
        echo "  $0 restart [name]   # 重启所有隧道或指定隧道"
        echo "  $0 clean [-f]       # 清理隧道及相关文件（-f 强制删除所有文件，默认保留密钥）"
        ;;
esac