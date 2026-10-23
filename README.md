# DartKeyMux-Dist

**DartKeyMux 的整合分发仓库。** 自身不含前端也不含后端代码，只做一件事：

> 从前端仓库与后端仓库各自的 GitHub Release 拉产物 → 连同 adb 与启动脚本打成一个
> zip → 作为本仓库的 Release 发布，让用户「解压即用」。

```
┌───────────────────────┐   Release    ┌──────────────────┐
│ lianxingkong/         │  app-release │                  │
│   DartKeyMux (前端)   │ ───────────► │                  │
└───────────────────────┘     .apk      │  DartKeyMux-Dist │   Release   ┌──────────────┐
                                       │   （本仓库）      │ ──────────► │ 用户下载解压  │
┌───────────────────────┐   Release    │                  │  windows    │ 双击 bat 即用 │
│ com-wuqi/GoKeyMux     │  GoKeyMux-   │  CI 校验版本对齐  │  amd64/386  └──────────────┘
│   （后端）            │  windows-*.zip│  CD 打包 + 发布  │
└───────────────────────┘ ───────────► └──────────────────┘
                              + adb（构建时下载）
```

## 仓库结构

```
.
├── .github/workflows/
│   ├── ci.yml                 # 版本表/脚本校验；手动触发时真跑一次打包
│   └── release.yml            # tag 或手动触发 → 打包 amd64+386 → 发布 release
├── scripts/
│   ├── assemble.sh            # ★ 唯一的打包逻辑，CI 与 CD 共用
│   ├── start-amd64.bat        # 包内启动脚本（64 位）
│   ├── start-386.bat          # 包内启动脚本（32 位）
│   ├── install-apk.bat        # 包内强制安装/更新 App（启动脚本只在未安装时才装）
│   ├── start.sh               # 非 Windows 占位说明
│   ├── install-fakerinput.ps1 # FakerInput 驱动静默安装（自动提权）
│   ├── get-adb.ps1            # adb 下载向导（包内 platform-tools\ 缺失时才触发）
│   └── config.template.json   # 后端配置模板
├── versions.env               # ★ 唯一需要人工维护的文件：前后端版本对齐
├── PACKAGE-README.md          # 会被复制进 zip 当作包内 README.md
└── README.md
```

## versions.env 是唯一真相源

```bash
FRONTEND_REPO="lianxingkong/DartKeyMux"   # 前端仓库（Flutter 代码在其 flutter_application_1/ 子目录）
FRONTEND_TAG="v1.1.2"                     # 前端 release tag
FRONTEND_ASSET="app-release.apk"          # 前端 release 里的 APK 资产名

BACKEND_REPO="com-wuqi/GoKeyMux"          # 后端仓库
BACKEND_TAG="v0.1.2"                      # 后端 release tag
BACKEND_ASSET_TEMPLATE="GoKeyMux-windows-{arch}.zip"   # {arch} → amd64 / 386

FAKERINPUT_MSI="FakerInput_Setup_0.1.1_x64.msi"
PACKAGE_VERSION="v1.0.0"                  # 本仓库产物版本号

ADB_MIRRORS=(                              # adb 下载源，按顺序尝试；前两个国内可直连
  "腾讯云镜像|https://mirrors.cloud.tencent.com/AndroidSDK/platform-tools-latest-windows.zip"
  "阿里云镜像|https://mirrors.aliyun.com/android.googlesource.com/platform-tools-latest-windows.zip"
  "Google 官方|https://dl.google.com/android/repository/platform-tools-latest-windows.zip"
)
```

**日常唯一要做的事**：前端或后端发新 release 后，改这里的两个 tag 并推 `main`，
CI 会自动校验「tag 存在 + 资产名对得上」。

## 版本与端口约定

| 项 | 约定 | 依据 |
| --- | --- | --- |
| gRPC / adb reverse 端口 | **50051** | 前端 `lib/app_config.dart`；后端 `config.go` 的 `GRPCAddress` |
| 平台 | **仅 Windows** | GoKeyMux 仓库描述即 "windows only"，release 只有 windows 资产 |
| 架构 | **amd64 + 386** | GoKeyMux release 同时提供两个架构 |
| 后端二进制 | `GoKeyMux.exe` | release zip 内实测 |
| 后端运行时依赖 | `Interception/`（含 `interception.dll`）、`proto/` | 必须随包保留，删掉后端起不来 |
| adb | 构建时从 `ADB_MIRRORS` 按序下载（腾讯云 → 阿里云 → Google），**打进包但不入库** | `platform-tools-latest-windows.zip` |

手动启动（不用脚本）时，反向映射端口同样必须是 **50051**：

```
platform-tools\adb.exe reverse tcp:50051 tcp:50051
```

