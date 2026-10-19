#!/usr/bin/env bash
#
# assemble.sh —— 把「前端 APK + 后端 Go 服务 + adb + 启动脚本」打成解压即用的 zip
#
# 用法:
#   ./scripts/assemble.sh [windows] [amd64|386] [version]
#
# 参数都可以省略，默认 windows + amd64 + versions.env 里的 PACKAGE_VERSION。
# 也可以只用环境变量驱动（CI 用的就是这种方式）:
#   ARCH=386 PACKAGE_VERSION_OVERRIDE=v1.0.0 ./scripts/assemble.sh
#
# 依赖: bash / curl / unzip / 以及 zip 或 tar(bsdtar) 其中之一
#
set -euo pipefail

# ---------------------------------------------------------------------------
# 参数与环境变量
# ---------------------------------------------------------------------------
PLATFORM="${1:-${PLATFORM:-windows}}"
ARCH="${2:-${ARCH:-amd64}}"
VERSION_OVERRIDE="${3:-}"

# ---------------------------------------------------------------------------
# 路径
# ---------------------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# shellcheck source=/dev/null
source "$ROOT/versions.env"

if [ -n "$VERSION_OVERRIDE" ]; then
  PACKAGE_VERSION="$VERSION_OVERRIDE"
fi
if [ -n "${PACKAGE_VERSION_OVERRIDE:-}" ]; then
  PACKAGE_VERSION="$PACKAGE_VERSION_OVERRIDE"
fi

# ---------------------------------------------------------------------------
# 校验
# ---------------------------------------------------------------------------
if [ "$PLATFORM" != "windows" ]; then
  echo "assemble.sh: 只支持 windows（GoKeyMux 后端为 Windows 独占，无 linux/macos 产物）" >&2
  echo "            传入的平台: $PLATFORM" >&2
  exit 1
fi

case "$ARCH" in
  amd64|386) ;;
  *) echo "assemble.sh: 未知架构 '$ARCH'（可选: amd64 386）" >&2; exit 1 ;;
esac

for v in FRONTEND_REPO FRONTEND_TAG FRONTEND_ASSET \
         BACKEND_REPO BACKEND_TAG BACKEND_ASSET_TEMPLATE \
         FAKERINPUT_MSI PACKAGE_VERSION; do
  if [ -z "${!v:-}" ]; then
    echo "assemble.sh: versions.env 缺少变量 $v" >&2
    exit 1
  fi
done

command -v curl >/dev/null 2>&1 || { echo "assemble.sh: 缺少依赖 'curl'" >&2; exit 1; }

# 解压器: 优先 unzip，退化到 tar（Windows 10+ 自带 tar.exe，Git Bash 里可直接用）
EXTRACTOR=""
if command -v unzip >/dev/null 2>&1; then
  EXTRACTOR="unzip"
elif command -v tar >/dev/null 2>&1; then
  EXTRACTOR="tar"
else
  echo "assemble.sh: 需要 'unzip' 或 'tar' 之一才能解压 release 资产" >&2
  exit 1
fi

# 解压 zip 到指定目录
extract_zip() { # zipfile destdir
  if [ "$EXTRACTOR" = "unzip" ]; then
    unzip -q "$1" -d "$2"
  else
    mkdir -p "$2"
    tar -x -f "$1" -C "$2"
  fi
}

# 打包器: 优先 zip；退化到 bsdtar。
# 注意 Git Bash 里 `tar` 是 GNU tar（打不了 zip），系统的 bsdtar 叫 /c/Windows/system32/tar.exe，
# 所以两者要分别探测。
is_bsdtar() { # command
  command -v "$1" >/dev/null 2>&1 || return 1
  "$1" --version 2>&1 | grep -qi 'bsdtar'
}

ZIPPER=""
ZIPPER_ARGS=()
if command -v zip >/dev/null 2>&1; then
  ZIPPER="zip"
elif is_bsdtar bsdtar; then
  ZIPPER="bsdtar"
elif is_bsdtar /c/Windows/system32/tar.exe; then
  ZIPPER="/c/Windows/system32/tar.exe"
