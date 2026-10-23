# DartKeyMux 整合分发包

本包是 **DartKeyMux 前端（Flutter App）+ GoKeyMux 后端（Go 服务）** 的一键整合分发版本，
已内置 Android 调试桥（adb）与启动脚本，目标是「解压 → 双击 → 可用」。

> 需要 **USB 数据线**。无线网络延迟在音游场景不可接受，本项目强制走 ADB 反向端口转发。

---

## 一、使用前准备

1. 一台 Windows 电脑（**本包仅支持 Windows**，因为 GoKeyMux 后端是 Windows 独占程序）。
2. 一部 Android 手机，系统 API 21+（Android 5.0+）。
3. 一条数据线。
4. 手机开启**开发者选项 → USB 调试**。

## 二、三步跑起来

1. **解压** 整个 zip 到一个你记得住的目录（路径**不要有中文以外的奇怪字符**，也别放在需要管理员权限的目录，如 `C:\Program Files`）。
2. **用数据线连上手机**，手机上如弹出「允许 USB 调试吗？」请点**允许**。
3. **双击启动脚本**：
   - 64 位 Windows：`start-amd64.bat` ← **推荐，绝大多数电脑选这个**
   - 32 位 Windows：`start-386.bat`

脚本会自动依次做 4 件事，并在控制台打印进度：

```
[0/4] 首次运行会提示安装 FakerInput 输入引擎驱动（需要管理员权限，会弹 UAC）
      → 不想装可以直接关掉 UAC 窗口，脚本会跳过并继续
[1/4] 启动 adb 服务，并检查手机是否已连接、是否已授权
[2/4] adb reverse tcp:50051 tcp:50051   （把手机上的 50051 转发到电脑）
[3/4] 检查 App 是否已安装：已安装则跳过，没有才安装
[4/4] 启动后端 GoKeyMux（最小化到任务栏）
```

> **[3/4] 只在手机上还没有 App 时安装。** 重插数据线后重跑脚本不会重装，也不会打断正在运行的 App。
> 但脚本只能判断「装没装」，判断不了「是不是最新版」：解压了**新版本**的压缩包之后，
> 请先双击 `install-apk.bat` 更新 App，再双击启动脚本。

完成后，在手机上打开 **DartKeyMux** 应用，AppBar 右侧的指示灯变**绿**即表示已连上后端。

## 三、包内有什么

```
.
├── app/
│   └── app-release.apk                     ← 前端 Flutter App
├── backend/
│   ├── amd64/                              ← 64 位后端（GoKeyMux.exe + Interception/ + proto/ …）
│   └── 386/                                ← 32 位后端
├── platform-tools/                         ← Google 官方 adb（构建时下载，非仓库内置）
├── config.template.json                    ← 后端配置模板（脚本首次运行会复制过去）
├── install-fakerinput.ps1                  ← FakerInput 驱动静默安装脚本
├── get-adb.ps1                             ← adb 下载向导（仅当 platform-tools\ 缺失时才会用到）
├── install-apk.bat                         ← 强制安装 / 更新 App（保留数据）
├── start-amd64.bat                         ← 一键启动（64 位）
├── start-386.bat                           ← 一键启动（32 位）
└── README.md
```

