# SSH 隧道管理工具 - OpenWRT 版本

这是一个用于管理多个 SSH 隧道的工具，专门为 OpenWRT 设计，基于 procd 进程管理，提供自动重连、状态监控和日志记录功能。

## 功能特点

- 多隧道管理
- 自动重连机制
- 状态监控
- 详细日志记录
- procd 服务集成
- 网络感知（通过 hotplug）
- 资源占用优化
- 配置持久化

## 系统要求

- OpenWRT 系统
- SSH 客户端
- cron 支持
- netstat 工具

## 安装步骤

1. **下载脚本**
```bash
wget -O /usr/bin/tunnel-manager.sh https://your-domain.com/scripts/openwrt/tunnel-manager.sh
chmod +x /usr/bin/tunnel-manager.sh
```

2. **初始化系统**
```bash
tunnel-manager.sh setup
```
这个命令会：
- 创建必要的目录结构
- 创建 init.d 服务脚本
- 创建监控脚本
- 创建 hotplug 脚本
- 设置 cron 任务

## 目录结构

```
/etc/ssh-tunnels/
├── configs/           # 隧道配置文件
│   ├── tunnel1.conf
│   └── tunnel2.conf
└── keys/             # SSH 密钥存储
    ├── tunnel1_key
    └── tunnel2_key

/usr/bin/ssh-tunnels/
└── monitor.sh        # 监控脚本（由setup自动创建）

/etc/init.d/
└── ssh-tunnels       # OpenWRT init 脚本

/etc/hotplug.d/iface/
└── 30-ssh-tunnels    # 网络接口监控脚本
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
tunnel-manager.sh stop [tunnel_name]     # 不指定名称则停止所有隧道

# 重启隧道
tunnel-manager.sh restart [tunnel_name]   # 不指定名称则重启所有隧道
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
```

### 3. 查看日志

bash
# 查看系统日志
logread | grep ssh-tunnels

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
- WAN 口状态监控和自动恢复

## 持久化存储

为确保配置在重启后保持，建议：

```bash
# 创建持久化存储
mkdir -p /overlay/etc/ssh-tunnels
mount -o bind /overlay/etc/ssh-tunnels /etc/ssh-tunnels

# 添加到 /etc/rc.local
cat >> /etc/rc.local << 'EOF'
# 确保 SSH 隧道配置持久化
mount -o bind /overlay/etc/ssh-tunnels /etc/ssh-tunnels
exit 0
EOF
```

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

## 资源优化

1. **内存使用优化**
```bash
# 在 /etc/sysctl.conf 中添加
net.ipv4.tcp_keepalive_time = 60
net.ipv4.tcp_keepalive_intvl = 10
net.ipv4.tcp_keepalive_probes = 6
```

2. **CPU 使用优化**
- 使用较长的检查间隔
- 避免频繁的日志写入
- 优化 SSH 参数

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
   - 检查 procd 服务状态
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
   /etc/init.d/ssh-tunnels stop
   ```

3. **如何处理内存不足？**
   ```bash
   # 调整检查间隔
   vi /usr/bin/ssh-tunnels/monitor.sh
   # 修改 CHECK_INTERVAL 值
   ```

## 许可证

MIT License

## 作者

xuzhijvn``` 