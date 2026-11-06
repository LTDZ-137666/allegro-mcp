# uninstall.ps1 — Allegro AI Bridge 一键卸载脚本
# 用法: 右键 → "使用 PowerShell 运行"，或 PowerShell 中: .\uninstall.ps1

$ErrorActionPreference = "Continue"
Write-Host "========================================" -ForegroundColor Cyan
Write-Host " Allegro AI Bridge — 卸载程序" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# ============================================================
# 1. 卸载 Python 包
# ============================================================
Write-Host "[1/4] 卸载 Python 包..." -ForegroundColor Yellow

$pythonCmd = $null
try { python --version 2>&1 | Out-Null; $pythonCmd = "python" } catch {
    try { python3 --version 2>&1 | Out-Null; $pythonCmd = "python3" } catch {}
}

if ($pythonCmd) {
    $pkgCheck = & $pythonCmd -m pip show allegro-ai-bridge 2>&1
    if ($LASTEXITCODE -eq 0) {
        & $pythonCmd -m pip uninstall allegro-ai-bridge -y 2>&1 | Out-Null
        Write-Host "   allegro-ai-bridge 已卸载" -ForegroundColor Green
    } else {
        Write-Host "   allegro-ai-bridge 未安装 (跳过)" -ForegroundColor Gray
    }
} else {
    Write-Host "   Python 未找到 (跳过 pip 卸载)" -ForegroundColor Yellow
}

Write-Host ""

# ============================================================
# 2. 删除 SKILL 脚本和 DLL
# ============================================================
Write-Host "[2/4] 清理 SKILL 脚本和 DLL..." -ForegroundColor Yellow

# 确定 pcbenv 路径
$pcbenvPath = $null
if ($env:HOME) { $pcbenvPath = Join-Path $env:HOME "pcbenv" }
elseif ($env:USERPROFILE) { $pcbenvPath = Join-Path $env:USERPROFILE "pcbenv" }

if ($pcbenvPath -and (Test-Path $pcbenvPath)) {
    $filesToRemove = @("ai_bridge.il", "layout.il", "allegro_ai_bridge.dll")
    foreach ($f in $filesToRemove) {
        $fp = Join-Path $pcbenvPath $f
        if (Test-Path $fp) {
            Remove-Item $fp -Force
            Write-Host "   已删除: $fp" -ForegroundColor Green
        }
    }
} else {
    Write-Host "   pcbenv 路径未找到 (跳过)" -ForegroundColor Gray
}

# 同时清理 CDSROOT\tools\bin
if ($env:CDSROOT) {
    $toolsBin = Join-Path $env:CDSROOT "tools\bin\allegro_ai_bridge.dll"
    if (Test-Path $toolsBin) {
        Remove-Item $toolsBin -Force
        Write-Host "   已删除: $toolsBin" -ForegroundColor Green
    }
}

Write-Host ""

# ============================================================
# 3. 从 allegro.ilinit 移除 loadi 行
# ============================================================
Write-Host "[3/4] 清理 allegro.ilinit..." -ForegroundColor Yellow

if ($pcbenvPath) {
    $ilinit = Join-Path $pcbenvPath "allegro.ilinit"
    if (Test-Path $ilinit) {
        $lines = Get-Content $ilinit
        $newLines = $lines | Where-Object {
            $_ -notmatch 'ai_bridge\.il' -and
            $_ -notmatch 'AI Bridge auto-loaded'
        }
        if ($newLines.Count -ne $lines.Count) {
            $newLines | Set-Content $ilinit
            Write-Host "   allegro.ilinit: 已清理 ai_bridge 引用" -ForegroundColor Green
        } else {
            Write-Host "   allegro.ilinit: 无 ai_bridge 引用 (跳过)" -ForegroundColor Gray
        }
    }
}

Write-Host ""

# ============================================================
# 4. 从 mcp.json 移除 allegro-mcp
# ============================================================
Write-Host "[4/4] 清理 Proma MCP 配置..." -ForegroundColor Yellow

$promaRoot = Join-Path $env:USERPROFILE ".proma\agent-workspaces"
if (Test-Path $promaRoot) {
    Get-ChildItem $promaRoot -Directory | ForEach-Object {
        $mcpJson = Join-Path $_.FullName "mcp.json"
        if (Test-Path $mcpJson) {
            try {
                $config = Get-Content $mcpJson -Raw | ConvertFrom-Json -ErrorAction Stop
                if ($config.servers -and $config.servers.PSObject.Properties['allegro-mcp']) {
                    $config.servers.PSObject.Properties.Remove('allegro-mcp')
                    $config | ConvertTo-Json -Depth 5 | Set-Content $mcpJson -Encoding UTF8
                    Write-Host "   MCP 已移除: $mcpJson" -ForegroundColor Green
                }
            } catch {
                Write-Host "   WARNING: 无法处理 $mcpJson" -ForegroundColor Yellow
            }
        }
    }
}

Write-Host ""
Write-Host "========================================" -ForegroundColor Green
Write-Host "  卸载完成！" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Green

Write-Host "按任意键退出..." -ForegroundColor Gray
$null = $Host.UI.RawUI.Key
