#!/bin/bash
# ============================================================
# onekey-frpc — frp 客户端 (frpc) 一键安装脚本
# 适用环境: Linux (amd64)
# 功能: 安装 frpc + 创建配置模板 + systemd 服务
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
ARCH=$(uname -m)
case "$ARCH" in
  x86_64)  FRP_ARCH="amd64" ;;
  aarch64) FRP_ARCH="arm64"  ;;
  armv7l)  FRP_ARCH="arm"    ;;
  *)       err "不支持的架构: ${ARCH} (仅支持 amd64 / arm64 / arm)" ;;
esac
info "系统架构: ${ARCH} → frp_linux_${FRP_ARCH}"

# =================== 1. 获取最新版本 ===================
info "=== 1/5 获取 frp 最新版本 ==="

LATEST_VER=$(curl -s --connect-timeout 5 \
  https://api.github.com/repos/fatedier/frp/releases/latest \
  | grep -o '"tag_name": *"[^"]*"' | grep -o 'v[^"]*' 2>/dev/null || echo "$FALLBACK_VER")
FRP_VER="${LATEST_VER}"
info "  最新版本: ${FRP_VER}"

# =================== 2. 下载 frp ===================
info "=== 2/5 下载 frp ${FRP_VER} ==="

DOWNLOAD_URL="https://github.com/fatedier/frp/releases/download/${FRP_VER}/frp_${FRP_VER#v}_linux_${FRP_ARCH}.tar.gz"
TMPDIR=$(mktemp -d)
cd "$TMPDIR"

wget -q "$DOWNLOAD_URL" -O frp.tar.gz
tar xzf frp.tar.gz
EXTRACT_DIR=$(find . -maxdepth 1 -type d -name "frp_*" | head -1)
if [ -z "$EXTRACT_DIR" ]; then
  err "解压后找不到 frp 目录"
fi

# 创建安装目录
mkdir -p "$INSTALL_DIR"

# 只复制 frpc 二进制
cp "${EXTRACT_DIR}/frpc" "$BIN"
chmod +x "$BIN"

# 复制示例配置作为参考
cp "${EXTRACT_DIR}/conf/frpc.toml" "${INSTALL_DIR}/frpc.example.toml" 2>/dev/null || true
cp -r "${EXTRACT_DIR}/conf" "${INSTALL_DIR}/conf.example" 2>/dev/null || true

rm -rf "$TMPDIR"

info "  ✓ frpc 已安装到 ${BIN}"
info "  ✓ 示例配置: ${INSTALL_DIR}/frpc.example.toml"

# =================== 3. 创建配置模板 ===================
info "=== 3/5 创建 frpc 配置模板 ==="

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
# webServer.user = "admin"
# webServer.password = "admin"

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
  info "  ✓ 已创建配置模板: ${INSTALL_DIR}/frpc.toml"
  info "  ⚠ 请编辑该文件，填入你的 frps 服务器地址和 token"
else
  info "  - 配置已存在，跳过创建"
fi

# =================== 4. 创建 systemd 服务 ===================
info "=== 4/5 创建 systemd 服务 ==="

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
info "  ✓ systemd 服务已创建: /etc/systemd/system/frpc.service"

# =================== 5. 验证 ===================
info "=== 5/5 验证 ==="

if command -v frpc &>/dev/null; then
  FRPC_VER=$(frpc --version 2>/dev/null || echo "${FRP_VER}")
  info "  ✓ frpc 版本: ${FRPC_VER}"
else
  err "  ✗ frpc 未找到，安装可能失败"
fi

# =================== 完成 ===================
echo ""
info "========== 安装完成 =========="
info " frpc 版本:    ${FRP_VER}"
info " 安装目录:     ${INSTALL_DIR}/"
info " 配置文件:     ${INSTALL_DIR}/frpc.toml    ← 请先编辑此文件"
info " 示例配置:     ${INSTALL_DIR}/frpc.example.toml"
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
info ""
info "  3) 查看状态:"
info "     systemctl status frpc"
info "     journalctl -u frpc -f"
echo ""
info "=== 常用命令 ==="
info "  systemctl restart frpc   # 重启"
info "  systemctl stop frpc      # 停止"
info "  frpc reload              # 热加载配置（不改端口的新代理生效）"
info "  frpc verify -c /opt/frp/frpc.toml  # 验证配置文件语法"
