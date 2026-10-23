@echo off
rem ---------------------------------------------------------------------------
rem  UTF-8 batch on Chinese Windows: cmd decodes the .bat using the code page
rem  captured at process start (936), so an in-file "chcp 65001" only changes
rem  display, not parsing, and Chinese text eats the ASCII prefix of the next
rem  token ("'xxx' is not recognized"). Re-exec in a FRESH cmd process after
rem  switching the code page, then parse this file again from the top.
rem  Keep everything above :dkm_main ASCII-only.
rem ---------------------------------------------------------------------------
setlocal
if defined DKM_UTF8 goto :dkm_main
set "DKM_UTF8=1"
chcp 65001 >nul
cmd /c ""%~f0" %*"
exit /b %ERRORLEVEL%
:dkm_main
cd /d "%~dp0"
title DartKeyMux 一键启动 (amd64)

rem ===========================================================================
rem  解压即用：双击本脚本即可完成启动准备。
rem  目标机器：Windows amd64（x64）。旧 32 位系统请改用 start-386.bat
rem  前置条件：手机已开启「USB 调试」并用数据线连上电脑
rem
rem  关于 App 安装：
rem    本脚本只在「手机上还没有 App」时安装；已安装则跳过。
rem    所以重插数据线后重跑本脚本不会重装，也不会打断正在运行的 App。
rem    解压了【新版本】的压缩包之后，请先双击 install-apk.bat 更新 App。
rem ===========================================================================

set "ARCH=amd64"
set "APK=app\app-release.apk"
set "ADB=platform-tools\adb.exe"
set "PKG=com.example.flutter_application_1"
set "REVERSE_PORT=50051"
set "DRIVER=install-fakerinput.ps1"
set "CONFIG_SRC=config.template.json"
set "CONFIG_DST=backend\%ARCH%\config.json"

echo ============================================================
echo   DartKeyMux 一键启动（后端 GoKeyMux %ARCH% / gRPC 端口 %REVERSE_PORT%）
echo ============================================================
echo.
echo   本脚本会依次完成：
echo     [1/4] 启动 adb 服务，并检查手机连接
echo     [2/4] 建立端口反向映射（手机 → 电脑）
echo     [3/4] 检查 App 是否已安装（已装则跳过，不重复安装）
echo     [4/4] 启动后端 GoKeyMux
echo.
echo   前置条件：手机已开启「USB 调试」，并用数据线连上电脑。
echo   刚解压了新版本的包？请先双击 install-apk.bat 更新 App。
echo.

if not exist "%APK%" (
  echo [错误] 缺少 %APK%
  echo        压缩包不完整，请重新解压后再试。
  goto :fail
)
if not exist "backend\%ARCH%\GoKeyMux.exe" (
  echo [错误] 缺少 backend\%ARCH%\GoKeyMux.exe
  echo        压缩包不完整，请重新解压后再试。
  goto :fail
)

rem ---------------------------------------------------------------------------
rem  adb：包里已自带（构建时打进包），所以下面这段正常情况下不会触发。
rem  只有 platform-tools\ 缺失（被删除 / 拿到旧包）时，才让用户自己选下载源。
rem ---------------------------------------------------------------------------
if exist "%ADB%" goto :adb_ready

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
rem 容忍多敲的空格：set /p 会原样保留输入里的空格
set "ADB_CHOICE=%ADB_CHOICE: =%"

if "%ADB_CHOICE%"=="4" goto :adb_manual

set "ADB_URL="
if "%ADB_CHOICE%"=="1" set "ADB_URL=https://mirrors.cloud.tencent.com/AndroidSDK/platform-tools-latest-windows.zip"
if "%ADB_CHOICE%"=="2" set "ADB_URL=https://mirrors.aliyun.com/android.googlesource.com/platform-tools-latest-windows.zip"
if "%ADB_CHOICE%"=="3" set "ADB_URL=https://dl.google.com/android/repository/platform-tools-latest-windows.zip"
if not defined ADB_URL set "ADB_URL=https://mirrors.cloud.tencent.com/AndroidSDK/platform-tools-latest-windows.zip"

powershell -NoProfile -ExecutionPolicy Bypass -File "get-adb.ps1" -Url "%ADB_URL%"
if errorlevel 1 goto :adb_fail
if not exist "%ADB%" goto :adb_fail
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

