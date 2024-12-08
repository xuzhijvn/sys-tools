# Windows SSH 隧道管理器

基于 PowerShell 的 Windows SSH 隧道管理工具，提供自动化的隧道管理功能。

## 功能特点

- 自动化隧道配置和管理
- Windows 服务集成，确保稳定运行
- 自动监控和故障恢复
- 详细的日志记录
- 支持多隧道管理
- 安全的密钥管理

## 系统要求

- Windows 10/11 或 Windows Server 2016+
- PowerShell 5.1 或更高版本
- 已安装 OpenSSH 客户端
- 管理员权限

## 安装步骤

1. **安装 OpenSSH 客户端**（如果尚未安装）：
   - 以管理员身份打开 PowerShell
   - 运行以下命令：
   ```powershell
   Add-WindowsCapability -Online -Name OpenSSH.Client~~~~0.0.1.0
   ```

2. **生成 SSH 密钥**：
   - 打开 PowerShell（不需要管理员权限）
   - 生成新的 SSH 密钥：
   ```powershell
   # 生成新的 SSH 密钥对（一路回车使用默认值即可）
   ssh-keygen -t rsa -b 4096
   ```
   - 密钥默认保存在：`C:\Users\你的用户名\.ssh\id_rsa`（私钥）和 `id_rsa.pub`（公钥）

3. **配置 SSH 密钥**：
   - 查看公钥内容：
   ```powershell
   Get-Content $env:USERPROFILE\.ssh\id_rsa.pub
   ```
   - 复制公钥内容到远程服务器的 `~/.ssh/authorized_keys` 文件中：
   ```powershell
   # 方法1：使用 ssh-copy-id（如果可用）
   ssh-copy-id 用户名@服务器地址

   # 方法2：手动复制（如果无法使用 ssh-copy-id）
   # 1. 复制上面显示的公钥内容
   # 2. 登录到远程服务器
   # 3. 添加到授权文件：
   #    mkdir -p ~/.ssh
   #    echo "你的公钥内容" >> ~/.ssh/authorized_keys
   #    chmod 700 ~/.ssh
   #    chmod 600 ~/.ssh/authorized_keys
   ```

4. **创建必要的目录**：
   - 以管理员身份打开 PowerShell
   - 创建基础目录结构：
   ```powershell
   New-Item -ItemType Directory -Force -Path "C:\ProgramData\ssh-tunnels"
   New-Item -ItemType Directory -Force -Path "C:\ProgramData\ssh-tunnels\configs"
   New-Item -ItemType Directory -Force -Path "C:\ProgramData\ssh-tunnels\logs"
   New-Item -ItemType Directory -Force -Path "C:\ProgramData\ssh-tunnels\keys"
   New-Item -ItemType Directory -Force -Path "C:\ProgramData\ssh-tunnels\scripts"
   ```

5. **复制脚本文件**：
   - 将 `tunnel-manager.ps1` 复制到固定位置（例如：`C:\ProgramData\ssh-tunnels\tunnel-manager.ps1`）

6. **设置执行策略**（如果需要）：
   ```powershell
   Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope LocalMachine
   ```

## 使用指南

### 1. 设置新隧道

1. 以管理员身份打开 PowerShell
2. 进入脚本目录：
   ```powershell
   cd C:\ProgramData\ssh-tunnels
   ```
3. 创建新隧道，使用以下命令：
   ```powershell
   .\tunnel-manager.ps1 setup <隧道名称> -mode <L/R/D> -localPort <本地端口> -remoteHost <远程主机> -remotePort <远程端口> -sshServer <用户名@服务器> -sshKey <密钥路径>
   ```

   示例：
   ```powershell
   # 使用默认密钥位置
   .\tunnel-manager.ps1 setup mysql-tunnel -mode L -localPort 3306 -remoteHost localhost -remotePort 3306 -sshServer user@example.com -sshKey $env:USERPROFILE\.ssh\id_rsa

   # 使用自定义密钥位置
   .\tunnel-manager.ps1 setup mysql-tunnel -mode L -localPort 3306 -remoteHost localhost -remotePort 3306 -sshServer user@example.com -sshKey C:\path\to\your\private_key
   ```

   参数说明：
   - `mode`: 隧道模式
     - `L`: 本地转发（常用，将远程端口映射到本地）
     - `R`: 远程转发（将本地端口映射到远程）
     - `D`: 动态转发（SOCKS代理）
   - `localPort`: 本地端口号
   - `remoteHost`: 远程主机地址（mode=D时可省略）
   - `remotePort`: 远程端口号（mode=D时可省略）
   - `sshServer`: SSH服务器（格式：用户名@服务器地址）
   - `sshKey`: SSH私钥路径

### 2. 隧道管理

1. **启动隧道**：
   ```powershell
   .\tunnel-manager.ps1 start <隧道名称>
   ```

2. **停止隧道**：
   ```powershell
   .\tunnel-manager.ps1 stop <隧道名称>
   ```

3. **列出所有隧道**：
   ```powershell
   .\tunnel-manager.ps1 list
   ```

4. **删除隧道**：
   ```powershell
   .\tunnel-manager.ps1 remove <隧道名称>
   ```

### 3. 监控和日志

- 监控日志位置：`C:\ProgramData\ssh-tunnels\logs\monitor.log`
- 隧道服务日志位置：`C:\ProgramData\ssh-tunnels\logs\tunnel.log`
- 使用 PowerShell 查看日志：
  ```powershell
  Get-Content -Path "C:\ProgramData\ssh-tunnels\logs\monitor.log" -Tail 50 -Wait
  ```

## 目录结构

```
C:\ProgramData\ssh-tunnels\
├── tunnel-manager.ps1  # 主脚本
├── configs/           # 隧道配置文件目录
│   └── *.conf        # 各个隧道的配置文件
├── logs/             # 日志文件目录
│   ├── monitor.log   # 监控服务日志
│   └── tunnel.log    # 隧道服务日志
├── keys/             # SSH 密钥目录
└── scripts/          # 服务脚本目录
    ├── tunnel-monitor.ps1  # 监控服务脚本
    └── tunnel-service.ps1  # 隧道服务脚本
```

## 故障排除

1. **服务无法启动**：
   - 检查 `C:\ProgramData\ssh-tunnels\logs\` 中的日志文件
   - 验证 SSH 密钥权限（只有 SYSTEM 和管理员应有访问权限）
   - 确保 OpenSSH 客户端已安装且正常工作

2. **连接问题**：
   - 验证 SSH 服务器是否可访问：`ssh -i <密钥路径> <用户名@服务器> "echo test"`
   - 检查本地端口是否已被占用：`netstat -ano | findstr <端口号>`
   - 检查防火墙设置是否允许连接
   - 确认密钥权限：
     ```powershell
     # 检查私钥权限
     icacls $env:USERPROFILE\.ssh\id_rsa
     # 如果需要，设置正确的权限
     icacls $env:USERPROFILE\.ssh\id_rsa /inheritance:r
     icacls $env:USERPROFILE\.ssh\id_rsa /grant:r "$env:USERNAME:(R)"
     ```

3. **权限问题**：
   - 确保以管理员身份运行 PowerShell
   - 检查 SSH 密钥和脚本文件的权限设置
   - 确保 SSH 私钥对当前用户和 SYSTEM 账户可读
``` 