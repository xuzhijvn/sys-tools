# SSH 隧道管理脚本 - Linux 版本

这是一个用于管理 SSH 隧道的 Shell 脚本，支持本地转发、远程转发和动态转发。脚本使用 systemd 服务来管理隧道，确保隧道的稳定性和自动恢复。

## 功能特点

- 多隧道管理
- 自动重连机制
- 状态监控
- 详细日志记录
- systemd 服务集成
- 失败重试策略

## 安装

### root 用户安装（推荐）

```bash
# 1. 复制脚本到系统目录
sudo cp tunnel-manager.sh /usr/local/bin/
sudo chmod +x /usr/local/bin/tunnel-manager.sh

# 2. 运行安装命令
tunnel-manager.sh setup
```

### 普通用户安装

```bash
# 1. 创建用户目录
mkdir -p ~/.local/bin
mkdir -p ~/.config/systemd/user
mkdir -p ~/.config/ssh-tunnels/{configs,logs,keys}

# 2. 复制脚本到用户目录
cp tunnel-manager.sh ~/.local/bin/
chmod +x ~/.local/bin/tunnel-manager.sh

# 3. 添加到环境变量（如果还没有）
echo 'export PATH=$PATH:$HOME/.local/bin' >> ~/.bashrc
source ~/.bashrc

# 4. 启用用户服务自动启动
loginctl enable-linger $USER

# 5. 运行安装命令
tunnel-manager.sh setup
```

## 使用方法

### 1. 生成 SSH 密钥

```bash
# 为隧道生成专用密钥
ssh-keygen -t ed25519 -f ~/.ssh/tunnel_key -N ""

# 复制公钥到目标服务器
ssh-copy-id -i ~/.ssh/tunnel_key.pub user@remote-server

# 设置正确的权限
chmod 700 ~/.ssh
chmod 600 ~/.ssh/tunnel_key
chmod 644 ~/.ssh/tunnel_key.pub
```

### 2. 添加隧道

```bash
# 本地转发（访问远程数据库）
tunnel-manager.sh add db_tunnel L 3306 db.internal 3306 user@server ~/.ssh/tunnel_key

# 远程转发（暴露本地服务）
tunnel-manager.sh add web_tunnel R 8080 localhost 80 user@server ~/.ssh/tunnel_key

# 动态转发 (SOCKS 代理)
# 对于动态转发模式，remote_host 和 remote_port 参数会被忽略，可以省略或使用任意值
tunnel-manager.sh add proxy D 1080 "" "" user@server ~/.ssh/tunnel_key
```

### 3. 管理隧道

```bash
# 列出所有隧道
tunnel-manager.sh list

# 查看隧道状态
tunnel-manager.sh status

# 停止特定隧道
tunnel-manager.sh stop web_tunnel

# 停止所有隧道
tunnel-manager.sh stop

# 重启特定隧道
tunnel-manager.sh restart web_tunnel

# 重启所有隧道
tunnel-manager.sh restart

# 移除隧道
tunnel-manager.sh remove web_tunnel

# 清理但保留密钥（默认行为）
tunnel-manager.sh clean

# 清理所有文件（包括密钥）
tunnel-manager.sh clean -f
```

## 目录结构

### root 用户模式
- 配置目录：/etc/ssh-tunnels/configs/
- 日志目录：/var/log/ssh-tunnels/
- 密钥目录：/etc/ssh-tunnels/keys/
- 服务目录：/etc/systemd/system/
- 脚本目录：/usr/local/bin/

### 普通用户模式
- 配置目录：~/.config/ssh-tunnels/configs/
- 日志目录：~/.config/ssh-tunnels/logs/
- 密钥目录：~/.config/ssh-tunnels/keys/
- 服务目录：~/.config/systemd/user/
- 脚本目录：~/.local/bin/

## 注意事项

5. 普通用户需要确保：
   - 已启用 lingering：`loginctl enable-linger $USER`
   - D-Bus 服务正常运行：`systemctl --user status dbus`
   - 用户实例已启动：`systemctl --user status`

6. 如果使用 sudo -i 切换到 root 用户：
   - 脚本会自动检测原始用户
   - 使用原始用户的 SSH 密钥和配置
   - 确保原始用户有正确的权限

## 配置说明

每个隧道的配置文件 (`/etc/ssh-tunnels/configs/<name>.conf`) 包含以下参数：