elif is_bsdtar tar; then
  ZIPPER="tar"
else
  echo "assemble.sh: 需要 'zip' 或 bsdtar 才能产出 zip" >&2
  echo "             Git Bash 会自动用系统自带的 /c/Windows/system32/tar.exe（bsdtar）" >&2
  echo "             若仍失败，请改在 WSL 里运行，或安装 zip" >&2
  exit 1
fi

# 通用 curl 选项。
# --ssl-revoke-best-effort: Windows 用 schannel 时，若连不上证书吊销列表服务器
#   （CRYPT_E_REVOCATION_OFFLINE）会直接判定下载失败；加上它可"尽力而为"地继续。
#   在 Linux/macOS 的 curl 上该选项会被忽略，无副作用。
CURL_OPTS=(--ssl-revoke-best-effort --retry 3 --retry-delay 2 --retry-connrefused)

# 可选：给 curl 带上 token，提高速率上限（两个仓库都是 public，不配也能跑）。
#
# 注意：不要传本仓库的 GITHUB_TOKEN！它只对本仓库有效，拿去请求别的仓库的
# release 下载地址会返回 401（带无效凭据比匿名更糟）。只在有真正的 PAT 时才传。
CURL_AUTH=()
if [ -n "${PAT:-}" ]; then
  CURL_AUTH=(-H "Authorization: Bearer ${PAT}")
elif [ -n "${GITHUB_TOKEN:-}" ]; then
  CURL_AUTH=(-H "Authorization: Bearer ${GITHUB_TOKEN}")
elif [ -n "${GH_TOKEN:-}" ]; then
  CURL_AUTH=(-H "Authorization: Bearer ${GH_TOKEN}")
fi

# ---------------------------------------------------------------------------
# 辅助函数
# ---------------------------------------------------------------------------
asset_url() { # owner/repo tag asset
  echo "https://github.com/$1/releases/download/$2/$3"
}

# 先探一次，避免半路才发现资产不存在
check_asset() { # owner/repo tag asset
  local url
  url="$(asset_url "$1" "$2" "$3")"
  # -L 必须带：GitHub 的 release 下载 URL 会 302 跳到 blob 存储，--head 不跟随重定向
  if curl -fsSIL -o /dev/null "${CURL_OPTS[@]}" "${CURL_AUTH[@]}" "$url"; then
    echo "    ok  $3"
  else
    echo "assemble.sh: 资产不存在 —— $1@$2 里找不到 '$3'" >&2
    echo "             URL: $url" >&2
    echo "             请核对 versions.env，或该 release 的资产名是否已变更" >&2
    exit 1
  fi
}

fetch_asset() { # owner/repo tag asset destdir
  local url
  url="$(asset_url "$1" "$2" "$3")"
  echo "    get $3"
  curl -fsSL "${CURL_OPTS[@]}" "${CURL_AUTH[@]}" -o "$4/$3" "$url"
}

# ---------------------------------------------------------------------------
# 工作目录
# ---------------------------------------------------------------------------
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
PKG="$WORK/pkg"
mkdir -p "$PKG/app" "$PKG/platform-tools" "$PKG/backend/amd64" "$PKG/backend/386"

ADB_URL="https://dl.google.com/android/repository/platform-tools-latest-windows.zip"

echo "==> DartKeyMux-Dist 打包"
echo "    PACKAGE_VERSION = $PACKAGE_VERSION"
echo "    platform/arch   = $PLATFORM/$ARCH"
echo "    frontend        = $FRONTEND_REPO@$FRONTEND_TAG"
echo "    backend         = $BACKEND_REPO@$BACKEND_TAG"
echo ""

# ---------------------------------------------------------------------------
# 1. 前端 APK
# ---------------------------------------------------------------------------
echo "==> [1/4] 前端 APK"
check_asset "$FRONTEND_REPO" "$FRONTEND_TAG" "$FRONTEND_ASSET"
fetch_asset "$FRONTEND_REPO" "$FRONTEND_TAG" "$FRONTEND_ASSET" "$PKG/app"

