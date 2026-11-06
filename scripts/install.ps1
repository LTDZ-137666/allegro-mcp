# install.ps1 — Allegro AI Bridge 一键安装脚本
# 用法: 右键 → "使用 PowerShell 运行"，或 PowerShell 中: .\install.ps1

$ErrorActionPreference = "Stop"
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path

Write-Host "========================================" -ForegroundColor Cyan
Write-Host " Allegro AI Bridge — 中件安装程序" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# ============================================================
# 1. 检测环境
# ============================================================
Write-Host "[1/6] 检测环境..." -ForegroundColor Yellow

# 1a. 检查 Python
$pythonCmd = $null
try {
    $pyVer = python --version 2>&1
    if ($LASTEXITCODE -eq 0) {
        $pythonCmd = "python"
        Write-Host "   Python: $pyVer" -ForegroundColor Green
    }
} catch {
    try {
        $pyVer = python3 --version 2>&1
        $pythonCmd = "python3"
        Write-Host "   Python: $pyVer" -ForegroundColor Green
    } catch {
        Write-Host "   ERROR: Python 3.10+ 未找到。请先安装 Python。" -ForegroundColor Red
        Write-Host "   下载地址: https://www.python.org/downloads/" -ForegroundColor Yellow
        exit 1
    }
}

# 检查 Python 版本 >= 3.10
$pyVersionStr = (& $pythonCmd -c "import sys; print(f'{sys.version_info.major}.{sys.version_info.minor}')") 2>&1
$pyMajor = [int]($pyVersionStr.Split('.')[0])
$pyMinor = [int]($pyVersionStr.Split('.')[1])
if ($pyMajor -lt 3 -or ($pyMajor -eq 3 -and $pyMinor -lt 10)) {
    Write-Host "   ERROR: 需要 Python 3.10+，当前版本: $pyVersionStr" -ForegroundColor Red
    exit 1
}

# 1b. 检查 pip
$pipCheck = & $pythonCmd -m pip --version 2>&1
if ($LASTEXITCODE -ne 0) {
    Write-Host "   ERROR: pip 不可用" -ForegroundColor Red
    exit 1
}
Write-Host "   pip: OK" -ForegroundColor Green

# 1c. 检测 Allegro 安装 (从注册表)
$allegroFound = $false
$pcbenvPath = $null
$cdsrootPath = $null

# 尝试从 HOME 环境变量获取 pcbenv
if ($env:HOME) {
    $pcbenvPath = Join-Path $env:HOME "pcbenv"
} elseif ($env:USERPROFILE) {
    # Allegro 通常把 HOME 设为 %USERPROFILE%
    $pcbenvPath = Join-Path $env:USERPROFILE "pcbenv"
}

# 从注册表查找 Cadence 安装
$regPaths = @(
    "HKLM:\SOFTWARE\Cadence Design Systems",
    "HKLM:\SOFTWARE\WOW6432Node\Cadence Design Systems"
)
foreach ($rp in $regPaths) {
    try {
        $cadence = Get-ItemProperty -Path $rp -ErrorAction SilentlyContinue
        if ($cadence) {
            Write-Host "   Cadence 注册表: 已找到" -ForegroundColor Green
            $allegroFound = $true
            break
        }
    } catch {}
}

# 尝试从 CDSROOT 环境变量
if (-not $allegroFound -and $env:CDSROOT) {
    $cdsrootPath = $env:CDSROOT
    Write-Host "   CDSROOT: $cdsrootPath" -ForegroundColor Green
    $allegroFound = $true
}

if (-not $allegroFound) {
    Write-Host "   WARNING: 未检测到 Cadence Allegro 安装" -ForegroundColor Yellow
    Write-Host "   将继续安装 Python 部分，但 DLL/SKILL 部署需要手动完成" -ForegroundColor Yellow
}

# 确保 pcbenv 目录存在
if ($pcbenvPath) {
    if (-not (Test-Path $pcbenvPath)) {
        New-Item -ItemType Directory -Path $pcbenvPath -Force | Out-Null
        Write-Host "   创建 pcbenv: $pcbenvPath" -ForegroundColor Green
    }
    Write-Host "   pcbenv: $pcbenvPath" -ForegroundColor Green
} else {
    Write-Host "   WARNING: 无法确定 pcbenv 路径 (HOME 未设置)" -ForegroundColor Yellow
    Write-Host "   请手动将 DLL 和 SKILL 脚本复制到 Allegro 的 skill 目录" -ForegroundColor Yellow
}

