#!/bin/bash
# ============================================================
# onekey-frpc — frp 客户端 (frpc) 一键安装/升级/卸载脚本
# 适用环境: Linux (amd64 / arm64 / arm)
# ============================================================
set -e

trap 'echo -e "\033[0;31m[ERROR] 脚本执行失败，请检查:\033[0m
  - 网络连接（能否访问 github.com）
  - 是否以 root 运行
  - 系统架构是否支持" >&2' ERR

# ---------- 配置 ----------
INSTALL_DIR="/opt/frp"
BIN="/usr/local/bin/frpc"
FALLBACK_VER="v0.70.0"

# ---------- 彩色输出 ----------
GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'
info()  { echo -e "${GREEN}[INFO]${NC} $1"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $1"; }
err()   { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }

# ---------- 检测 root ----------
if [ "$(id -u)" -ne 0 ]; then
  err "请以 root 用户运行 (当前非 root)"
fi

# ---------- 检测架构 ----------
detect_arch() {
  case "$(uname -m)" in
    x86_64)  echo "amd64" ;;
    aarch64) echo "arm64" ;;
    armv7l)  echo "arm"   ;;
    i386|i686) echo "386" ;;
    *)       echo ""       ;;
  esac
}

# ---------- 获取最新版本 ----------
fetch_latest_ver() {
  curl -s --connect-timeout 5 \
    https://api.github.com/repos/fatedier/frp/releases/latest \
    | grep -o '"tag_name": *"[^"]*"' | grep -o 'v[^\"]*' 2>/dev/null || echo ""
}

# ---------- 获取当前版本 ----------
get_current_ver() {
  if ! command -v frpc &>/dev/null; then
    echo ""; return
  fi
  frpc --version 2>/dev/null | head -1 || echo ""
}

# ---------- 卸载 ----------
uninstall_frpc() {
  echo ""
  warn "========== 卸载 frpc =========="
  echo ""
  systemctl stop frpc 2>/dev/null || true
  systemctl disable frpc 2>/dev/null || true
  rm -f /etc/systemd/system/frpc.service
  systemctl daemon-reload
  rm -f "$BIN"
  rm -rf "$INSTALL_DIR"
  info "✓ frpc 已卸载"
  info "  配置目录 ${INSTALL_DIR} 已删除"
  echo ""
  exit 0
}

# ---------- 安装 ----------
do_install() {
  LUCKY_VER="$1"
  FRP_ARCH="$2"
  LATEST_NUM="${LUCKY_VER#v}"

  info "=== 1/4 下载 frp ${LUCKY_VER} ==="
  DOWNLOAD_URL="https://github.com/fatedier/frp/releases/download/${LUCKY_VER}/frp_${LATEST_NUM}_linux_${FRP_ARCH}.tar.gz"
  TMPDIR=$(mktemp -d)
  cd "$TMPDIR"
  wget -q "$DOWNLOAD_URL" -O frp.tar.gz
  tar xzf frp.tar.gz
  EXTRACT_DIR=$(find . -maxdepth 1 -type d -name "frp_*" | head -1)
  [ -z "$EXTRACT_DIR" ] && err "解压后找不到 frp 目录"

  mkdir -p "$INSTALL_DIR"
  cp "${EXTRACT_DIR}/frpc" "$BIN"
  chmod +x "$BIN"
  cp "${EXTRACT_DIR}/conf/frpc.toml" "${INSTALL_DIR}/frpc.example.toml" 2>/dev/null || true
  cp -r "${EXTRACT_DIR}/conf" "${INSTALL_DIR}/conf.example" 2>/dev/null || true
  rm -rf "$TMPDIR"
  info "  ✓ frpc 已安装"

  info "=== 2/4 创建配置模板 ==="
  if [ ! -f "${INSTALL_DIR}/frpc.toml" ]; then
    cat > "${INSTALL_DIR}/frpc.toml" << 'CONFIGEOF'
# ============================================================
# frpc 配置文件
# 请根据实际情况修改以下参数
# ============================================================

# frps 服务器地址
serverAddr = "your-server-ip"
serverPort = 7000

# 认证令牌（需与 frps 的 auth.token 一致）
auth.method = "token"
auth.token = "your-token"

# 日志
log.to = "./frpc.log"
log.level = "info"
log.maxDays = 3

# 管理地址（用于 reload / 查看状态）
webServer.addr = "127.0.0.1"
webServer.port = 7400

# 传输层
transport.poolCount = 5
transport.protocol = "tcp"

# ============================================================
# 代理配置示例
# 取消注释并根据需要修改即可启用
# ============================================================

# --- SSH 隧道 ---
# [[proxies]]
# name = "ssh"
# type = "tcp"
# localIP = "127.0.0.1"
# localPort = 22
# remotePort = 6000

# --- HTTP 服务 ---
# [[proxies]]
# name = "web"
# type = "http"
# localIP = "127.0.0.1"
# localPort = 80
# customDomains = ["yourdomain.com"]

# --- HTTPS 服务 ---
# [[proxies]]
# name = "web_https"
# type = "https"
# localIP = "127.0.0.1"
# localPort = 443
# customDomains = ["yourdomain.com"]

# --- UDP 服务 ---
# [[proxies]]
# name = "dns"
# type = "udp"
# localIP = "127.0.0.1"
# localPort = 53
# remotePort = 5300
CONFIGEOF
    info "  ✓ 已创建: ${INSTALL_DIR}/frpc.toml"
    info "  ⚠ 请编辑该文件，填入你的 frps 服务器地址和 token"
  else
    info "  - 配置已存在，保留不变"
  fi

  info "=== 3/4 创建 systemd 服务 ==="
  cat > /etc/systemd/system/frpc.service << 'SERVICEEOF'
[Unit]
Description=frp client (frpc) - reverse proxy agent
Documentation=https://github.com/fatedier/frp
After=network.target

[Service]
Type=simple
WorkingDirectory=/opt/frp
ExecStart=/usr/local/bin/frpc -c /opt/frp/frpc.toml
Restart=on-failure
RestartSec=5
LimitNOFILE=65536

[Install]
WantedBy=multi-user.target
SERVICEEOF
  systemctl daemon-reload
  info "  ✓ systemd 服务已创建"

  info "=== 4/4 完成 ==="
  info ""
  info "========== 安装完成 =========="
  info " frpc 版本:    ${LUCKY_VER}"
  info " 安装目录:     ${INSTALL_DIR}/"
  info " 配置文件:     ${INSTALL_DIR}/frpc.toml    ← 请先编辑此文件"
  info " 管理地址:     http://127.0.0.1:7400"
  info ""
  info "=== 启动命令 ==="
  info "  systemctl enable --now frpc"
  info ""
  info "再次运行脚本可升级或卸载 frpc"
  info ""
}

