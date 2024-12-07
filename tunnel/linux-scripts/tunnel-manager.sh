#!/bin/bash

# SSH 隧道管理脚本 - Linux 版本
# 用途：管理多个 SSH 隧道连接
# 作者：xuzhijvn
# 版本：1.0.0

# 添加权限检查函数
check_permissions() {
    # 如果是 root 用户，使用系统目录
    if [ "$(id -u)" = "0" ]; then
        TUNNEL_CONFIG_DIR="/etc/ssh-tunnels/configs"
        LOG_DIR="/var/log/ssh-tunnels"
        KEYS_DIR="/etc/ssh-tunnels/keys"
        SYSTEMD_DIR="/etc/systemd/system"
        SCRIPT_DIR="/usr/local/bin"
    else
        # 普通用户使用用户目录
        TUNNEL_CONFIG_DIR="$HOME/.config/ssh-tunnels/configs"
        LOG_DIR="$HOME/.config/ssh-tunnels/logs"
        KEYS_DIR="$HOME/.config/ssh-tunnels/keys"
        SYSTEMD_DIR="$HOME/.config/systemd/user"
        SCRIPT_DIR="$HOME/.local/bin"
    fi

    # 为所有用户创建必要的目录
    mkdir -p "$TUNNEL_CONFIG_DIR"
    mkdir -p "$LOG_DIR"
    mkdir -p "$KEYS_DIR"
    mkdir -p "$SYSTEMD_DIR"
    mkdir -p "$SCRIPT_DIR"

    # 设置适当的权限
    chmod 700 "$TUNNEL_CONFIG_DIR" "$LOG_DIR" "$KEYS_DIR"
}

# 在脚本开始时检查权限并设置目录
check_permissions

create_systemd_service() {
    if [ "$(id -u)" = "0" ]; then
        # 获取原始用户
        local original_user=$(who am i | awk '{print $1}')
        if [ -z "$original_user" ]; then
            original_user=$(logname 2>/dev/null)
        fi
        
        if [ -n "$original_user" ] && [ "$original_user" != "root" ]; then
            local user_id=$(id -u "$original_user")
            local group_id=$(id -g "$original_user")
            local user_home="/home/$original_user"
            
            cat > "/etc/systemd/system/ssh-tunnel@.service" << EOF
[Unit]
Description=SSH Tunnel Service for %i
After=network.target

[Service]
Type=simple
User=$original_user
Group=$original_user

# 环境变量设置
Environment="HOME=$user_home"
Environment="USER=$original_user"
Environment="LOGNAME=$original_user"
Environment="PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
Environment="SSH_AUTH_SOCK=/run/user/$user_id/keyring/ssh"
Environment="XDG_RUNTIME_DIR=/run/user/$user_id"
EnvironmentFile=/etc/ssh-tunnels/configs/%i.conf

# 工作目录设置
WorkingDirectory=$user_home

# 调试输出
StandardOutput=journal
StandardError=journal

ExecStart=/bin/bash -c '\
    echo "Starting SSH tunnel with following parameters:" && \
    echo "User: \$(id)" && \
    echo "Working directory: \$(pwd)" && \
    echo "SSH_KEY: \${SSH_KEY}" && \
    echo "SSH_SERVER: \${SSH_SERVER}" && \
    echo "Command to execute:" && \
    if [ "\${TUNNEL_MODE}" = "D" ]; then \
        echo "ssh -v -N -o ServerAliveInterval=30 -o ServerAliveCountMax=3 -o ExitOnForwardFailure=yes -o TCPKeepAlive=yes -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o BatchMode=yes -o ConnectTimeout=10 -o ConnectionAttempts=3 -o IdentityFile=\${SSH_KEY} \${EXTRA_SSH_OPTS} -D \${LOCAL_PORT} \${SSH_SERVER}" && \
        exec ssh -v -N \
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
        if [ "\${TUNNEL_MODE}" = "L" ]; then \
            echo "ssh -v -N -g -o ServerAliveInterval=30 -o ServerAliveCountMax=3 -o ExitOnForwardFailure=yes -o TCPKeepAlive=yes -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o BatchMode=yes -o ConnectTimeout=10 -o ConnectionAttempts=3 -o IdentityFile=\${SSH_KEY} \${EXTRA_SSH_OPTS} -\${TUNNEL_MODE} \${LOCAL_PORT}:\${REMOTE_HOST}:\${REMOTE_PORT} \${SSH_SERVER}" && \
            exec ssh -v -N -g \
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
        else \
            echo "ssh -v -N -o ServerAliveInterval=30 -o ServerAliveCountMax=3 -o ExitOnForwardFailure=yes -o TCPKeepAlive=yes -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o BatchMode=yes -o ConnectTimeout=10 -o ConnectionAttempts=3 -o IdentityFile=\${SSH_KEY} \${EXTRA_SSH_OPTS} -\${TUNNEL_MODE} \${LOCAL_PORT}:\${REMOTE_HOST}:\${REMOTE_PORT} \${SSH_SERVER}" && \
            exec ssh -v -N \
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
        fi \
    fi'

Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF
        else
            # 如果找不到原始用户，使用默认的服务文件
            cat > "/etc/systemd/system/ssh-tunnel@.service" << 'EOF'
[Unit]
Description=SSH Tunnel Service for %i
After=network.target

[Service]
Type=simple
Environment="SSH_AUTH_SOCK=/run/user/0/keyring/ssh"
EnvironmentFile=/etc/ssh-tunnels/configs/%i.conf

ExecStart=/bin/bash -c '\
    if [ "${TUNNEL_MODE}" = "D" ]; then \
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
        -o "IdentityFile=${SSH_KEY}" \
        ${EXTRA_SSH_OPTS} \
        -D ${LOCAL_PORT} \
        ${SSH_SERVER}; \
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
        -o "IdentityFile=${SSH_KEY}" \
        ${EXTRA_SSH_OPTS} \
        -${TUNNEL_MODE} ${LOCAL_PORT}:${REMOTE_HOST}:${REMOTE_PORT} \
        ${SSH_SERVER}; \
    fi'

Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF
        fi
    else
        # 普通用户的服务文件保持不变
        cat > "$SYSTEMD_DIR/ssh-tunnel@.service" << EOF
[Unit]
Description=SSH Tunnel Service for %i
After=network.target

[Service]
Type=simple
EnvironmentFile=${TUNNEL_CONFIG_DIR}/%i.conf

# 获取原始用户
User=%u
Group=%u

ExecStart=/bin/bash -c '\
    if [ "\${TUNNEL_MODE}" = "D" ]; then \
        exec ssh -N \
        -o "ServerAliveInterval=30" \
        -o "ServerAliveCountMax=3" \
        -o "ExitOnForwardFailure=yes" \
        -o "TCPKeepAlive=yes" \
        -o "StrictHostKeyChecking=no" \
        -o "UserKnownHostsFile=/dev/null" \
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
WantedBy=default.target
EOF
    fi
}

