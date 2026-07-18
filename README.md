# onekey-frpc

一键在 Linux 上安装 [frp](https://github.com/fatedier/frp) 客户端 (frpc)，自动获取最新版本 + 生成配置模板 + 创建 systemd 服务。

---

## 快速开始

> ⚠️ 需要 root 权限。

```bash
# 方式一：一键直达（推荐）
bash <(wget -qO- https://raw.githubusercontent.com/guochan2019/onekey-frpc/main/onekey-frpc.sh)

# 方式二：git clone
git clone https://github.com/guochan2019/onekey-frpc.git
cd onekey-frpc
chmod +x onekey-frpc.sh
./onekey-frpc.sh
```

### 方式三：wget（仅公开仓库可用）

```bash
wget -qO- https://raw.githubusercontent.com/guochan2019/onekey-frpc/main/onekey-frpc.sh | bash
```

---

## 使用方式

运行脚本后显示菜单：

```
========================================
  frpc 一键安装/升级/卸载脚本
========================================

[INFO] 检测到 frpc 0.70.0 已安装

请选择操作：
  1. 安装 / 升级 frpc
  2. 卸载 frpc
  0. 退出
```

| 选项 | 功能 |
|------|------|
| **1** | 未安装 → 4 步完整安装；已安装 → 检测版本并升级 |
| **2** | 卸载：停止服务、删除二进制/配置 |
| **0** | 退出 |

## 安装流程

| 步骤 | 说明 |
|------|------|
| 检测 | 自动识别系统架构（amd64 / arm64 / arm / 386） |
| 1/4 | 下载并解压 frp，提取 frpc 二进制 |
| 2/4 | 创建配置模板 `/opt/frp/frpc.toml`（幂等，不覆盖已有配置） |
| 3/4 | 创建 systemd 服务 `frpc.service` |
| 4/4 | 显示完成信息 |

---

## 目录结构

```
/opt/frp/
├── frpc.toml              # 配置文件（需手动编辑）
├── frpc.example.toml      # 官方示例配置（参考用）
└── conf.example/          # 官方完整示例（参考用）

/usr/local/bin/frpc        # frpc 二进制
```

---

## 配置说明

安装完成后编辑 `/opt/frp/frpc.toml`，至少修改以下参数：

### 必填

| 参数 | 说明 | 示例 |
|------|------|------|
| `serverAddr` | frps 服务器 IP 或域名 | `"1.2.3.4"` |
| `serverPort` | frps 绑定的端口 | `7000` |
| `auth.token` | 认证令牌（与 frps 一致） | `"your-token"` |

### 代理示例（按需取消注释）

```toml
# SSH 隧道 — 暴露内网 SSH 到公网 6000 端口
[[proxies]]
name = "ssh"
type = "tcp"
localIP = "127.0.0.1"
localPort = 22
remotePort = 6000

# HTTP 服务 — 绑定域名
[[proxies]]
name = "web"
type = "http"
localIP = "127.0.0.1"
localPort = 80
customDomains = ["yourdomain.com"]

# UDP 服务 — 比如 DNS
[[proxies]]
name = "dns"
type = "udp"
localIP = "127.0.0.1"
localPort = 53
remotePort = 5300
```

更多代理类型（stcp / xtcp / tcpmux / plugin 等）参考配置模板中的注释或 [frp 官方文档](https://github.com/fatedier/frp)。

---

## 服务管理

```bash
# 启动
systemctl enable --now frpc

# 状态
systemctl status frpc

# 实时日志
journalctl -u frpc -f

# 重启
systemctl restart frpc

# 热加载（新增/修改代理，无需重启服务）
frpc reload

# 验证配置语法
frpc verify -c /opt/frp/frpc.toml
```

### 升级 / 卸载

再次运行脚本选择对应选项即可：

```bash
bash onekey-frpc.sh
# 选 1 → 升级；选 2 → 卸载
```

---

## 架构支持

| 架构 | 支持 |
|------|------|
| x86_64 (amd64) | ✅ |
| aarch64 (arm64) | ✅ |
| armv7l | ✅ |

---

## 许可证

本项目基于 [GPL-3.0](LICENSE) 协议。frp 本身同样遵循 GPL-3.0。
