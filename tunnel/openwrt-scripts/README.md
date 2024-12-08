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

### 普通用户安装
```bash
# 1. 确保有 sudo 权限
# 编辑 /etc/sudoers，添加以下内容：
your_username ALL=(ALL) NOPASSWD: /usr/bin/tunnel-manager.sh
your_username ALL=(ALL) NOPASSWD: /etc/init.d/ssh-tunnels

# 2. 复制脚本到用户目录
mkdir -p ~/bin
cp tunnel-manager.sh ~/bin/
chmod +x ~/bin/tunnel-manager.sh

# 3. 添加到环境变量
echo 'export PATH=$PATH:$HOME/bin' >> ~/.profile
source ~/.profile

# 4. 运行安装命令
sudo tunnel-manager.sh setup
```

## 使用方法

### 添加隧道
```bash
# 本地转发（访问远程数据库）
sudo tunnel-manager.sh add db_tunnel L 3306 db.internal 3306 user@server ~/.ssh/id_ed25519

# 远程转发（暴露本地服务）
sudo tunnel-manager.sh add web_tunnel R 8080 localhost 80 user@server ~/.ssh/id_ed25519

# 动态转发 (SOCKS 代理)
sudo tunnel-manager.sh add proxy D 1080 - - user@server ~/.ssh/id_ed25519
```

### 管理隧道
```bash
# 列出所有隧道
sudo tunnel-manager.sh list

# 查看隧道状态
sudo tunnel-manager.sh status

# 停止特定隧道
sudo tunnel-manager.sh stop web_tunnel

# 停止所有隧道
sudo tunnel-manager.sh stop

# 重启特定隧道
sudo tunnel-manager.sh restart web_tunnel

# 重启所有隧道
sudo tunnel-manager.sh restart

# 移除隧道
sudo tunnel-manager.sh remove web_tunnel
```

### 系统管理
```bash
# 检查系统配置
sudo tunnel-manager.sh check

# 测试系统功能
sudo tunnel-manager.sh test

# 清理所有配置
sudo tunnel-manager.sh clean
```

## 目录结构

- 配置目录：/etc/ssh-tunnels/configs/
- 日志目录：/var/log/ssh-tunnels/
- 密钥目录：/etc/ssh-tunnels/keys/
- 服务目录：/etc/init.d/
- 脚本目录：/usr/bin/ssh-tunnels/

## 注意事项

1. 普通用户需要 sudo 权限才能执行脚本
2. 使用前请确保 SSH 密钥已正确配置：
```bash
# 生成密钥
ssh-keygen -t ed25519 -f ~/.ssh/tunnel_key

# 复制公钥到目标服务器
ssh-copy-id -i ~/.ssh/tunnel_key.pub user@server

# 设置正确的权限
chmod 700 ~/.ssh
chmod 600 ~/.ssh/tunnel_key
chmod 644 ~/.ssh/tunnel_key.pub
```

3. 本地转发模式(-L)默认启用网关模式(-g)，允许其他设备通过 OpenWRT 访问隧道

4. 可以在目标服务器的 authorized_keys 中限制命令：
```bash
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
``` 