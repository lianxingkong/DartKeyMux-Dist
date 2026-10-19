@echo off
chcp 65001 >nul
setlocal
cd /d "%~dp0"
title DartKeyMux 一键启动 (386)

rem ===========================================================================
rem  解压即用：双击本脚本即可完成全部 4 步。
rem  目标机器：Windows 386（32 位）。64 位系统请优先用 start-amd64.bat
rem  前置条件：手机已开启「USB 调试」并用数据线连上电脑
rem ===========================================================================

set "ARCH=386"
set "APK=app\app-release.apk"
set "REVERSE_PORT=50051"
set "DRIVER=install-fakerinput.ps1"
set "CONFIG_SRC=config.template.json"
set "CONFIG_DST=backend\%ARCH%\config.json"

echo ============================================================
echo   DartKeyMux 一键启动（后端 GoKeyMux %ARCH% / gRPC 端口 50051）
echo ============================================================
echo.

if not exist "%APK%"                       ( echo [错误] 缺少 %APK% & goto :fail )
if not exist "backend\%ARCH%\GoKeyMux.exe" ( echo [错误] 缺少 backend\%ARCH%\GoKeyMux.exe & goto :fail )

rem ---------------------------------------------------------------------------
rem  adb：包里已自带（构建时打进包），所以下面这段正常情况下不会触发。
rem  只有 platform-tools\ 缺失（被删除 / 拿到旧包）时，才让用户自己选下载源。
rem ---------------------------------------------------------------------------
if exist "platform-tools\adb.exe" goto :adb_ready

echo.
echo [提示] 包内没有检测到 adb（platform-tools\adb.exe）
echo        正常包是自带的；既然缺失，请选择下载方式：
echo.
echo          1. 腾讯云镜像下载（国内直连，推荐）
echo          2. 阿里云镜像下载
echo          3. Google 官方下载（国内通常需要梯子）
echo          4. 我自己准备 adb（手动放进 platform-tools\ 后重新双击本脚本）
echo.
set "ADB_CHOICE="
set /p "ADB_CHOICE=请输入 1-4 后回车 [默认 1]: "
if not defined ADB_CHOICE set "ADB_CHOICE=1"

if "%ADB_CHOICE%"=="4" goto :adb_manual

set "ADB_URL="
if "%ADB_CHOICE%"=="1" set "ADB_URL=https://mirrors.cloud.tencent.com/AndroidSDK/platform-tools-latest-windows.zip"
if "%ADB_CHOICE%"=="2" set "ADB_URL=https://mirrors.aliyun.com/android.googlesource.com/platform-tools-latest-windows.zip"
if "%ADB_CHOICE%"=="3" set "ADB_URL=https://dl.google.com/android/repository/platform-tools-latest-windows.zip"
if not defined ADB_URL set "ADB_URL=https://mirrors.cloud.tencent.com/AndroidSDK/platform-tools-latest-windows.zip"

powershell -NoProfile -ExecutionPolicy Bypass -File "get-adb.ps1" -Url "%ADB_URL%"
if errorlevel 1 goto :adb_fail
if not exist "platform-tools\adb.exe" goto :adb_fail
echo [提示] adb 已就绪。
echo.
goto :adb_ready

:adb_manual
echo.
echo   请把解压出来的 platform-tools 文件夹放到本目录（与本脚本同级），
echo   使本目录下存在 platform-tools\adb.exe，然后重新双击本脚本。
echo.
pause
exit /b 1

:adb_fail
echo.
echo [错误] adb 下载失败。可换一个源重试（推荐选项 1 腾讯云镜像），
echo        或按选项 4 自行准备 adb 放进 platform-tools\ 目录。
echo.
pause
exit /b 1

:adb_ready

rem ---------------------------------------------------------------------------
rem  FakerInput 输入引擎驱动：需要管理员权限（会弹 UAC），只影响 fakerInput 引擎
rem  注意：386 架构的后端资产里不包含该 msi，若包内没有会自动跳过
rem ---------------------------------------------------------------------------
if not exist "%DRIVER%" goto :skip_driver
if exist "backend\%ARCH%\fakerinput-installed.flag" goto :skip_driver

echo [0/4] 检查 FakerInput 驱动 ...
echo        若需要安装会弹出 UAC 窗口，请点「是」；不想装可直接关掉，脚本会继续
echo.
powershell -NoProfile -ExecutionPolicy Bypass -File "%DRIVER%"
if errorlevel 1 (
  echo [提示] FakerInput 驱动未安装（被取消、失败，或包里没有该安装包）。
  echo        不影响本脚本继续运行；只有后端选用 fakerInput 引擎时才需要它。
) else (
  echo. > "backend\%ARCH%\fakerinput-installed.flag"
  echo [提示] FakerInput 驱动已就绪。
)
echo.
:skip_driver

rem ---------------------------------------------------------------------------
rem  首次运行生成后端 config.json（放在后端目录里，避免污染解压目录根）
rem ---------------------------------------------------------------------------
if not exist "%CONFIG_DST%" if exist "%CONFIG_SRC%" (
  copy /y "%CONFIG_SRC%" "%CONFIG_DST%" >nul
  echo [提示] 已生成 backend\%ARCH%\config.json，可直接编辑该文件调整后端行为
  echo.
)

echo [1/4] 启动 adb 服务 ...
"platform-tools\adb.exe" start-server
if errorlevel 1 goto :fail

echo [2/4] 端口反向映射 tcp:%REVERSE_PORT% ^(手机 -^> 电脑^) ...
"platform-tools\adb.exe" reverse tcp:%REVERSE_PORT% tcp:%REVERSE_PORT%
if errorlevel 1 (
  echo.
  echo [错误] adb reverse 失败。最常见原因是手机没连上或没开 USB 调试。
  echo        请检查：
  echo          1^) 数据线已连接，且手机上已点「允许 USB 调试」
  echo          2^) 执行 platform-tools\adb.exe devices 应该能看到你的设备
  echo.
  goto :fail
)

echo [3/4] 安装 / 更新 App ...
"platform-tools\adb.exe" install -r "%APK%"
if errorlevel 1 (
  echo.
  echo [错误] APK 安装失败。若提示 INSTALL_FAILED_UPDATE_INCOMPATIBLE，
  echo        说明手机上已装有签名不同的同包名应用，请先手动卸载旧版再重试。
  echo.
  goto :fail
)

echo [4/4] 启动后端 GoKeyMux ...
pushd "backend\%ARCH%"
start "GoKeyMux backend" /min "GoKeyMux.exe"
popd

echo.
echo ============================================================
echo   全部完成。现在可以在手机上打开 DartKeyMux 应用了。
echo ============================================================
echo   端口映射是「每插拔一次数据线就失效」的：重插线后请重新双击本脚本。
echo   后端窗口已最小化到任务栏，关掉它即可退出后端。
echo.
pause
exit /b 0

:fail
echo.
echo 脚本中断，请按上面的提示处理后重试。
pause
exit /b 1