# ---------------------------------------------------------------------------
# 2. 后端（两个架构都装进同一个包，用户按机器位数选启动脚本）
# ---------------------------------------------------------------------------
echo "==> [2/4] 后端 GoKeyMux"
MSI_FOUND=""
for arch in amd64 386; do
  be_asset="${BACKEND_ASSET_TEMPLATE//\{arch\}/$arch}"
  check_asset "$BACKEND_REPO" "$BACKEND_TAG" "$be_asset"
  fetch_asset "$BACKEND_REPO" "$BACKEND_TAG" "$be_asset" "$WORK"
  extract_zip "$WORK/$be_asset" "$PKG/backend/$arch"

  if [ ! -f "$PKG/backend/$arch/GoKeyMux.exe" ]; then
    echo "assemble.sh: $be_asset 解压后没有 GoKeyMux.exe —— 后端打包结构可能变了" >&2
    exit 1
  fi
  # 运行时依赖：Interception/ 提供 interception.dll，删掉后端会起不来
  if [ ! -d "$PKG/backend/$arch/Interception" ]; then
    echo "assemble.sh: 警告 —— $be_asset 里没有 Interception/ 目录" >&2
  fi
  if [ -f "$PKG/backend/$arch/$FAKERINPUT_MSI" ]; then
    MSI_FOUND="$arch"
    cp "$PKG/backend/$arch/$FAKERINPUT_MSI" "$PKG/$FAKERINPUT_MSI"
    echo "    FakerInput 驱动安装包来自 $arch 资产"
  fi
done

if [ -z "$MSI_FOUND" ]; then
  echo "assemble.sh: 警告 —— 哪个架构的资产里都没找到 $FAKERINPUT_MSI" >&2
  echo "             start-*.bat 的 FakerInput 自动安装会被跳过" >&2
fi

# ---------------------------------------------------------------------------
# 3. adb（Android platform-tools，构建时现拉，不入库）
# ---------------------------------------------------------------------------
echo "==> [3/4] adb (platform-tools-latest-windows)"
curl -fsSL "${CURL_OPTS[@]}" "${CURL_AUTH[@]}" -o "$WORK/pt.zip" "$ADB_URL"
extract_zip "$WORK/pt.zip" "$PKG"
if [ ! -f "$PKG/platform-tools/adb.exe" ]; then
  echo "assemble.sh: platform-tools 包里没有 adb.exe" >&2
  exit 1
fi

# ---------------------------------------------------------------------------
# 4. 启动脚本与说明
# ---------------------------------------------------------------------------
echo "==> [4/4] 启动脚本与 README"
cp "$ROOT/scripts/start-amd64.bat"        "$PKG/start-amd64.bat"
cp "$ROOT/scripts/start-386.bat"          "$PKG/start-386.bat"
cp "$ROOT/scripts/install-fakerinput.ps1" "$PKG/install-fakerinput.ps1"
[ -f "$ROOT/PACKAGE-README.md" ] && cp "$ROOT/PACKAGE-README.md" "$PKG/README.md"
[ -f "$ROOT/scripts/config.template.json" ] && cp "$ROOT/scripts/config.template.json" "$PKG/config.template.json"

# ---------------------------------------------------------------------------
# 打包
# ---------------------------------------------------------------------------
mkdir -p "$ROOT/dist"
ZIP_NAME="app-$PACKAGE_VERSION-windows-$ARCH.zip"
ZIP_ABS="$ROOT/dist/$ZIP_NAME"

rm -f "$ZIP_ABS"
(
  cd "$PKG"
  if [ "$ZIPPER" = "zip" ]; then
    zip -qr "$ZIP_ABS" .
  else
    # bsdtar 3.x：*.zip 后缀配合 -a 自动选 zip 格式，且保留目录结构
    "$ZIPPER" "${ZIPPER_ARGS[@]}" -a -c -f "$ZIP_ABS" ./*
  fi
)

echo ""
echo "==> 产出: dist/$ZIP_NAME"
if command -v du >/dev/null 2>&1; then
  echo "    大小: $(du -h "$ZIP_ABS" | cut -f1)"
fi