端口写错的典型表现是「命令都成功了，但 App 连不上后端」。三处端口（App `grpcPort`、
后端 `gRPCAddress`、反代命令）必须同时改，详见 [PACKAGE-README.md](./PACKAGE-README.md) 第六节。

## 产物

每个架构各一个包，包内**同时**带有两个架构的后端（用户不必为位数挑包）：

```
app-<PACKAGE_VERSION>-windows-amd64.zip
app-<PACKAGE_VERSION>-windows-386.zip
SHA256SUMS
```

包内布局（`README.md` 内容见 [PACKAGE-README.md](./PACKAGE-README.md)）：

```
app/app-release.apk
backend/amd64/GoKeyMux.exe        + Interception/ + proto/ + …
backend/386/GoKeyMux.exe          + Interception/ + proto/ + …
platform-tools/adb.exe            ← adb 随包内置，用户零下载
config.template.json
install-fakerinput.ps1
get-adb.ps1                       ← 仅当 platform-tools\ 缺失时的下载向导
install-apk.bat                   ← 强制安装 / 更新 App（保留数据）
start-amd64.bat
start-386.bat
README.md
```

## 工作流

### 首次配置

1. 把本仓库推到 GitHub。
2. 在仓库 **Settings → Secrets and variables → Actions** 里加 `PAT`：
   - classic PAT 勾 `repo`，或 fine-grained PAT 对 `lianxingkong/DartKeyMux` 与
     `com-wuqi/GoKeyMux` 都给 **Contents: Read**。
   - 两个仓库都是 public，理论上不配也能跑（会退化用 `GITHUB_TOKEN`），
     但配了更稳、也不受匿名 API 速率限制影响。

### 发版

```bash
# 方式一：打 tag 自动发版（tag 会覆盖 PACKAGE_VERSION）
git tag v1.0.0 && git push --tags

# 方式二：Actions → Release → Run workflow，填 force_version
```

流程：`prepare` 解析版本 → `build` 矩阵打包 amd64/386 → `publish` 创建或更新 release。

## 本地自测

CI/CD 用的是 `assemble.sh`，本地同样可以真跑一遍（Windows 上请在 **Git Bash** 里执行，
本机若无 `unzip`/`zip`，脚本会自动退化用 Windows 自带的 `tar.exe`）：

```bash
# Git Bash
ARCH=amd64 ./scripts/assemble.sh
# 产出: dist/app-v1.0.0-windows-amd64.zip
```

`gh` 不是必需依赖：脚本用 `curl` 直接从
`https://github.com/<repo>/releases/download/<tag>/<asset>` 下载，
并在下载前先用 `curl -IL` 跟随 302 重定向确认资产存在，失败即报错退出（不会打出残缺包）。

## 维护备忘

- **改打包逻辑只改 `scripts/assemble.sh` 一处**，CI 与 CD 共用，避免两份逻辑漂移。
- adb 在构建时按 `ADB_MIRRORS` 顺序尝试下载（**腾讯云 → 阿里云 → Google**）并打进包，
  因此用户双击脚本即可用、不需要梯子。任一源失败会继续试下一个，全部失败才终止构建。
- `platform-tools-latest-*` 恒指向最新版 adb。若新版 adb 与老旧 Android 不兼容，
  需改成固定版本 URL，或把特定版本的 adb 入库。
- `assemble.sh` 解出的 `platform-tools/` 目录名由 Google 包结构保证，勿改。
- 只有当包内 `platform-tools\` 缺失时，`get-adb.ps1` 才会被启动脚本拉起（选项菜单换源）。
- 打包产物落在 `dist/`，已在 `.gitignore` 忽略。
- 后端首跑会在**后端自己的目录**生成 `config.json`（启动脚本用 `pushd` 保证），
  所以配置不会污染解压根目录。
- 启动脚本只在「手机上还没装 App」时安装（`adb shell pm path` 判断），已安装则跳过，
  避免每次重插数据线都重装、打断正在运行的 App。**新版本更新由 `install-apk.bat` 负责**，
  所以打包时务必带上它（`assemble.sh` 与 CI 冒烟清单都已包含）。
- 三个 bat（`start-amd64.bat`、`start-386.bat`、`install-apk.bat`）各自内嵌了设备检查逻辑；
  改判定规则或错误提示时，三处要一起改。
- 三个 bat 是 **UTF-8（无 BOM）+ CRLF**，顶部有一段“切代码页后在新 cmd 进程里重读自己”的
  自重启块（`:dkm_main`）。这是为了绕开中文 Windows 的坑：cmd 按进程启动时的代码页（936）
  解析 .bat，脚本里 `chcp 65001` 只改显示不改解析，UTF-8 中文会把后续 ASCII 前缀吃掉，
  表现为 `'xxx' is not recognized` 或乱码。**`:dkm_main` 之前只能放 ASCII**，别把中文移到前面，
  也别删掉这个块。
