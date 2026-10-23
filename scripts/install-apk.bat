@echo off
chcp 65001 >nul
setlocal
cd /d "%~dp0"
title DartKeyMux 安装 / 更新 App

rem ===========================================================================
rem  把 app\app-release.apk 安装（覆盖安装）到手机。
rem
rem  用途：
rem    - 手机还没装 App，但不想跑完整的启动流程
rem    - 解压了新版本的压缩包，需要更新手机上的 App
rem    - App 出问题，想强制重装修复
rem
rem  参数：
rem    --no-pause   供 start-*.bat 调用，结束后不暂停
rem ===========================================================================

set "ADB=platform-tools\adb.exe"
set "APK=app\app-release.apk"
set "PKG=com.example.flutter_application_1"
set "LOG=%TEMP%\DartKeyMux-install.log"

set "NO_PAUSE="
if /i "%~1"=="--no-pause" set "NO_PAUSE=1"

echo ============================================================
echo   DartKeyMux 安装 / 更新 App
echo ============================================================
echo.
echo   本脚本会把 app\app-release.apk 覆盖安装到手机（保留 App 数据）。
echo.

if not exist "%APK%" (
  echo [错误] 缺少 %APK%
  echo        压缩包不完整，请重新解压后再试。
  goto :fail
)

if not exist "%ADB%" (
  echo [错误] 包内缺少 %ADB%
  echo        正常包是自带的。请先双击 start-amd64.bat（或 start-386.bat），
  echo        它会在 adb 缺失时引导你下载；下载完成后回到本脚本重试。
  goto :fail
)

echo [1/4] 启动 adb 服务 ...
"%ADB%" start-server >nul 2>&1
if errorlevel 1 (
  echo.
  echo [错误] adb 服务启动失败。常见原因与处理：
  echo         1. 端口 5037 被其它程序占用：关闭 Android Studio、手机助手等
  echo         2. adb 进程残留：执行 platform-tools\adb.exe kill-server 后重试
  goto :fail
)

echo [2/4] 检查手机连接 ...
call :check_device
if errorlevel 1 goto :fail
echo       手机连接正常。
echo.

echo [3/4] 安装 / 覆盖安装 App ...
echo       同版本也会重装（本脚本就是强制安装入口），安装会保留 App 数据。
"%ADB%" install -r "%APK%" >"%LOG%" 2>&1
set "RC=%ERRORLEVEL%"
type "%LOG%"
if not "%RC%"=="0" goto :install_failed

echo.
if defined NO_PAUSE (
  echo       安装完成：App 已覆盖安装到手机（数据保留）。
) else (
  echo [4/4] 完成。
  echo       App 已安装到手机，覆盖安装不会清空 App 数据。
  echo       接下来双击 start-amd64.bat（64 位系统）或 start-386.bat（32 位系统）启动。
  echo.
  pause
)
exit /b 0

rem ---------------------------------------------------------------------------
rem  安装失败：按 adb 的 Failure 错误码给出针对性指引
rem ---------------------------------------------------------------------------
:install_failed
echo.
echo [错误] App 安装失败，原因见上面的 Failure 行。
echo.

findstr /i /c:"INSTALL_FAILED_UPDATE_INCOMPATIBLE" "%LOG%" >nul 2>&1
if not errorlevel 1 (
  echo 原因：手机上已有「包名相同、签名不同」的 App，Android 拒绝覆盖安装。
  echo       常见于装过 debug 包、他人修改版，或从其它渠道装过同名包。
  echo 处理：先卸载旧版（会丢失该 App 的数据），再重新运行本脚本：
  echo         platform-tools\adb.exe uninstall %PKG%
  goto :fail
)

findstr /i /c:"INSTALL_FAILED_VERSION_DOWNGRADE" "%LOG%" >nul 2>&1
if not errorlevel 1 (
  echo 原因：手机上已装的版本比本包里的更新，Android 默认拒绝降级。
  echo 处理：换用更新的分发包；确实要降级可手动执行：
  echo         platform-tools\adb.exe install -r -d "%APK%"
  echo       注意 -d 强降级可能造成数据不兼容。
  goto :fail
)

findstr /i /c:"INSTALL_FAILED_USER_RESTRICTED" "%LOG%" >nul 2>&1
if not errorlevel 1 (
  echo 原因：手机系统限制了通过 USB 安装应用（小米/红米/部分国产 ROM 常见）。
  echo 处理：
  echo   1. 开发者选项里打开「USB 安装」或「通过 USB 安装应用」
  echo   2. 小米手机可能需要登录小米账号并等待授权
  echo   3. 部分机型需关闭「MIUI 优化」后重试
  goto :fail
)