create_monitor_service() {
    if [ "$(id -u)" = "0" ]; then
        # root 用户创建系统服务
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
    else
        # 普通用户创建用户服务
        mkdir -p "$SYSTEMD_DIR"
        cat > "$SYSTEMD_DIR/tunnel-monitor.service" << 'EOF'
[Unit]
Description=SSH Tunnels Monitor
After=network.target

[Service]
Type=simple
ExecStart=%h/.local/bin/tunnel-monitor.sh
Restart=always
RestartSec=10

[Install]
WantedBy=default.target
EOF
    fi
}

create_monitor_script() {
    local script_path
    local config_dir
    local log_file
    
    if [ "$(id -u)" = "0" ]; then
        script_path="/usr/local/bin/tunnel-monitor.sh"
        config_dir="/etc/ssh-tunnels/configs"
        log_file="/var/log/ssh-tunnels/monitor.log"
    else
        script_path="$HOME/.local/bin/tunnel-monitor.sh"
        config_dir="$HOME/.config/ssh-tunnels/configs"
        log_file="$HOME/.config/ssh-tunnels/logs/monitor.log"
        mkdir -p "$(dirname "$log_file")"
    fi
    
    cat > "$script_path" << EOF
#!/bin/bash

LOG_FILE="$log_file"
CONFIG_DIR="$config_dir"
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
    source "\$config"
    
    if ! netstat -tln | grep -q ":\${LOCAL_PORT}"; then
        FAILURE_COUNTS["\$TUNNEL_NAME"]=\$((FAILURE_COUNTS["\$TUNNEL_NAME"] + 1))
        log "Tunnel \$TUNNEL_NAME (port \$LOCAL_PORT) check failed. Failure count: \${FAILURE_COUNTS[\$TUNNEL_NAME]}"
        
        if [ "\${FAILURE_COUNTS[\$TUNNEL_NAME]}" -ge "\$MAX_FAILURES" ]; then
            log "Max failures reached for \$TUNNEL_NAME. Restarting tunnel..."
            if [ "\$(id -u)" = "0" ]; then
                systemctl restart "ssh-tunnel@\${TUNNEL_NAME}"
            else
                systemctl --user restart "ssh-tunnel@\${TUNNEL_NAME}"
            fi
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
    for config in "\$CONFIG_DIR"/*.conf; do
        [ -f "\$config" ] && check_tunnel "\$config"
    done
    sleep "\$CHECK_INTERVAL"
done
EOF

    chmod +x "$script_path"
}

check_setup() {
    local status=0
    local systemd_dir
    local script_path
    local service_name
    
    if [ "$(id -u)" = "0" ]; then
        systemd_dir="/etc/systemd/system"
        script_path="/usr/local/bin/tunnel-monitor.sh"
        service_name="tunnel-monitor"
    else
        systemd_dir="$HOME/.config/systemd/user"
        script_path="$HOME/.local/bin/tunnel-monitor.sh"
        service_name="tunnel-monitor"
    fi
    
    # 检查必要的目录
    for dir in "$TUNNEL_CONFIG_DIR" "$LOG_DIR" "$KEYS_DIR"; do
        if [ ! -d "$dir" ]; then
            echo "错误: 目录 $dir 不存在"
            status=1
        fi
    done
    
    # 检查必要的脚本和服务
    if [ ! -f "$systemd_dir/ssh-tunnel@.service" ]; then
        echo "错误: systemd 服务模板不存在"
        status=1
    fi
    
    if [ ! -f "$systemd_dir/$service_name.service" ]; then
        echo "错误: 监控服务不存在"
        status=1
    fi
    
    if [ ! -x "$script_path" ]; then
        echo "错误: 监控脚本不存在或不可执行"
        status=1
    fi
    
    # 检查服务状态
    if [ "$(id -u)" = "0" ]; then
        if ! systemctl is-enabled "$service_name" >/dev/null 2>&1; then
            echo "错误: $service_name 服务未启用"
            status=1
        fi
    else
        if ! systemctl --user is-enabled "$service_name" >/dev/null 2>&1; then
            echo "错误: $service_name 服务未启用"
            status=1
        fi
    fi
    
    return $status
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
    
    # 如果是 root 用户，尝试获取原始用户
    if [ "$(id -u)" = "0" ]; then
        local original_user=$(who am i | awk '{print $1}')
        if [ -z "$original_user" ]; then
            original_user=$(logname 2>/dev/null)
        fi
        
        # 如果找到原始用户，使用其 .ssh 目录下的密钥
        if [ -n "$original_user" ] && [ "$original_user" != "root" ]; then
            local user_ssh_dir="/home/$original_user/.ssh"
            local user_key_file="$user_ssh_dir/$(basename "$ssh_key")"
            
            # 创建目录并设置权限
            install -d -m 700 -o "$original_user" -g "$original_user" "$user_ssh_dir"
            
            # 复制密钥文件并设置权限
            install -m 600 -o "$original_user" -g "$original_user" "$ssh_key" "$user_key_file"
            if [ -f "${ssh_key}.pub" ]; then
                install -m 644 -o "$original_user" -g "$original_user" "${ssh_key}.pub" "${user_key_file}.pub"
            fi
            
            # 添加公钥到 authorized_keys
            if [ -f "${ssh_key}.pub" ]; then
                local auth_keys_file="$user_ssh_dir/authorized_keys"
                touch "$auth_keys_file"
                chown "$original_user:$original_user" "$auth_keys_file"
                chmod 600 "$auth_keys_file"
                cat "${ssh_key}.pub" >> "$auth_keys_file"
            fi
            
            # 更新密钥路径和 SSH 服务器地址
            ssh_key="$user_key_file"
            ssh_server="${original_user}@${ssh_server#*@}"  # 替换用户名部分
        fi
    fi
    
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
    
    # 确保配置文件权限正确
    if [ "$(id -u)" = "0" ] && [ -n "$original_user" ] && [ "$original_user" != "root" ]; then
        chown "$original_user:$original_user" "${TUNNEL_CONFIG_DIR}/${name}.conf"
        chmod 600 "${TUNNEL_CONFIG_DIR}/${name}.conf"
        
        # 确保目录权限正确
        chown "$original_user:$original_user" "$TUNNEL_CONFIG_DIR"
        chmod 700 "$TUNNEL_CONFIG_DIR"
    fi
    
    if [ "$(id -u)" = "0" ]; then
        systemctl daemon-reload
        systemctl enable "ssh-tunnel@${name}"
        systemctl restart "ssh-tunnel@${name}"
    else
        systemctl --user daemon-reload
        systemctl --user enable "ssh-tunnel@${name}"
        systemctl --user restart "ssh-tunnel@${name}"
    fi
}

test_tunnel() {
    local test_name="test_tunnel"
    local test_port_l="12345"
    local test_port_r="12346"
    local test_port_d="12347"
    local current_user=$(whoami)
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
        # 添加到 authorized_keys
        mkdir -p ~/.ssh
        chmod 700 ~/.ssh
        cat "$KEYS_DIR/test_key.pub" >> ~/.ssh/authorized_keys
        chmod 600 ~/.ssh/authorized_keys
        echo "✓ 已添加测试密钥到 authorized_keys"
    else
        echo "✓ 测试密钥已存在"
    fi
    
    # 测试 SSH 连接
    echo "测试 SSH 连接..."
    if [ "$(id -u)" = "0" ]; then
        # root 用户：先尝试获取原始用户
        local test_user=$(who am i | awk '{print $1}')
        if [ -z "$test_user" ]; then
            test_user=$(logname 2>/dev/null)
        fi
        
        if [ -z "$test_user" ] || [ "$test_user" = "root" ]; then
            # 如果找不到原始用户或是直接用 root 登录，使用 root
            test_user="root"
            echo "使用 root 用户测试 SSH 连接..."
            if ! ssh -i "$KEYS_DIR/test_key" -o "StrictHostKeyChecking=no" "root@localhost" "echo 测试成功" >/dev/null 2>&1; then
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
        else
            # 使用找到的普通用户
            echo "使用用户 $test_user 测试 SSH 连接..."
            
            # 设置用户的 SSH 目录和文件
            local user_ssh_dir="/home/$test_user/.ssh"
            local user_key_file="$user_ssh_dir/test_key"
            
            # 创建目录并设置权限
            install -d -m 700 -o "$test_user" -g "$test_user" "$user_ssh_dir"
            
            # 复制密钥文件并设置权限
            install -m 600 -o "$test_user" -g "$test_user" "$KEYS_DIR/test_key" "$user_key_file"
            if [ -f "$KEYS_DIR/test_key.pub" ]; then
                install -m 644 -o "$test_user" -g "$test_user" "$KEYS_DIR/test_key.pub" "${user_key_file}.pub"
            fi
            
            # 添加公钥到 authorized_keys
            local auth_keys_file="$user_ssh_dir/authorized_keys"
            touch "$auth_keys_file"
            chown "$test_user:$test_user" "$auth_keys_file"
            chmod 600 "$auth_keys_file"
            cat "$KEYS_DIR/test_key.pub" >> "$auth_keys_file"
            
            if ! sudo -u "$test_user" ssh -i "$user_key_file" -o "StrictHostKeyChecking=no" "${test_user}@localhost" "echo 测试成功" >/dev/null 2>&1; then
                echo "❌ SSH 连接测试失败"
                echo "请检查："
                echo "1. SSH 服务是否运行："
                echo "   systemctl status sshd"
                echo "2. 是否允许公钥认证："
                echo "   grep PubkeyAuthentication /etc/ssh/sshd_config"
                echo "3. 用户 $test_user 是否有权限使用 SSH"
                return 1
            fi
            
            # 更新服务配置中的密钥路径
            SSH_KEY="$user_key_file"
        fi
    else
        # 普通用户：直接测试当前用户
        if ! ssh -i "$KEYS_DIR/test_key" -o "StrictHostKeyChecking=no" "${current_user}@localhost" "echo 测试成功" >/dev/null 2>&1; then
            echo "❌ SSH 连接测试失败"
            echo "请检查："
            echo "1. SSH 服务是否运行："
            echo "   systemctl status sshd"
            echo "2. 是否允许公钥认证："
            echo "   grep PubkeyAuthentication /etc/ssh/sshd_config"
            return 1
        fi
    fi
    echo "✓ SSH 连接测试成功"
    
    # 2. 测试本地转发模式
    echo "2. 测试本地转发模式 (-L)..."
    local ssh_server
    if [ "$(id -u)" = "0" ]; then
        if [ "$test_user" = "root" ]; then
            ssh_server="root@localhost"
        else
            ssh_server="${test_user}@localhost"
        fi
    else
        ssh_server="${current_user}@localhost"
    fi
    setup_tunnel "${test_name}_l" "L" "$test_port_l" "localhost" "22" "$ssh_server" "$KEYS_DIR/test_key" || {
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
            if [ "$(id -u)" = "0" ]; then
                systemctl status "ssh-tunnel@${test_name}_l"
                journalctl -u "ssh-tunnel@${test_name}_l" --no-pager -n 20
            else
                systemctl --user status "ssh-tunnel@${test_name}_l"
                journalctl --user -u "ssh-tunnel@${test_name}_l" --no-pager -n 20
            fi
            echo "请检查："
            echo "1. SSH 服务是否运行"
            echo "2. 是否允许本地 root 登录"
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
    setup_tunnel "${test_name}_d" "D" "$test_port_d" "-" "-" "${current_user}@localhost" "$KEYS_DIR/test_key" || {
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
            if [ "$(id -u)" = "0" ]; then
                systemctl status "ssh-tunnel@${test_name}_d"
            else
                systemctl --user status "ssh-tunnel@${test_name}_d"
            fi
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
        if [ "$(id -u)" = "0" ]; then
            systemctl stop "ssh-tunnel@${name}"
            systemctl disable "ssh-tunnel@${name}"
            systemctl daemon-reload
        else
            systemctl --user stop "ssh-tunnel@${name}"
            systemctl --user disable "ssh-tunnel@${name}"
            systemctl --user daemon-reload
        fi
        rm -f "${TUNNEL_CONFIG_DIR}/${name}.conf"
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
                    if [ "$(id -u)" = "0" ]; then
                        systemctl stop "ssh-tunnel@${TUNNEL_NAME}"
                    else
                        systemctl --user stop "ssh-tunnel@${TUNNEL_NAME}"
                    fi
                fi
            done
        else
            # 停止特定隧道
            if [ "$(id -u)" = "0" ]; then
                systemctl stop "ssh-tunnel@${name}"
            else
                systemctl --user stop "ssh-tunnel@${name}"
            fi
        fi
        ;;
    restart)
        name="$2"
        if [ -z "$name" ]; then
            # 重启所有隧道
            for conf in "$TUNNEL_CONFIG_DIR"/*.conf; do
                if [ -f "$conf" ]; then
                    source "$conf"
                    if [ "$(id -u)" = "0" ]; then
                        systemctl restart "ssh-tunnel@${TUNNEL_NAME}"
                    else
                        systemctl --user restart "ssh-tunnel@${TUNNEL_NAME}"
                    fi
                fi
            done
        else
            # 重启特定隧道
            if [ "$(id -u)" = "0" ]; then
                systemctl restart "ssh-tunnel@${name}"
            else
                systemctl --user restart "ssh-tunnel@${name}"
            fi
        fi
        ;;
    setup)
        echo "开始设置 SSH 隧道管理系统..."
        
        create_systemd_service
        create_monitor_service
        create_monitor_script
        
        if [ "$(id -u)" = "0" ]; then
            # root 用户使用系统级命令
            systemctl daemon-reload
            systemctl enable tunnel-monitor
            systemctl start tunnel-monitor
        else
            # 普通用户使用用户级命令
            # 检查是否是通过 SSH 或终端直接登录
            if [ -z "$XDG_RUNTIME_DIR" ]; then
                echo "错误: 未检测到用户会话环境"
                echo "请按照以下步骤操作："
                echo "1. 确保已安装必要的包："
                echo "   sudo yum install -y dbus systemd-devel"
                echo
                echo "2. 启用并启动 dbus 服务："
                echo "   sudo systemctl enable dbus"
                echo "   sudo systemctl start dbus"
                echo
                echo "3. 设置用户会话："
                echo "   loginctl enable-linger $(whoami)"
                echo
                echo "4. 注销并重新登录系统"
                echo
                echo "5. 然后重新运行此脚本"
                exit 1
            fi
            
            # 启用 lingering，确保用户退出后服务继续运行
            if ! loginctl show-user "$(whoami)" | grep -q "Linger=yes"; then
                echo "启用用户服务自动启动..."
                loginctl enable-linger "$(whoami)"
                sleep 2
            fi
            
            # 重新加载并启动服务
            echo "启动监控服务..."
            systemctl --user daemon-reload
            systemctl --user enable tunnel-monitor
            
            # 尝试启动服务
            if ! systemctl --user start tunnel-monitor; then
                echo "❌ 监控服务启动失败"
                echo "请按照以下步骤操作："
                echo "1. 确保已安装必要的包："
                echo "   sudo yum install -y dbus systemd-devel"
                echo
                echo "2. 启用并启动 dbus 服务："
                echo "   sudo systemctl enable dbus"
                echo "   sudo systemctl start dbus"
                echo
                echo "3. 设置用户会话："
                echo "   loginctl enable-linger $(whoami)"
                echo
                echo "4. 注销并重新登录系统"
                echo
                echo "5. 然后重新运行此脚本"
                exit 1
            fi
            echo "✓ 监控服务已启动"
        fi
        
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
            echo "  $0 add <name> <mode> <local_port> <remote_host> <remote_port> <ssh_server> <ssh_key> [extra_opts]"
        else
            echo
            echo "设置过程中发生错误，请检查以上错误信息并修复。"
            exit 1
        fi
        ;;
    status)
        for conf in "$TUNNEL_CONFIG_DIR"/*.conf; do
            if [ -f "$conf" ]; then
                source "$conf"
                echo -n "Tunnel $TUNNEL_NAME (port $LOCAL_PORT): "
                if [ "$(id -u)" = "0" ]; then
                    active_check="systemctl is-active ssh-tunnel@${TUNNEL_NAME}"
                else
                    active_check="systemctl --user is-active ssh-tunnel@${TUNNEL_NAME}"
                fi
                if $active_check >/dev/null 2>&1; then
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
        
        # 确保在安全目录中执行
        cd / || exit 1
        
        if [ "$(id -u)" = "0" ]; then
            # root 用户清理系统文件
            # 1. 停止并禁用所有隧道服务
            for conf in "$TUNNEL_CONFIG_DIR"/*.conf; do
                if [ -f "$conf" ]; then
                    source "$conf"
                    systemctl stop "ssh-tunnel@${TUNNEL_NAME}"
                    systemctl disable "ssh-tunnel@${TUNNEL_NAME}"
                fi
            done
            
            # 2. 停止并禁用监控服务
            systemctl stop tunnel-monitor
            systemctl disable tunnel-monitor
            
            # 3. 删除服务文件
            rm -f /etc/systemd/system/ssh-tunnel@.service
            rm -f /etc/systemd/system/tunnel-monitor.service
            systemctl daemon-reload
            
            # 4. 删除脚本文件
            rm -f /usr/local/bin/tunnel-monitor.sh
            
            # 5. 删除配置目录
            rm -rf /etc/ssh-tunnels
            
            # 6. 删除日志文件
            rm -rf /var/log/ssh-tunnels
        else
            # 普通用户清理用户文件
            # 1. 停止并禁用所有隧道服务
            for conf in "$TUNNEL_CONFIG_DIR"/*.conf; do
                if [ -f "$conf" ]; then
                    source "$conf"
                    systemctl --user stop "ssh-tunnel@${TUNNEL_NAME}"
                    systemctl --user disable "ssh-tunnel@${TUNNEL_NAME}"
                fi
            done
            
            # 2. 停止并禁用监控服务
            systemctl --user stop tunnel-monitor
            systemctl --user disable tunnel-monitor
            
            # 3. 删除服务文件
            rm -f "$HOME/.config/systemd/user/ssh-tunnel@.service"
            rm -f "$HOME/.config/systemd/user/tunnel-monitor.service"
            systemctl --user daemon-reload
            
            # 4. 删除脚本文件
            rm -f "$HOME/.local/bin/tunnel-monitor.sh"
            
            # 5. 删除配置目录
            rm -rf "$HOME/.config/ssh-tunnels"
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
        if [ "$(id -u)" = "0" ]; then
            echo "  服务目录: /etc/systemd/system"
            echo "  脚本目录: /usr/local/bin"
        else
            echo "  服务目录: $HOME/.config/systemd/user"
            echo "  脚本目录: $HOME/.local/bin"
        fi
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