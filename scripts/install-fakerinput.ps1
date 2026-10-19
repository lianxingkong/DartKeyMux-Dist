# install-fakerinput.ps1 —— 静默安装 FakerInput 输入引擎驱动
#
# 由 start-amd64.bat / start-386.bat 调用。
# 需要管理员权限；未提权时会自动弹 UAC 重新拉起自己。
# 退出码: 0 = 已安装/已存在/找不到安装包, 1 = 安装被取消或失败
#
# 注意：本文件保持纯 ASCII 输出，避免 Windows PowerShell 5.1 读取 UTF-8
#       无 BOM 文件时中文乱码（中文提示统一放在 .bat 里）。

[CmdletBinding()]
param(
    [string]$MsiPath
)

$ErrorActionPreference = 'Stop'

function Test-Admin {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    $p = New-Object Security.Principal.WindowsPrincipal($id)
    return $p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

if (-not $MsiPath -or $MsiPath -eq '') {
    $MsiPath = (Get-ChildItem -Path $PSScriptRoot -Filter 'FakerInput_Setup_*.msi' -File |
                Select-Object -First 1 -ExpandProperty FullName)
}

if (-not $MsiPath -or -not (Test-Path -LiteralPath $MsiPath)) {
    Write-Host '[fakerinput] no installer found in package root - skipped.'
    exit 0
}

# --- 已经装过就不再走 UAC -----------------------------------------------------
$installed = Get-ItemProperty -Path `
    'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*', `
    'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*' `
    -ErrorAction SilentlyContinue |
    Where-Object { $_.DisplayName -like '*FakerInput*' }

if ($installed) {
    Write-Host ("[fakerinput] already installed: " + $installed[0].DisplayName)
    exit 0
}

# --- 未提权则弹 UAC 重新拉起自己 ----------------------------------------------
if (-not (Test-Admin)) {
    Write-Host '[fakerinput] requesting administrator rights (UAC prompt)...'
    $argList = @(
        '-NoProfile',
        '-ExecutionPolicy', 'Bypass',
        '-File', ('"' + $PSCommandPath + '"'),
        '-MsiPath', ('"' + $MsiPath + '"')
    )
    try {
        $proc = Start-Process -FilePath 'powershell.exe' -ArgumentList $argList -Verb RunAs -Wait -PassThru
    } catch {
        Write-Host '[fakerinput] elevation was cancelled or failed.'
        exit 1
    }
    exit $proc.ExitCode
}

# --- 已提权：静默安装 ---------------------------------------------------------
Write-Host ("[fakerinput] installing silently: " + $MsiPath)
$msiArgs = @('/i', ('"' + $MsiPath + '"'), '/qn', '/norestart')
$proc = Start-Process -FilePath 'msiexec.exe' -ArgumentList $msiArgs -Wait -PassThru
if ($proc.ExitCode -eq 0 -or $proc.ExitCode -eq 3010) {
    Write-Host ("[fakerinput] install finished, exit code " + $proc.ExitCode + ".")
    exit 0
}
Write-Host ("[fakerinput] msiexec failed, exit code " + $proc.ExitCode + ".")
exit 1