Write-Host ""

# ============================================================
# 2. 部署 DLL
# ============================================================
Write-Host "[2/6] 部署 Bridge DLL..." -ForegroundColor Yellow

$dllSource = Join-Path $scriptDir "dll\x86\allegro_ai_bridge.dll"
if (Test-Path $dllSource) {
    if ($pcbenvPath) {
        Copy-Item -Path $dllSource -Destination $pcbenvPath -Force
        Write-Host "   DLL → $pcbenvPath" -ForegroundColor Green
    }
    # 同时复制到 CDSROOT\tools\bin (备选)
    if ($cdsrootPath) {
        $toolsBin = Join-Path $cdsrootPath "tools\bin"
        if (Test-Path $toolsBin) {
            Copy-Item -Path $dllSource -Destination $toolsBin -Force
            Write-Host "   DLL → $toolsBin" -ForegroundColor Green
        }
    }
} else {
    Write-Host "   WARNING: DLL 未找到 ($dllSource)" -ForegroundColor Yellow
    Write-Host "   请确保 dll/x86/allegro_ai_bridge.dll 存在" -ForegroundColor Yellow
}

Write-Host ""

# ============================================================
# 3. 部署 SKILL 脚本
# ============================================================
Write-Host "[3/6] 部署 SKILL 脚本..." -ForegroundColor Yellow

$skillSource = Join-Path $scriptDir "skill"
if (Test-Path $skillSource) {
    if ($pcbenvPath) {
        Get-ChildItem $skillSource -Filter "*.il" | ForEach-Object {
            Copy-Item -Path $_.FullName -Destination $pcbenvPath -Force
            Write-Host "   SKILL → $pcbenvPath\$($_.Name)" -ForegroundColor Green
        }
    }

    # 检查并更新 allegro.ilinit
    if ($pcbenvPath) {
        $ilinit = Join-Path $pcbenvPath "allegro.ilinit"
        $loadLine = 'loadi("ai_bridge.il")'
        if (Test-Path $ilinit) {
            $content = Get-Content $ilinit -Raw -ErrorAction SilentlyContinue
            if ($content -notmatch [regex]::Escape($loadLine)) {
                Add-Content -Path $ilinit -Value "`n; AI Bridge auto-loaded by installer`n$loadLine`n"
                Write-Host "   allegro.ilinit: 已追加 loadi" -ForegroundColor Green
            } else {
                Write-Host "   allegro.ilinit: 已包含 ai_bridge (跳过)" -ForegroundColor Green
            }
        } else {
            Set-Content -Path $ilinit -Value "; Allegro IL init — AI Bridge auto-installed`n$loadLine`n"
            Write-Host "   allegro.ilinit: 已创建" -ForegroundColor Green
        }
    }
} else {
    Write-Host "   WARNING: skill/ 目录未找到" -ForegroundColor Yellow
}

Write-Host ""

# ============================================================
# 4. 安装 Python 包
# ============================================================
Write-Host "[4/6] 安装 Python MCP Server..." -ForegroundColor Yellow

& $pythonCmd -m pip install "$scriptDir" --quiet 2>&1
if ($LASTEXITCODE -ne 0) {
    Write-Host "   ERROR: pip install 失败" -ForegroundColor Red
    exit 1
}
Write-Host "   allegro-ai-bridge 已安装" -ForegroundColor Green

# 获取 python.exe 完整路径 (用于 MCP 配置)
$pythonFullPath = & $pythonCmd -c "import sys; print(sys.executable)" 2>&1
Write-Host "   Python: $pythonFullPath" -ForegroundColor Green

Write-Host ""

# ============================================================
# 5. 注册 Proma MCP 配置
# ============================================================
Write-Host "[5/6] 注册 Proma MCP 配置..." -ForegroundColor Yellow

