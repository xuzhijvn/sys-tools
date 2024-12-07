# SSH 隧道管理工具 - Linux 版本

这是一个用于管理多个 SSH 隧道的工具，基于 systemd 服务管理，提供自动重连、状态监控和日志记录功能。

## 功能特点

- 多隧道管理
- 自动重连机制
- 状态监控
- 详细日志记录
- systemd 服务集成
- 失败重试策略

## 系统要求

- Linux 系统（支持 systemd）
- Bash shell
- SSH 客户端
- netstat 工具（通常包含在 net-tools 包中）

## 安装步骤

1. **下载脚本**
```bash
wget -O /usr/local/bin/tunnel-manager.sh https://your-domain.com/scripts/tunnel-manager.sh
chmod +x /usr/local/bin/tunnel-manager.sh
```

2. **初始化系统**
```bash
tunnel-manager.sh setup
```
这个命令会：
- 创建必要的目录结构
- 创建 systemd 服务文件
- 创建监控脚本
- 启动监控服务

## 目录结构

```
/etc/ssh-tunnels/
├── configs/           # 隧道配置文件
│   ├── tunnel1.conf
│   └── tunnel2.conf
├── keys/             # SSH 密钥存储
│   ├── tunnel1_key
│   └── tunnel2_key
└── logs/             # 日志文件

/usr/local/bin/
├── tunnel-manager.sh  # 主管理脚本
└── tunnel-monitor.sh  # 监控脚本（由setup自动创建）
```

## 使用方法

### 1. 生成 SSH 密钥

```bash
# 为隧道生成专用密钥
ssh-keygen -t ed25519 -f /etc/ssh-tunnels/keys/tunnel1_key -N ""

# 复制公钥到目标服务器
ssh-copy-id -i /etc/ssh-tunnels/keys/tunnel1_key.pub user@remote-server
```

### 2. 管理隧道

```bash
# 添加新隧道
tunnel-manager.sh add <name> <mode> <local_port> <remote_host> <remote_port> <ssh_server> <ssh_key> [extra_opts]

# 模式说明：
# L: 本地端口转发 (-L)
# R: 远程端口转发 (-R)
# D: 动态端口转发 (-D，SOCKS代理)

# 示例1：本地端口转发（访问远程数据库）
tunnel-manager.sh add db_tunnel L 3306 db.internal 3306 user@server /etc/ssh-tunnels/keys/tunnel1_key

# 示例2：远程端口转发（暴露本地服务）
tunnel-manager.sh add web_tunnel R 8080 localhost 80 user@server /etc/ssh-tunnels/keys/tunnel2_key

# 示例3：动态端口转发（SOCKS代理）
tunnel-manager.sh add proxy_tunnel D 1080 - - user@server /etc/ssh-tunnels/keys/tunnel3_key

# 删除隧道
tunnel-manager.sh remove tunnel_name

# 查看所有隧道
tunnel-manager.sh list

# 查看隧道状态
tunnel-manager.sh status

# 停止隧道
tunnel-manager.sh stop [tunnel_name]     # 不���定名称则停止所有隧道

# 重启隧道
tunnel-manager.sh restart [tunnel_name]   # 不指定名称则重启所有隧道

# 完全清理
tunnel-manager.sh clean                   # 清理所有隧道及相关文件、服务和配置
```

### 3. 隧道管理示例

```bash
# 1. 创建并启动一个数据库隧道
tunnel-manager.sh add db_tunnel L 3306 db.internal 3306 user@server /etc/ssh-tunnels/keys/db_key

# 2. 临时停止这个隧道
tunnel-manager.sh stop db_tunnel

# 3. 重新启动这个隧道
tunnel-manager.sh restart db_tunnel

# 4. 修改隧道配置
tunnel-manager.sh remove db_tunnel
tunnel-manager.sh add db_tunnel L 3307 db.internal 3306 user@server /etc/ssh-tunnels/keys/db_key

# 5. 停止所有隧道
tunnel-manager.sh stop

# 6. 重启所有隧道
tunnel-manager.sh restart

# 7. 完全清理系统
tunnel-manager.sh clean   # 清理所有隧道、服务和配置文件
```

### 4. 查看日志

bash
# 查看隧道服务日志
journalctl -u ssh-tunnel@tunnel_name

# 查看监控服务日志
journalctl -u tunnel-monitor

# 查看详细日志文件
tail -f /var/log/ssh-tunnels/monitor.log
```

## 配置说明

每个隧道的配置文件 (`/etc/ssh-tunnels/configs/<name>.conf`) 包含以下参数：

```bash
TUNNEL_NAME="tunnel_name"        # 隧道名称
TUNNEL_MODE="L"                  # 隧道模式：L(本地), R(远程), D(动态)
LOCAL_PORT="local_port"          # 本地端口
REMOTE_HOST="remote_host"        # 远程主机（动态模式下可忽略）
REMOTE_PORT="remote_port"        # 远程端口（动态模式下可忽略）
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

1. **隧道无法建立**
   - 检查 SSH 密钥权限
   - 验证目标服务器连接
   - 检查端口占用情况

2. **隧道经常断开**
   - 检查网络连接稳定性
   - 调整 SSH 保活参数
   - 查看详细日志

3. **服务无法启动**
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

## 许可证

MIT License

## 作者

xuzhijvn``` 