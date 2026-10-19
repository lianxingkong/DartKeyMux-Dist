#!/usr/bin/env bash
#
# start.sh —— 占位脚本。
#
# 本分发包是 Windows 专用的：后端 GoKeyMux 明确为 "windows only"，
# 其 release 只提供 GoKeyMux-windows-amd64.zip / GoKeyMux-windows-386.zip，
# 没有 linux / macos 产物，因此没有对应的打包流程。
#
set -euo pipefail

cat >&2 <<'EOF'
[!] 这个包是 Windows 专用的。

    后端 GoKeyMux 只发布 Windows 构建（GoKeyMux-windows-amd64 / -386），
    本分发包也只随附 Windows 版 adb。

    Windows 用户请双击:
        start-amd64.bat   （64 位系统，推荐）
        start-386.bat     （32 位系统）

    非 Windows 用户只能手动补齐：自行编译后端 + 自备对应平台的 adb。
EOF
exit 1