```bash
TUNNEL_NAME="tunnel_name"        # 隧道名称
TUNNEL_MODE="L"                  # 隧道模式：L(本地), R(远程), D(动态)
LOCAL_PORT="local_port"          # 本地端口
REMOTE_HOST="remote_host"        # 远程主机（动态模式下会被忽略）
REMOTE_PORT="remote_port"        # 远程端口（动态模式下会被忽略）
SSH_SERVER="user@server"         # SSH 服务器
SSH_KEY="/path/to/key"          # SSH 密钥路径
EXTRA_SSH_OPTS=""               # 额外的 SSH 选项
```

## 隧道模式说明

1. **本地端口转发 (-L)**
   - 将远程服务映射到本地端口
   - 适用于访问远程内部服务
   - 示例：访问远程数据库

2. **远程端口转发 (-R)**
   - 将本地服务映射到远程端口
   - 适用于暴露内部服务
   - 示例：远程访问本地 Web 服务器

3. **动态端口转发 (-D)**
   - 创建 SOCKS 代理
   - 适用于通用代理需求
   - 示例：浏览器代理配置

## 监控和自动恢复

- 每 30 秒检查一次隧道状态
- 连续失败 3 次后自动重启隧道
- 所有事件都记录到日志文件
- 通过 systemd 服务确保监控进程始终运行

## 安全建议

1. **SSH 密钥管理**
   - 为每个隧道使用独立的密钥
   - 适当限制密钥权限
   - 定期轮换密钥

2. **服务器端配置**
```bash
# 在目标服务器的 ~/.ssh/authorized_keys 中限制命令
command="echo 'Port forwarding only'",no-agent-forwarding,no-x11-forwarding,no-pty ssh-ed25519 AAAA...
```

3. **文件权限**
```bash
chmod 700 /etc/ssh-tunnels/keys
chmod 600 /etc/ssh-tunnels/keys/*
chmod 644 /etc/ssh-tunnels/keys/*.pub
```

## 故障排查

1. **使用 check 命令进行系统检查**
bash
# 检查系统配置状态
tunnel-manager.sh check

# 测试系统功能
tunnel-manager.sh test

# 如果一切正常，会看到：
✓ 所有组件检查通过
系统配置正常，可以正常使用。

# 如果有问题，会看到具体错误信息：
错误: systemd 服务模板不存在
错误: 监控服务不存在
错误: tunnel-monitor 服务未启用
```

2. **使用 test 命令测试功能**
```bash
# 测试系统功能
tunnel-manager.sh test

# 测试会执行以下步骤：
# 1. 添加测试隧道
# 2. 检查隧道状态
# 3. 测试停止功能
# 4. 测试重启功能
# 5. 测试删除功能
```

3. **隧道无法建立**
```   - 检查 SSH 密钥权限
   - 验证目标服务器连接
   - 检查端口占用情况

3. **隧道经常断开**
   - 检查网络接稳定性
   - 调整 SSH 保活参数
   - 查看详细日志

4. **服务无法启动**
   - 检查 systemd 服务状态
   - 验证配置文件格式
   - 查看系统日志

## 常见问题

1. **如何修改隧道配置？**
   ```bash
   # 删除后重新添加
   tunnel-manager.sh remove old_tunnel
   tunnel-manager.sh add old_tunnel <new_parameters>
   ```

2. **如何临时停止隧道？**
   ```bash
   systemctl stop ssh-tunnel@tunnel_name
   ```

3. **如何查看详细状态？**
   ```bash
   systemctl status ssh-tunnel@tunnel_name
   ```

## 查看日志

1. **查看隧道服务日志**
```bash
# 对于 root 用户
journalctl -u ssh-tunnel@tunnel_name

# 对于普通用户
journalctl --user -u ssh-tunnel@tunnel_name
```

2. **查看监控服务日志**
```bash
# 对于 root 用户
journalctl -u tunnel-monitor

# 对于普通用户
journalctl --user -u tunnel-monitor
```

3. **查看详细日志文件**
```bash
# 对于 root 用户
tail -f /var/log/ssh-tunnels/monitor.log

# 对于普通用户
tail -f ~/.config/ssh-tunnels/logs/monitor.log
```

4. **实时监控日志**
```bash
# 对于 root 用户
journalctl -u ssh-tunnel@tunnel_name -f

# 对于普通用户
journalctl --user -u ssh-tunnel@tunnel_name -f
```

## 许可证

MIT License

## 作者

xuzhijvn``` 