# tunnel-manager.ps1
param(
    [Parameter(Position=0)]
    [string]$Command,
    [Parameter(ValueFromRemainingArguments=$true)]
    [string[]]$Arguments
)

# 固定系统目录
$TUNNEL_CONFIG_DIR = "C:\ProgramData\ssh-tunnels\configs"
$LOG_DIR = "C:\ProgramData\ssh-tunnels\logs"
$KEYS_DIR = "C:\ProgramData\ssh-tunnels\keys"
$SCRIPTS_DIR = "C:\ProgramData\ssh-tunnels\scripts"

# 创建必要的目录
New-Item -ItemType Directory -Force -Path $TUNNEL_CONFIG_DIR
New-Item -ItemType Directory -Force -Path $LOG_DIR
New-Item -ItemType Directory -Force -Path $KEYS_DIR
New-Item -ItemType Directory -Force -Path $SCRIPTS_DIR

# 创建监控服务脚本
function Create-MonitorScript {
    $monitorPath = Join-Path $SCRIPTS_DIR "tunnel-monitor.ps1"
    @"
# tunnel-monitor.ps1
`$ErrorActionPreference = 'Stop'

# 配置
`$CONFIG_DIR = 'C:\ProgramData\ssh-tunnels\configs'
`$LOG_DIR = 'C:\ProgramData\ssh-tunnels\logs'
`$CHECK_INTERVAL = 30
`$MAX_FAILURES = 3

# 初始化失败计数器
`$script:failureCounts = @{}

function Write-Log {
    param([string]`$Message)
    
    `$timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    `$logMessage = "`$timestamp - `$Message"
    `$logFile = Join-Path `$LOG_DIR "monitor.log"
    Add-Content -Path `$logFile -Value `$logMessage
    Write-Host `$logMessage
}

function Test-TunnelPort {
    param(
        [string]`$Port
    )
    
    try {
        `$null = Test-NetConnection -ComputerName localhost -Port `$Port -ErrorAction Stop
        return `$true
    } catch {
        return `$false
    }
}

function Check-Tunnel {
    param(
        [string]`$ConfigFile
    )
    
    try {
        `$config = Get-Content `$ConfigFile | ConvertFrom-StringData
        `$serviceName = "SSHTunnel_`$(`$config.TUNNEL_NAME)"
        
        # 检查服务状态
        `$service = Get-Service -Name `$serviceName -ErrorAction SilentlyContinue
        if (-not `$service) {
            Write-Log "Service `$serviceName not found"
            return
        }
        
        # 检查端口
        if (-not (Test-TunnelPort -Port `$config.LOCAL_PORT)) {
            if (-not `$script:failureCounts.ContainsKey(`$serviceName)) {
                `$script:failureCounts[`$serviceName] = 0
            }
            
            `$script:failureCounts[`$serviceName]++
            Write-Log "Tunnel `$(`$config.TUNNEL_NAME) (port `$(`$config.LOCAL_PORT)) check failed. Failure count: `$(`$script:failureCounts[`$serviceName])"
            
            if (`$script:failureCounts[`$serviceName] -ge `$MAX_FAILURES) {
                Write-Log "Max failures reached for `$(`$config.TUNNEL_NAME). Restarting service..."
                Restart-Service -Name `$serviceName -Force
                `$script:failureCounts[`$serviceName] = 0
                
                Start-Sleep -Seconds 5
                if (Test-TunnelPort -Port `$config.LOCAL_PORT) {
                    Write-Log "Tunnel `$(`$config.TUNNEL_NAME) restored successfully"
                } else {
                    Write-Log "Failed to restore tunnel `$(`$config.TUNNEL_NAME)"
                }
            }
        } else {
            `$script:failureCounts[`$serviceName] = 0
        }
    } catch {
        Write-Log "Error checking tunnel `$ConfigFile : `$_"
    }
}

Write-Log "SSH tunnel monitor started"

while (`$true) {
    Get-ChildItem -Path `$CONFIG_DIR -Filter "*.conf" | ForEach-Object {
        Check-Tunnel -ConfigFile `$_.FullName
    }
    Start-Sleep -Seconds `$CHECK_INTERVAL
}
"@ | Set-Content $monitorPath
}

# 创建隧道服务脚本
function Create-ServiceScript {
    $servicePath = Join-Path $SCRIPTS_DIR "tunnel-service.ps1"
    @"
# tunnel-service.ps1
param(
    [string]`$ConfigFile
)

`$ErrorActionPreference = 'Stop'
`$LOG_DIR = 'C:\ProgramData\ssh-tunnels\logs'

function Write-Log {
    param([string]`$Message)
    
    `$timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    `$logMessage = "`$timestamp - `$Message"
    `$logFile = Join-Path `$LOG_DIR "tunnel.log"
    Add-Content -Path `$logFile -Value `$logMessage
    Write-Host `$logMessage
}

try {
    # 读取配置
    `$config = Get-Content `$ConfigFile | ConvertFrom-StringData
    
    Write-Log "Starting SSH tunnel with following parameters:"
    Write-Log "Config file: `$ConfigFile"
    Write-Log "SSH server: `$(`$config.SSH_SERVER)"
    Write-Log "Mode: `$(`$config.TUNNEL_MODE)"
    Write-Log "Local port: `$(`$config.LOCAL_PORT)"
    
    # 构建 SSH 参数
    `$sshArgs = @(
        "-N"
        "-o", "ServerAliveInterval=30"
        "-o", "ServerAliveCountMax=3"
        "-o", "ExitOnForwardFailure=yes"
        "-o", "TCPKeepAlive=yes"
        "-o", "StrictHostKeyChecking=no"
        "-o", "UserKnownHostsFile=/dev/null"
        "-o", "BatchMode=yes"
        "-o", "ConnectTimeout=10"
        "-o", "ConnectionAttempts=3"
        "-i", `$config.SSH_KEY
    )
    
    if (`$config.TUNNEL_MODE -eq "D") {
        `$sshArgs += "-D", `$config.LOCAL_PORT
    } else {
        `$sshArgs += "-`$(`$config.TUNNEL_MODE)", "`$(`$config.LOCAL_PORT):`$(`$config.REMOTE_HOST):`$(`$config.REMOTE_PORT)"
    }
    
    `$sshArgs += `$config.SSH_SERVER
    
    Write-Log "Starting SSH with arguments: ssh `$(`$sshArgs -join ' ')"
    
    # 启动 SSH 进程
    `$process = Start-Process -FilePath "ssh" -ArgumentList `$sshArgs -NoNewWindow -PassThru
    Write-Log "SSH process started with PID: `$(`$process.Id)"
    
    # 等待进程结束
    `$process.WaitForExit()
    Write-Log "SSH process exited with code: `$(`$process.ExitCode)"
    exit `$process.ExitCode
} catch {
    Write-Log "Error: `$_"
    exit 1
}
"@ | Set-Content $servicePath
}

# 创建 Windows 服务
function Create-TunnelService {
    param(
        [string]$Name,
        [string]$ConfigFile
    )
    
    $serviceName = "SSHTunnel_$Name"
    $serviceArgs = "-ExecutionPolicy Bypass -File `"$(Join-Path $SCRIPTS_DIR 'tunnel-service.ps1')`" -ConfigFile `"$ConfigFile`""
    
    # 创建服务
    $result = sc.exe create $serviceName binPath= "powershell.exe $serviceArgs" start= auto
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to create service: $result"
    }
    
    # 设置服务恢复选项（自动重启）
    $result = sc.exe failure $serviceName reset= 86400 actions= restart/60000/restart/60000/restart/60000
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to set service recovery options: $result"
    }
    
    # 设置服务描述
    $result = sc.exe description $serviceName "SSH Tunnel Service for $Name"
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to set service description: $result"
    }
}

# 创建监控服务
function Create-MonitorService {
    $serviceName = "SSHTunnelMonitor"
    $serviceArgs = "-ExecutionPolicy Bypass -File `"$(Join-Path $SCRIPTS_DIR 'tunnel-monitor.ps1')`""
    
    # 创建服务
    $result = sc.exe create $serviceName binPath= "powershell.exe $serviceArgs" start= auto
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to create monitor service: $result"
    }
    
    # 设置服务恢复选项
    $result = sc.exe failure $serviceName reset= 86400 actions= restart/60000/restart/60000/restart/60000
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to set monitor service recovery options: $result"
    }
    
    # 设置服务描述
    $result = sc.exe description $serviceName "SSH Tunnel Monitor Service"
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to set monitor service description: $result"
    }
}

# 设置隧道
function Setup-Tunnel {
    param(
        [string]$name,
        [string]$mode,
        [string]$localPort,
        [string]$remoteHost,
        [string]$remotePort,
        [string]$sshServer,
        [string]$sshKey
    )
    
    # 验证参数
    if ([string]::IsNullOrEmpty($name)) {
        throw "Name is required"
    }
    if ($mode -notmatch '^[LRD]$') {
        throw "Mode must be L, R, or D"
    }
    if ([string]::IsNullOrEmpty($localPort)) {
        throw "Local port is required"
    }
    if ($mode -ne "D" -and ([string]::IsNullOrEmpty($remoteHost) -or [string]::IsNullOrEmpty($remotePort))) {
        throw "Remote host and port are required for L/R mode"
    }
    if ([string]::IsNullOrEmpty($sshServer)) {
        throw "SSH server is required"
    }
    if ([string]::IsNullOrEmpty($sshKey)) {
        throw "SSH key is required"
    }
    
    # 复制 SSH 密钥
    $keyFileName = Split-Path $sshKey -Leaf
    $keyDestPath = Join-Path $KEYS_DIR $keyFileName
    Copy-Item -Path $sshKey -Destination $keyDestPath -Force
    
    # 创建配置文件
    $configPath = Join-Path $TUNNEL_CONFIG_DIR "$name.conf"
    @"
TUNNEL_NAME=$name
TUNNEL_MODE=$mode
LOCAL_PORT=$localPort
REMOTE_HOST=$remoteHost
REMOTE_PORT=$remotePort
SSH_SERVER=$sshServer
SSH_KEY=$keyDestPath
"@ | Set-Content $configPath
    
    # 创建服务脚本
    Create-ServiceScript
    
    # 创建服务
    Create-TunnelService -Name $name -ConfigFile $configPath
    
    # 如果监控服务不存在，创建它
    if (-not (Get-Service -Name "SSHTunnelMonitor" -ErrorAction SilentlyContinue)) {
        Create-MonitorScript
        Create-MonitorService
    }
    
    Write-Host "Tunnel '$name' setup completed"
}

# 启动隧道
function Start-SSHTunnel {
    param([string]$name)
    
    $serviceName = "SSHTunnel_$name"
    Start-Service -Name $serviceName
    Start-Service -Name "SSHTunnelMonitor"
    Write-Host "Started tunnel '$name'"
}

# 停止隧道
function Stop-SSHTunnel {
    param([string]$name)
    
    $serviceName = "SSHTunnel_$name"
    Stop-Service -Name $serviceName
    Write-Host "Stopped tunnel '$name'"
}

# 删除隧道
function Remove-SSHTunnel {
    param([string]$name)
    
    $serviceName = "SSHTunnel_$name"
    $configPath = Join-Path $TUNNEL_CONFIG_DIR "$name.conf"
    
    # 停止并删除服务
    Stop-Service -Name $serviceName -Force -ErrorAction SilentlyContinue
    sc.exe delete $serviceName
    
    # 删除配置文件
    Remove-Item -Path $configPath -Force -ErrorAction SilentlyContinue
    
    Write-Host "Removed tunnel '$name'"
}

# 列出所有隧道
function List-Tunnels {
    $tunnels = @()
    Get-ChildItem -Path $TUNNEL_CONFIG_DIR -Filter "*.conf" | ForEach-Object {
        $config = Get-Content $_.FullName | ConvertFrom-StringData
        $service = Get-Service -Name "SSHTunnel_$($config.TUNNEL_NAME)" -ErrorAction SilentlyContinue
        $tunnels += [PSCustomObject]@{
            Name = $config.TUNNEL_NAME
            Mode = $config.TUNNEL_MODE
            LocalPort = $config.LOCAL_PORT
            RemoteHost = $config.REMOTE_HOST
            RemotePort = $config.REMOTE_PORT
            SSHServer = $config.SSH_SERVER
            Status = if ($service) { $service.Status } else { "Not Installed" }
        }
    }
    
    if ($tunnels.Count -eq 0) {
        Write-Host "No tunnels configured"
    } else {
        $tunnels | Format-Table -AutoSize
    }
}

# 主命令处理
switch ($Command) {
    "setup" {
        $params = @{}
        for ($i = 0; $i -lt $Arguments.Count; $i++) {
            switch ($Arguments[$i]) {
                "-mode" { $params["mode"] = $Arguments[++$i] }
                "-localPort" { $params["localPort"] = $Arguments[++$i] }
                "-remoteHost" { $params["remoteHost"] = $Arguments[++$i] }
                "-remotePort" { $params["remotePort"] = $Arguments[++$i] }
                "-sshServer" { $params["sshServer"] = $Arguments[++$i] }
                "-sshKey" { $params["sshKey"] = $Arguments[++$i] }
                default {
                    if (-not $params.ContainsKey("name")) {
                        $params["name"] = $Arguments[$i]
                    }
                }
            }
        }
        Setup-Tunnel @params
    }
    "start" { Start-SSHTunnel -name $Arguments[0] }
    "stop" { Stop-SSHTunnel -name $Arguments[0] }
    "remove" { Remove-SSHTunnel -name $Arguments[0] }
    "list" { List-Tunnels }
    default {
        Write-Host @"
Usage:
    tunnel-manager.ps1 setup <name> -mode <L/R/D> -localPort <port> [-remoteHost <host>] [-remotePort <port>] -sshServer <server> -sshKey <path>
    tunnel-manager.ps1 start <name>
    tunnel-manager.ps1 stop <name>
    tunnel-manager.ps1 remove <name>
    tunnel-manager.ps1 list
"@
    }
} 