$promaRoot = Join-Path $env:USERPROFILE ".proma\agent-workspaces"
$mcpEntry = @{
    command = $pythonFullPath
    args = @("-m", "allegro_mcp.server")
    timeout = 1800
    type = "stdio"
    enabled = $true
}

$registered = 0
if (Test-Path $promaRoot) {
    Get-ChildItem $promaRoot -Directory | ForEach-Object {
        $mcpJson = Join-Path $_.FullName "mcp.json"
        if (Test-Path $mcpJson) {
            try {
                $config = Get-Content $mcpJson -Raw | ConvertFrom-Json -ErrorAction Stop
                if (-not $config.servers) {
                    $config | Add-Member -MemberType NoteProperty -Name "servers" -Value @{} -Force
                }
                $config.servers | Add-Member -MemberType NoteProperty -Name "allegro-mcp" -Value $mcpEntry -Force
                $config | ConvertTo-Json -Depth 5 | Set-Content $mcpJson -Encoding UTF8
                Write-Host "   MCP 已注册: $mcpJson" -ForegroundColor Green
                $registered++
            } catch {
                Write-Host "   WARNING: 无法更新 $mcpJson — $_" -ForegroundColor Yellow
            }
        }
    }
}

if ($registered -eq 0) {
    Write-Host "   WARNING: 未找到 Proma 工作区 mcp.json" -ForegroundColor Yellow
    Write-Host "   请手动将以下配置添加到 mcp.json 的 servers 节:" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "   `"allegro-mcp`": {" -ForegroundColor Gray
    Write-Host "     `"command`": `"$pythonFullPath`"," -ForegroundColor Gray
    Write-Host "     `"args`": [`"-m`", `"allegro_mcp.server`"]," -ForegroundColor Gray
    Write-Host "     `"timeout`": 1800," -ForegroundColor Gray
    Write-Host "     `"type`": `"stdio`"," -ForegroundColor Gray
    Write-Host "     `"enabled`": true" -ForegroundColor Gray
    Write-Host "   }" -ForegroundColor Gray
}

Write-Host ""

# ============================================================
# 6. 验证
# ============================================================
Write-Host "[6/6] 验证安装..." -ForegroundColor Yellow

$allOk = $true

# 验证 pip 包
$pkgCheck = & $pythonCmd -m pip show allegro-ai-bridge 2>&1
if ($LASTEXITCODE -eq 0) {
    Write-Host "   pip 包: OK" -ForegroundColor Green
} else {
    Write-Host "   pip 包: FAILED" -ForegroundColor Red
    $allOk = $false
}

# 验证 DLL
if ($pcbenvPath) {
    $dllDest = Join-Path $pcbenvPath "allegro_ai_bridge.dll"
    if (Test-Path $dllDest) {
        Write-Host "   DLL: OK ($dllDest)" -ForegroundColor Green
    } else {
        Write-Host "   DLL: 未找到 (非关键)" -ForegroundColor Yellow
    }
}

# 验证 SKILL
if ($pcbenvPath) {
    $skillDest = Join-Path $pcbenvPath "ai_bridge.il"
    if (Test-Path $skillDest) {
        Write-Host "   SKILL: OK ($skillDest)" -ForegroundColor Green
    } else {
        Write-Host "   SKILL: 未找到 (非关键)" -ForegroundColor Yellow
    }
}

Write-Host ""

if ($allOk) {
    Write-Host "========================================" -ForegroundColor Green
    Write-Host "  安装成功！" -ForegroundColor Green
    Write-Host "========================================" -ForegroundColor Green
    Write-Host ""
    Write-Host "  使用步骤:" -ForegroundColor White
    Write-Host "  1. 启动 Cadence Allegro PCB Editor" -ForegroundColor White
    Write-Host "  2. 在 Allegro 命令行输入: ai_server_start" -ForegroundColor Cyan
    Write-Host "  3. 在 Proma 中即可用自然语言控制 Allegro" -ForegroundColor White
    Write-Host ""
    Write-Host "  卸载: 运行 uninstall.ps1" -ForegroundColor Gray
} else {
    Write-Host "安装部分完成，请检查上面的警告信息。" -ForegroundColor Yellow
}

# 暂停以便用户看到结果
Write-Host "按任意键退出..." -ForegroundColor Gray
$null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
