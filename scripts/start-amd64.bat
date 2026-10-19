@echo off
chcp 65001 >nul
setlocal
cd /d "%~dp0"
title DartKeyMux 一键启动 (amd64)

rem ===========================================================================
rem  解压即用：双击本脚本即可完成全部 4 步。
rem  目标机器：Windows amd64（x64）。若你的电脑是旧 32 位系统，请改用 start-386.bat
rem  前置条件：手机已开启「USB 调试」并用数据线连上电脑
rem ===========================================================================

set "ARCH=amd64"
set "APK=app\app-release.apk"
set "REVERSE_PORT=50051"
set "DRIVER=install-fakerinput.ps1"
set "CONFIG_SRC=config.template.json"
set "CONFIG_DST=backend\%ARCH%\config.json"

echo ============================================================
echo   DartKeyMux 一键启动（后端 GoKeyMux %ARCH% / gRPC 端口 50051）
echo ============================================================
echo.

if not exist "platform-tools\adb.exe"      ( echo [错误] 缺少 platform-tools\adb.exe & goto :fail )
if not exist "%APK%"                       ( echo [错误] 缺少 %APK% & goto :fail )
if not exist "backend\%ARCH%\GoKeyMux.exe" ( echo [错误] 缺少 backend\%ARCH%\GoKeyMux.exe & goto :fail )

rem ---------------------------------------------------------------------------
rem  FakerInput 输入引擎驱动：首次使用需安装一次，需要管理员权限（会弹 UAC）
rem  这一步只影响 fakerInput 驱动；不装也能用 Interception / winput 等其它引擎
rem ---------------------------------------------------------------------------
if not exist "%DRIVER%" goto :skip_driver
if exist "backend\%ARCH%\fakerinput-installed.flag" goto :skip_driver

echo [0/4] FakerInput 驱动未安装，准备调用安装程序
echo        安装需要管理员权限，随后会弹出 UAC 窗口，请点「是」
echo        若你不想现在安装，可直接关掉 UAC 窗口，脚本会跳过并继续
echo.
powershell -NoProfile -ExecutionPolicy Bypass -File "%DRIVER%"
if errorlevel 1 (
  echo [提示] FakerInput 驱动未安装（可能被取消或失败）。
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