# ---------- 升级 ----------
do_upgrade() {
  LUCKY_VER="$1"
  FRP_ARCH="$2"
  LATEST_NUM="${LUCKY_VER#v}"
  CURRENT_VER="$3"

  info "=== 升级 frpc: ${CURRENT_VER} → ${LUCKY_VER} ==="

  DOWNLOAD_URL="https://github.com/fatedier/frp/releases/download/${LUCKY_VER}/frp_${LATEST_NUM}_linux_${FRP_ARCH}.tar.gz"

  # 备份旧二进制
  cp "$BIN" "${BIN}.bak.$(date +%Y%m%d_%H%M%S)" 2>/dev/null || true

  TMPDIR=$(mktemp -d)
  cd "$TMPDIR"
  wget -q "$DOWNLOAD_URL" -O frp.tar.gz
  tar xzf frp.tar.gz
  EXTRACT_DIR=$(find . -maxdepth 1 -type d -name "frp_*" | head -1)
  [ -z "$EXTRACT_DIR" ] && err "解压后找不到 frp 目录"

  cp "${EXTRACT_DIR}/frpc" "$BIN"
  chmod +x "$BIN"

  mkdir -p "$INSTALL_DIR"
  cp "${EXTRACT_DIR}/conf/frpc.toml" "${INSTALL_DIR}/frpc.example.toml" 2>/dev/null || true
  rm -rf "$TMPDIR"

  if systemctl is-active frpc &>/dev/null; then
    systemctl restart frpc
    info "  ✓ frpc 服务已重启"
  fi

  info ""
  info "========== 升级完成 =========="
  info " ${CURRENT_VER} → ${LUCKY_VER}"
  info " 备份: ${BIN}.bak.*"
  info "================================"
}

# =================== 主菜单 ===================
echo ""
echo "========================================"
echo "  frpc 一键安装/升级/卸载脚本"
echo "  https://github.com/fatedier/frp"
echo "========================================"
echo ""

FRP_ARCH=$(detect_arch)
[ -z "$FRP_ARCH" ] && err "不支持的架构: $(uname -m) (仅支持 amd64 / arm64 / arm / 386)"

INSTALLED=false
CURRENT_VER=$(get_current_ver)
if [ -f "$BIN" ]; then
  INSTALLED=true
  if [ -n "$CURRENT_VER" ]; then
    info "检测到 frpc ${CURRENT_VER} 已安装"
  else
    info "检测到 frpc 已安装（版本未知）"
  fi
else
  info "frpc 未安装"
fi

echo ""
echo "请选择操作："
echo "  1. 安装 / 升级 frpc"
echo "  2. 卸载 frpc"
echo "  0. 退出"
echo ""
read -p "请输入选项 (0-2): " ACTION
echo ""

case "$ACTION" in
  2)
    uninstall_frpc
    ;;
  0)
    info "已退出"
    exit 0
    ;;
  1|"")
    LATEST_VER=$(fetch_latest_ver)
    if [ -z "$LATEST_VER" ]; then
      LATEST_VER="$FALLBACK_VER"
      warn "GitHub API 不可用，使用后备版本 ${FALLBACK_VER}"
    fi

    if [ "$INSTALLED" = true ]; then
      LATEST_NUM="${LATEST_VER#v}"
      if [ -n "$CURRENT_VER" ] && [ "$CURRENT_VER" = "$LATEST_NUM" ]; then
        info "当前版本: ${CURRENT_VER}"
        info "✓ 已是最新版本，无需更新"
        exit 0
      fi
      do_upgrade "$LATEST_VER" "$FRP_ARCH" "$CURRENT_VER"
    else
      do_install "$LATEST_VER" "$FRP_ARCH"
    fi
    ;;
  *)
    err "无效选项: ${ACTION}"
    ;;
esac