findstr /i /c:"INSTALL_FAILED_INSUFFICIENT_STORAGE" "%LOG%" >nul 2>&1
if not errorlevel 1 (
  echo 原因：手机存储空间不足。
  echo 处理：清理空间后重试。
  goto :fail
)

findstr /i /c:"INSTALL_FAILED_ABORTED" "%LOG%" >nul 2>&1
if not errorlevel 1 (
  echo 原因：手机上取消了安装，或安装确认弹窗超时。
  echo 处理：保持手机解锁，重新运行本脚本，并在手机上点「允许 / 安装」。
  goto :fail
)

findstr /i /c:"INSTALL_FAILED_OLDER_SDK" "%LOG%" >nul 2>&1
if not errorlevel 1 (
  echo 原因：手机 Android 版本低于 App 要求的最低版本。
  echo 处理：换用支持该系统的旧版分发包。
  goto :fail
)

findstr /i /c:"INSTALL_FAILED_TEST_ONLY" "%LOG%" >nul 2>&1
if not errorlevel 1 (
  echo 原因：包内 APK 是 testOnly 构建，不能直接安装。
  echo 处理：属于打包流程问题，请反馈给分发者。
  goto :fail
)

echo 未识别的错误码，请按顺序排查：
echo   1. platform-tools\adb.exe devices 确认设备状态是 device
echo   2. 重新插拔数据线，并在手机上重新点「允许 USB 调试」
echo   3. 确认手机空间充足、系统未限制 USB 安装
echo   4. 换一根数据线 / 换一个 USB 口再试
echo.
echo 完整安装日志：%LOG%
goto :fail

rem ---------------------------------------------------------------------------
rem  失败收尾
rem ---------------------------------------------------------------------------
:fail
echo.
echo 处理完成后，重新双击本脚本即可；若是在启动流程中失败，也可重新双击 start-amd64.bat。
if not defined NO_PAUSE pause
exit /b 1

rem ---------------------------------------------------------------------------
rem  子过程：检查是否恰好有一台已授权的设备
rem ---------------------------------------------------------------------------
:check_device
set "DEV_COUNT=0"
set "DEV_ONLINE=0"
set "DEV_UNAUTH=0"
set "DEV_OFFLINE=0"
for /f "skip=1 tokens=1,2" %%A in ('%ADB% devices 2^>nul') do (
  if /i "%%B"=="device" (
    set /a DEV_COUNT+=1
    set "DEV_ONLINE=1"
  ) else if /i "%%B"=="unauthorized" (
    set /a DEV_COUNT+=1
    set "DEV_UNAUTH=1"
  ) else if /i "%%B"=="offline" (
    set /a DEV_COUNT+=1
    set "DEV_OFFLINE=1"
  )
)

if "%DEV_COUNT%"=="1" if "%DEV_ONLINE%"=="1" exit /b 0

echo.
echo [错误] 没有找到可用的手机。
echo.
echo        当前 adb 看到的设备：
echo        ------------------------------------------------
"%ADB%" devices
echo        ------------------------------------------------
echo.

if "%DEV_COUNT%"=="0" (
  echo 可能原因与处理：
  echo   1. 数据线只能充电或接触不良：换线 / 换 USB 口再试
  echo   2. 手机没开「开发者选项 → USB 调试」
  echo   3. 手机没点「允许 USB 调试」弹窗：解锁屏幕后重新插拔
  echo   4. Windows 缺驱动：设备管理器里检查是否有未知 Android 设备
) else if "%DEV_UNAUTH%"=="1" (
  echo 手机已连接，但未授权本电脑调试：
  echo   1. 点亮并解锁手机，在「允许 USB 调试吗？」弹窗点「允许」
  echo   2. 没看到弹窗：开发者选项里点「撤销 USB 调试授权」，再重新插拔
) else if "%DEV_OFFLINE%"=="1" (
  echo 手机处于 offline 状态：
  echo   1. 重新插拔数据线，或执行 platform-tools\adb.exe kill-server 后重试
  echo   2. 关闭其它正在占用 adb 的程序
) else if %DEV_COUNT% GTR 1 (
  echo 检测到多台设备，adb 无法确定操作哪一台：
  echo   1. 只保留一台手机连接后重试
)
echo.
exit /b 1