**adb 已经打进包里，你不需要自己下 adb、也不需要梯子。** 万一 `platform-tools\`
被删掉或拿到的是旧包，双击启动脚本会弹出一个下载方式菜单让你自选来源：

| 选项 | 来源 | 说明 |
| --- | --- | --- |
| 1 | 腾讯云镜像 | 国内直连，推荐 |
| 2 | 阿里云镜像 | 国内直连 |
| 3 | Google 官方 | 国内通常需要梯子 |
| 4 | 我自己准备 | 手动把 `platform-tools\` 放进解压目录 |

本包的版本对齐关系：

| 项目 | 对应版本 |
| --- | --- |
| 前端 Flutter App（DartKeyMux） | 见本 release 说明或 `versions.env` 记录 |
| 后端 Go 服务（GoKeyMux） | 同上 |
| adb（Android platform-tools） | 构建时从国内镜像（腾讯云/阿里云）或 Google 拉取的最新版 |

## 四、常见问题

**Q：提示 `adb reverse` 失败 / `adb devices` 看不到设备？**
A：手机没连上或没授权。检查数据线是否插好、手机上是否点了「允许 USB 调试」，
   然后手动执行 `platform-tools\adb.exe devices` 确认能看到设备序列号。

**Q：拔了数据线再插上，App 又连不上了？**
A：**端口映射是每插拔一次就失效的。** 重新双击一次启动脚本即可。

**Q：安装 APK 报 `INSTALL_FAILED_UPDATE_INCOMPATIBLE`？**
A：手机上已经装了签名不同的同名应用。先手动卸载旧版 DartKeyMux，再重跑脚本。

**Q：FakerInput 驱动必须装吗？**
A：不是必须。它只影响后端选用 `fakerInput` 输入引擎的情况；
   后端的 `Interception` 与 `winput` 引擎不需要它。安装需要管理员权限与一次 UAC 确认。
   注意：**386 的后端资产里不含该驱动**，所以 32 位包不会提供自动安装。

**Q：后端要怎么改配置（目标游戏进程名、输入引擎等）？**
A：编辑 `backend\amd64\config.json`（首次运行由 `config.template.json` 生成）。
   常见项：
   - `driveName`：输入引擎，可选 `makc` / `winputWithWindow` / `winputWithInterception` / `fakerInput` / `noop`
   - `winputWindowProcessName`：默认 `Game.exe`，改成你游戏的进程名
   - `gRPCAddress`：默认 `localhost:50051`，**不要改端口**，除非前后端一起改
   - `logLevel`：`debug` / `info` / `warn` / `error`

**Q：双击脚本时弹出「包内没有检测到 adb」的菜单，选哪个？**
A：正常包是自带 adb 的，出现这个菜单说明 `platform-tools\` 缺失（被删或旧包）。
   直接回车用默认的**选项 1 腾讯云镜像**（国内直连）即可；也可以选 2 阿里云。
   选项 3 是 Google 官方，国内通常需要梯子。选项 4 供你自己准备 adb。

**Q：adb 下载失败怎么办？**
A：换一个源重试（优先腾讯云），或选选项 4 自己准备：
   到任意能访问的地方下载 `platform-tools-latest-windows.zip`，解压出 `platform-tools`
   文件夹，放到解压目录下（与 `start-amd64.bat` 同级），使存在
   `platform-tools\adb.exe`，再重新双击脚本。

**Q：后端窗口在哪？怎么退出后端？**
A：后端以后台最小化窗口启动，在任务栏里；关闭该窗口即退出后端。

**Q：启动脚本没提示安装 App，是不是没生效？**
A：不是。手机上已经装了 App 时，`[3/4]` 会显示「已安装，跳过安装」，这是刻意设计的：
   避免每次重插数据线重跑脚本都重装一次（重装会杀掉正在运行的 App）。

**Q：换了新版本的包，启动脚本会自动更新 App 吗？**
A：不会。启动脚本只判断「手机上有没有装」，判断不了「是不是最新版」。
   解压新版本的包后，请先双击 **`install-apk.bat`** 更新 App（覆盖安装，保留数据），
   再双击启动脚本。

**Q：想强制重装 / 修复 App？**
A：双击 **`install-apk.bat`**。它不判断版本，直接覆盖安装，适合修复或回滚到包内版本。

**Q：`install-apk.bat` 安装失败怎么办？**
A：它会把 adb 的失败原因翻成中文并给出处理办法，常见几类：
   - `INSTALL_FAILED_UPDATE_INCOMPATIBLE`：手机上装的是签名不同的同名 App，
     需要先卸载（会丢 App 数据）再装；
   - `INSTALL_FAILED_VERSION_DOWNGRADE`：手机上版本比包内新，Android 拒绝降级；
   - `INSTALL_FAILED_USER_RESTRICTED`：小米/红米等需在开发者选项里打开「USB 安装」；
   - `INSTALL_FAILED_INSUFFICIENT_STORAGE`：手机空间不足。
   脚本会把完整日志留在 `%TEMP%\DartKeyMux-install.log`。

## 五、端口约定

App 与后端双方都硬编码 **50051**：

- 前端：`DartKeyMux/flutter_application_1/lib/app_config.dart` → `grpcPort = 50051`
- 后端：`GoKeyMux/config.go` → `gRPCAddress = "localhost:50051"`
- 启动脚本：`adb reverse tcp:50051 tcp:50051`

三者必须一致，否则手机上的 App 无法连上电脑上的后端。

如果你不用启动脚本、自己在终端里执行反向映射，端口也必须写 **50051**：

```
platform-tools\adb.exe reverse tcp:50051 tcp:50051
```

写成别的端口（比如 50052）时，手机上的 App 并不知道，表现就是「脚本/命令都成功了，
但 App 一直是灰灯、连不上后端」。

## 六、不用启动脚本，手动启动

启动脚本本质上只做三件事：安装 App、`adb reverse`、启动后端。都可以手动完成：

1. **安装 / 更新 App**（手机还没装，或想更新时）：
   双击 `install-apk.bat`，或在命令行执行：

   ```
   platform-tools\adb.exe install -r app\app-release.apk
   ```

2. **建立端口反向映射**（每次插拔数据线后都要重做）：

   ```
   platform-tools\adb.exe reverse tcp:50051 tcp:50051
   ```

3. **启动后端**：双击 `backend\amd64\GoKeyMux.exe`（32 位系统用 `backend\386\GoKeyMux.exe`）。

最后在手机上打开 DartKeyMux。

> **端口必须一致。** `adb reverse` 的端口要和 App 内配置的 gRPC 端口完全相同（当前 `50051`）。
> 改端口时三处要一起改：App 的 `lib/app_config.dart`（`grpcPort`）、
> 后端 `config.json` 的 `gRPCAddress`、以及 `adb reverse` 命令。
> 只改其中一处，表现就是 App 指示灯一直不绿 / 连不上后端。

手动模式注意事项：

- `adb reverse` 会自动拉起 adb 服务，不需要单独执行 `start-server`；
- 手动启动后端不会自动生成 `config.json`，需要时把 `config.template.json`
  复制到 `backend\amd64\config.json`（32 位系统放 `backend\386\`）；
- 手动模式不做设备检查，报错时先看 `platform-tools\adb.exe devices` 的状态；
- 手动装 App 失败时，直接看命令行里的 `Failure [INSTALL_FAILED_...]`，对照上面 FAQ 处理。