echo [1/4] 启动 adb 服务并检查手机连接 ...
"%ADB%" start-server >nul 2>&1
if errorlevel 1 (
  echo.
  echo [错误] adb 服务启动失败。常见原因与处理：
  echo         1. 端口 5037 被其它程序占用：关闭 Android Studio、手机助手等
  echo         2. adb 进程残留：执行 platform-tools\adb.exe kill-server 后重试
  goto :fail
)

call :check_device
if errorlevel 1 goto :fail
echo       手机连接正常。
echo.

echo [2/4] 建立端口反向映射（手机 → 电脑）tcp:%REVERSE_PORT% ...
"%ADB%" reverse tcp:%REVERSE_PORT% tcp:%REVERSE_PORT%
if errorlevel 1 (
  echo.
  echo [错误] adb reverse 失败，手机无法连到电脑上的后端。
  echo        请按顺序排查：
  echo          1. platform-tools\adb.exe devices 里设备状态是 device
  echo          2. 手机上已点「允许 USB 调试」
  echo          3. 重新插拔数据线后再试；仍失败执行 adb kill-server 后重试
  echo.
  echo        手动执行同样命令可看到原始报错：
  echo          platform-tools\adb.exe reverse tcp:%REVERSE_PORT% tcp:%REVERSE_PORT%
  goto :fail
)
echo       端口映射已建立：手机上的 tcp:%REVERSE_PORT% → 本机 tcp:%REVERSE_PORT%
echo.

echo [3/4] 检查 App 是否已安装 ...
call :is_pkg_installed
if not errorlevel 1 goto :apk_installed

echo       手机上还没有 DartKeyMux，开始安装 ...
echo       （安装脚本会打印自己的进度，安装失败时会给出具体原因）
call "%~dp0install-apk.bat" --no-pause
if errorlevel 1 goto :install_failed
goto :apk_done

:apk_installed
echo       App 已安装，跳过安装。
echo       如果你是刚解压了新版本的压缩包，请先双击 install-apk.bat 更新 App，
echo       否则手机上仍然是旧版本。
goto :apk_done

:install_failed
echo.
echo [错误] App 安装失败。安装脚本已经给出了具体原因和处理办法，
echo        按提示处理后再重新双击本脚本。
goto :fail

:apk_done
echo.

echo [4/4] 启动后端 GoKeyMux ...
pushd "backend\%ARCH%"
start "GoKeyMux backend" /min "GoKeyMux.exe"
popd

echo.
echo ============================================================
echo   全部完成。现在可以在手机上打开 DartKeyMux 应用了。
echo ============================================================
echo   端口映射是「每插拔一次数据线就失效」的：重插线后请重新双击本脚本。
echo   重跑本脚本不会重装 App（已安装则跳过），正在运行的 App 不会被打断。
echo.
echo   若 App 一直连不上后端，请确认：
echo     - 上面 [2/4] 显示「端口映射已建立」
echo     - App 内设置的 gRPC 端口与反向映射端口一致（当前 %REVERSE_PORT%）
echo.
echo   若后端窗口一闪而过，说明 GoKeyMux.exe 启动失败：
echo     请手动双击 backend\%ARCH%\GoKeyMux.exe 查看报错，或检查同目录的 config.json。
echo.
echo   不使用本脚本时，也可以手动启动（详见包内 README「六、手动启动」）：
echo     1. 双击 backend\%ARCH%\GoKeyMux.exe
echo     2. 打开命令行，执行：
echo          platform-tools\adb.exe reverse tcp:%REVERSE_PORT% tcp:%REVERSE_PORT%
echo     反向映射的端口必须与 App 内设置完全一致，否则手机连不上后端。
echo.
echo   后端窗口已最小化到任务栏，关掉它即可退出后端。
echo.
pause
exit /b 0

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

rem ---------------------------------------------------------------------------
rem  子过程：手机上是否已安装本 App（只看「有没有」，不判断版本）
rem ---------------------------------------------------------------------------
:is_pkg_installed
set "PKG_PATH="
for /f "delims=" %%L in ('%ADB% shell pm path %PKG% 2^>nul') do set "PKG_PATH=%%L"
if defined PKG_PATH exit /b 0
exit /b 1

rem ---------------------------------------------------------------------------
rem  失败收尾
rem ---------------------------------------------------------------------------
:fail
echo.
echo 脚本中断，请按上面的提示处理后重试。
pause
exit /b 1
