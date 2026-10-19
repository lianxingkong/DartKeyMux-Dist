# get-adb.ps1 -- download Android platform-tools and install into .\platform-tools
#
# Called by start-amd64.bat / start-386.bat ONLY when the package is missing
# platform-tools\adb.exe (a normal package ships adb pre-bundled, so this
# wizard usually never runs). The caller presents a menu and passes -Url.
#
# Exit codes: 0 = adb.exe is in place, 1 = download or extraction failed
#
# NOTE: this file is intentionally ASCII-only. Chinese prompts live in the
#       .bat (code page 65001 + UTF-8), because Windows PowerShell 5.1
#       mis-decodes UTF-8 without BOM and would print mojibake here.

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$Url,
    [string]$Destination
)

$ErrorActionPreference = 'Stop'

if (-not $Destination -or $Destination -eq '') {
    $Destination = Join-Path $PSScriptRoot 'platform-tools'
}

Write-Host ("[adb] download source: " + $Url)
Write-Host ("[adb] target dir     : " + $Destination)

$tmpRoot = Join-Path ([IO.Path]::GetTempPath()) ("dkm-adb-" + [Guid]::NewGuid().ToString('N'))
$zipPath = Join-Path $tmpRoot 'platform-tools.zip'
New-Item -ItemType Directory -Force -Path $tmpRoot | Out-Null

function Expand-ZipArchive {
    param([string]$Zip, [string]$Dest)
    $ErrorActionPreference = 'Stop'
    if (Test-Path $Dest) { Remove-Item -Recurse -Force $Dest }
    New-Item -ItemType Directory -Force -Path $Dest | Out-Null
    if (Get-Command Expand-Archive -ErrorAction SilentlyContinue) {
        Expand-Archive -LiteralPath $Zip -DestinationPath $Dest -Force
    } else {
        Add-Type -AssemblyName System.IO.Compression.FileSystem
        [IO.Compression.ZipFile]::ExtractToDirectory($Zip, $Dest)
    }
}

try {
    # --- download -----------------------------------------------------------
    $oldProgress = $ProgressPreference
    $ProgressPreference = 'SilentlyContinue'   # Invoke-WebRequest 的进度条会拖慢下载
    try {
        Invoke-WebRequest -Uri $Url -OutFile $zipPath -UseBasicParsing -TimeoutSec 600
    } finally {
        $ProgressPreference = $oldProgress
    }
    $sizeMB = [math]::Round((Get-Item $zipPath).Length / 1MB, 1)
    Write-Host ("[adb] downloaded " + $sizeMB + " MB")

    # --- extract ------------------------------------------------------------
    $extractRoot = Join-Path $tmpRoot 'x'
    Expand-ZipArchive -Zip $zipPath -Dest $extractRoot

    $src = Join-Path $extractRoot 'platform-tools'
    if (-not (Test-Path (Join-Path $src 'adb.exe'))) {
        # 有些镜像的包内层多套一层目录，兜底递归找一次
        $found = Get-ChildItem -Path $extractRoot -Recurse -Filter 'adb.exe' -File -ErrorAction SilentlyContinue |
                 Select-Object -First 1
        if (-not $found) { throw 'downloaded archive does not contain platform-tools/adb.exe' }
        $src = $found.Directory.FullName
    }

    if (Test-Path $Destination) { Remove-Item -Recurse -Force $Destination }
    Move-Item -LiteralPath $src -Destination $Destination -Force

    if (-not (Test-Path (Join-Path $Destination 'adb.exe'))) {
        throw 'adb.exe not found after install'
    }

    Write-Host '[adb] installed successfully.'
    exit 0
} catch {
    Write-Host ("[adb] FAILED: " + $_.Exception.Message)
    exit 1
} finally {
    if (Test-Path $tmpRoot) { Remove-Item -Recurse -Force $tmpRoot -ErrorAction SilentlyContinue }
}
