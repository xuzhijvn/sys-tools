# SSH 隧道管理脚本 - OpenWRT 版本

这是一个用于管理 SSH 隧道的 Shell 脚本，支持本地转发、远程转发和动态转发。脚本使用 procd 服务来管理隧道，确保隧道的稳定性和自动恢复。

## 功能特点

- 支持三种转发模式：本地转发(-L)、远程转发(-R)和动态转发(-D)
- 使用 procd 服务管理隧道
- 自动监控和恢复断开的隧道
- 本地转发模式默认开启网关功能(-g)
- 详细的错误提示和调试信息

## 安装

### 管理员安装（推荐）
```bash
# 1. 复制脚本到系统目录
cp tunnel-manager.sh /usr/bin/
chmod +x /usr/bin/tunnel-manager.sh

# 2. 运行安装命令
tunnel-manager.sh setup
```

## 密钥管理

在使用隧道之前，需要先设置 SSH 密钥。OpenWRT 支持两种方式生成密钥：

### 方式一：使用 OpenSSH（推荐）

```bash
# 1. 安装 openssh-keygen
opkg update
opkg install openssh-keygen

# 2. 创建密钥目录（如果不存在）
mkdir -p /etc/ssh-tunnels/keys
chmod 700 /etc/ssh-tunnels/keys

# 3. 生成 ED25519 密钥
ssh-keygen -t ed25519 -f /etc/ssh-tunnels/keys/tunnel_key

# 4. 设置正确的权限
chmod 600 /etc/ssh-tunnels/keys/tunnel_key
chmod 644 /etc/ssh-tunnels/keys/tunnel_key.pub

# 5. 将公钥复制到目标服务器
# 查看公钥内容
cat /etc/ssh-tunnels/keys/tunnel_key.pub
# 然后手动将上面显示的公钥内容追加到目标服务器的 ~/.ssh/authorized_keys 文件中
```

### 方式二：使用 Dropbear（OpenWRT 默认）

```bash
# 1. 创建密钥目录（如果不存在）
mkdir -p /etc/ssh-tunnels/keys
chmod 700 /etc/ssh-tunnels/keys

# 2. 生成 ED25519 密钥
dropbearkey -t ed25519 -f /etc/ssh-tunnels/keys/tunnel_key

# 3. 导出公钥为 OpenSSH 格式
dropbearkey -y -f /etc/ssh-tunnels/keys/tunnel_key | grep "^ssh-ed25519" > /etc/ssh-tunnels/keys/tunnel_key.pub

# 4. 设置正确的权限
chmod 600 /etc/ssh-tunnels/keys/tunnel_key
chmod 644 /etc/ssh-tunnels/keys/tunnel_key.pub

# 5. 将公钥复制到目标服务器
# 查看公钥内容
cat /etc/ssh-tunnels/keys/tunnel_key.pub
# 然后手动将上面显示的公钥内容追加到目标服务器的 ~/.ssh/authorized_keys 文件中
```

注意：
1. 推荐使用 OpenSSH 方式生成密钥，因为它与大多数 SSH 服务器兼容性更好
2. 如果使用 Dropbear 生成的密钥，某些情况下可能需要转换格式
3. 建议为每个隧道使用独立的密钥对
4. 确保密钥文件权限正确设置（密钥: 600, 公钥: 644）
5. 可以在目标服务器上限制密钥的使用范围：
```bash
# 在目标服务器的 ~/.ssh/authorized_keys 中添加限制
command="echo 'Port forwarding only'",no-agent-forwarding,no-x11-forwarding,no-pty ssh-ed25519 AAAA...
```

## 使用方法

### 添加隧道
```bash
# 本地转发（访问远程数据库）
tunnel-manager.sh add db_tunnel L 3306 db.internal 3306 user@server /etc/ssh-tunnels/keys/tunnel_key

# 远程转发（暴露本地服务）
tunnel-manager.sh add web_tunnel R 8080 localhost 80 user@server /etc/ssh-tunnels/keys/tunnel_key

# 动态转发 (SOCKS 代理)
tunnel-manager.sh add proxy D 1080 - - user@server /etc/ssh-tunnels/keys/tunnel_key
```

### 管理隧道
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
```

### 系统管理
```bash
# 检查系统配置
tunnel-manager.sh check

# 测试系统功能
tunnel-manager.sh test

# 清理所有配置
tunnel-manager.sh clean
```

## 目录结构

- 配置目录：/etc/ssh-tunnels/configs/
- 日志目录：/var/log/ssh-tunnels/
- 密钥目录：/etc/ssh-tunnels/keys/
- 服务目录：/etc/init.d/
- 脚本目录：/usr/bin/ssh-tunnels/

## 注意事项

1. 建议为每个隧道使用独立的密钥对
2. 确保密钥文件权限正确设置（密钥: 600, 公钥: 644）
3. 本地转发模式(-L)默认启用网关模式(-g)，允许其他设备通过 OpenWRT 访问隧道
4. 可以在目标服务器上限制密钥的使用范围：
```bash
# 在目标服务器的 ~/.ssh/authorized_keys 中添加限制
command="echo 'Port forwarding only'",no-agent-forwarding,no-x11-forwarding,no-pty ssh-ed25519 AAAA...
```

## 故障排除

1. 如果隧道无法启动，请检查：
   - SSH 服务是否运行：`/etc/init.d/dropbear status`
   - SSH 密钥权限是否正确：应为 600
   - 系统日志：`logread | grep ssh-tunnels`

2. 查看详细日志：
```bash
# 查看服务状态
/etc/init.d/ssh-tunnels status

# 查看系统日志
logread | grep ssh-tunnels

# 查看详细日志文件
tail -f /var/log/ssh-tunnels/monitor.log
```

## 许可证

MIT License

## 作者

xuzhijvn

## 可靠性保证

系统通过多层机制确保服务的可靠运行：

1. 服务级监控
   - 监控脚本每 30 秒检查一次所有隧道状态
   - 自动重启失败的隧道
   - 详细的日志记录

2. 系统级监控
   - 每 5 分钟检查监控脚本是否运行
   - 如果监控脚本不在运行，自动重启服务
   - 系统重启时自动启动服务

3. SSH 连接优化
   - 定期发送心跳包
   - 自动重连机制
   - TCP 保活设置