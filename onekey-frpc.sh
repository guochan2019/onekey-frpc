#!/bin/bash
# ============================================================
# onekey-frpc — frp 客户端 (frpc) 一键安装/升级脚本
# 适用环境: Linux (amd64 / arm64 / arm)
# 首次运行 = 安装，再次运行 = 自动升级
# ============================================================
set -e

# ---------- 配置 ----------
INSTALL_DIR="/opt/frp"
BIN="/usr/local/bin/frpc"
FALLBACK_VER="v0.70.0"

# ---------- 彩色输出 ----------
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'
info()  { echo -e "${GREEN}[INFO]${NC} $1"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $1"; }
err()   { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }

# ---------- 检测 root ----------
if [ "$(id -u)" -ne 0 ]; then
  err "请以 root 用户运行 (当前非 root)"
fi

# ---------- 检测架构 ----------
info "检测系统架构..."
ARCH=$(uname -m)
case "$ARCH" in
  x86_64)  FRP_ARCH="amd64" ;;
  aarch64) FRP_ARCH="arm64" ;;
  armv7l)  FRP_ARCH="arm"   ;;
  *)       err "不支持的架构: ${ARCH} (仅支持 amd64 / arm64 / arm)" ;;
esac
info "  架构: ${ARCH} → frp_linux_${FRP_ARCH}"

# ---------- 获取最新版本 ----------
info "获取最新版本..."
LATEST_VER=$(curl -s --connect-timeout 5 \
  https://api.github.com/repos/fatedier/frp/releases/latest \
  | grep -o '"tag_name": *"[^"]*"' | grep -o 'v[^"]*' 2>/dev/null || echo "$FALLBACK_VER")
LATEST_NUM="${LATEST_VER#v}"  # v0.70.0 → 0.70.0
info "  最新版本: ${LATEST_VER}"

DOWNLOAD_URL="https://github.com/fatedier/frp/releases/download/${LATEST_VER}/frp_${LATEST_NUM}_linux_${FRP_ARCH}.tar.gz"

# =================== 判断模式：安装 vs 升级 ===================
if command -v frpc &>/dev/null; then
  # ---------- 升级模式 ----------
  CURRENT_VER=$(frpc --version 2>/dev/null | head -1 || echo "unknown")
  info "当前版本: ${CURRENT_VER}"

  if [ "${CURRENT_VER}" = "${LATEST_NUM}" ]; then
    info ""
    info "========== 已是最新版本 =========="
    info " frpc ${CURRENT_VER} 无需升级"
    info " 如需强制重装，请先卸载:"
    info "   systemctl stop frpc && rm -f ${BIN}"
    info "   然后重新运行此脚本"
    info "=================================="
    exit 0
  fi

  warn "发现新版本 ${CURRENT_VER} → ${LATEST_VER}"
  info "=== 开始升级 frpc ==="

  # 备份旧二进制（可选）
  cp "$BIN" "${BIN}.bak.$(date +%Y%m%d_%H%M%S)" 2>/dev/null || true

  # 下载
  TMPDIR=$(mktemp -d)
  cd "$TMPDIR"
  wget -q "$DOWNLOAD_URL" -O frp.tar.gz
  tar xzf frp.tar.gz
  EXTRACT_DIR=$(find . -maxdepth 1 -type d -name "frp_*" | head -1)
  [ -z "$EXTRACT_DIR" ] && err "解压后找不到 frp 目录"

  # 替换二进制
  cp "${EXTRACT_DIR}/frpc" "$BIN"
  chmod +x "$BIN"

  # 更新示例配置
  mkdir -p "$INSTALL_DIR"
  cp "${EXTRACT_DIR}/conf/frpc.toml" "${INSTALL_DIR}/frpc.example.toml" 2>/dev/null || true
  rm -rf "$TMPDIR"

  # 重启服务
  if systemctl is-active frpc &>/dev/null; then
    systemctl restart frpc
    info "  ✓ frpc 服务已重启"
  fi

  echo ""
  info "========== 升级完成 =========="
  info " frpc ${CURRENT_VER} → ${LATEST_VER}"
  info " 备份: ${BIN}.bak.$(date +%Y%m%d_%H%M%S)"
  info "================================"

else
  # ---------- 全新安装模式 ----------
  info "=== 开始安装 frpc ==="

  # 1) 下载
  info "下载 frp ${LATEST_VER}..."
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
  info "  ✓ frpc 已安装到 ${BIN}"

  # 2) 创建配置模板（仅首次）
  if [ ! -f "${INSTALL_DIR}/frpc.toml" ]; then
    info "创建配置模板..."
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

  # 3) 创建 systemd 服务
  info "创建 systemd 服务..."
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

  # 4) 验证
  FRPC_VER=$(frpc --version 2>/dev/null || echo "${LATEST_NUM}")
  info "  ✓ frpc 版本: ${FRPC_VER}"

  # 完成
  echo ""
  info "========== 安装完成 =========="
  info " frpc 版本:    ${LATEST_VER}"
  info " 安装目录:     ${INSTALL_DIR}/"
  info " 配置文件:     ${INSTALL_DIR}/frpc.toml    ← 请先编辑此文件"
  info " 管理地址:     http://127.0.0.1:7400"
  echo ""
  info "=== 下一步：配置并启动 ==="
  info "  1) 编辑配置文件:"
  info "     nano ${INSTALL_DIR}/frpc.toml"
  info "     至少修改: serverAddr、auth.token"
  info "     按需启用 [[proxies]] 段落"
  info ""
  info "  2) 启动 frpc:"
  info "     systemctl enable --now frpc"
  echo ""
  info "=== 常用命令 ==="
  info "  systemctl restart frpc   # 重启"
  info "  systemctl stop frpc      # 停止"
  info "  frpc reload              # 热加载配置"
  info "  frpc verify -c /opt/frp/frpc.toml  # 验证语法"
  info "  再次运行此脚本即可升级  # 一键升级"
fi
