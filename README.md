# OpenClaw Production Deployment Guide

> 一份面向生产的 OpenClaw Docker 部署方案。从零搭建到稳定运行，每条经验都来自真实事故。

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

## 适用场景

- 单机 Linux 服务器（x86_64，4 核 / 4G 内存 / 80G 磁盘即可）
- 需要 Telegram 机器人 + 本地模型 / API 模型
- 需要出海代理（mihomo TUN 模式）
- 需要多 agent（main + guest）隔离运行

## 架构概览

```
宿主机
├── docker compose
│   ├── openclaw-gateway        网关主进程（会话编排、模型调度）
│   ├── mihomo-tun              代理 sidecar（TUN，共享 gateway netns）
│   ├── openclaw-recovery-watchdog  gateway 宕机兜底（15s）
│   └── 沙箱容器（按需自动重建）
│       ├── openclaw-sbx-workspace-<hash>      exec/read/write
│       └── openclaw-sbx-browser-workspace-<hash>  独立网络
```

**关键设计决策：**

- mihomo 以 `network_mode: service:gateway` 共享 netns，TUN 接管全量出站
- 沙箱 bind mount 真实 workspace，读写永远是最新版
- 配置热加载：改 `openclaw.json` 等待日志 `config hot reload applied`，不重启
- 浏览器按需启停，`status.running=false` 是空闲正常态

## 快速开始（3 分钟）

```bash
# 方式一：一键脚本
git clone https://github.com/CaamMori/openclaw-deploy.git
cd openclaw-deploy
bash scripts/quickstart.sh

# 方式二：手动步骤
# 1. 安装 OpenClaw
npm install -g openclaw && openclaw init

# 2. 创建目录
mkdir -p /data/{state/workspace,scripts,etc/openclaw,etc/mihomo,opt,backups}

# 3. 复制模板
cp templates/docker-compose.gateway.yml /data/scripts/
cp templates/openclaw.json /data/state/
cp templates/runtime.env.example /data/etc/openclaw/runtime.env
cp templates/mihomo-config.yaml /data/etc/mihomo/config.yaml

# 4. 替换 docker-compose 占位符
cd /data/scripts
gid=$(stat -c '%g' /var/run/docker.sock)
sed -i "s/YOUR_DOCKER_GROUP_ID/$gid/g" docker-compose.gateway.yml
ver=$(openclaw --version 2>/dev/null | grep -oP '[\d.]+' | head -1 || echo 'latest')
sed -i "s/YOUR_OPENCLAW_VERSION_HERE/$ver/g" docker-compose.gateway.yml
sed -i 's/YOUR_MIHOMO_VERSION_HERE/latest/g' docker-compose.gateway.yml

# 5. 编辑环境变量（填入你的 API key）
vim /data/etc/openclaw/runtime.env

# 6. 启动
docker compose -f docker-compose.gateway.yml up -d

# 6. 验证
openclaw health && openclaw doctor
```

## 目录结构

```
├── templates/                    配置模板
│   ├── docker-compose.gateway.yml   Docker Compose（YOUR_ 占位符）
│   ├── openclaw.json                Gateway 配置模板
│   ├── runtime.env.example          环境变量模板（带注释）
│   └── mihomo-config.yaml           代理配置模板
├── scripts/                      运维脚本
│   ├── quickstart.sh                一键初始化（交互式填 key）
│   ├── selfcheck.py                 22 项健康检查
│   ├── selfcheck-quick-cron.sh      cron 封装（调用 selfcheck.py）
│   ├── mihomo-guard.sh              代理节点自动切换
│   ├── ensure-browser.sh            Chromium 自愈
│   ├── ensure-telegram-alive.sh     Telegram 存活保活
│   ├── nightly-backup.sh            夜间备份
│   ├── pin-sbx-restart.sh           沙箱容器固定重启
│   └── entrypoint.sh                启动前锁清理（容器 entrypoint）
├── docs/                         详细文档
│   ├── architecture.md               架构详解
│   ├── deployment.md                 部署指南
│   ├── operations.md                 运维手册
│   ├── troubleshooting.md            排障指南
│   ├── gotchas.md                    踩坑记录（17 条铁律）
│   ├── backup-restore.md             备份与恢复
│   ├── multi-agent.md                多 agent 隔离运行
│   └── sandbox-permissions.md        沙箱权限说明
├── examples/                     示例配置
│   └── docker-compose.filled.yml     已填好的 Compose 对照样板
├── .github/workflows/           CI
│   └── ci.yml                        语法校验 + 密钥扫描
├── CONTRIBUTING.md
├── LICENSE                       MIT
└── README.md
```

## 运维脚本

| 脚本 | 用途 | 建议 cron |
|---|---|---|
| `selfcheck.py` | 22 项健康检查（支持 `--quick` 轻量 9 项、`--write-state` 写状态） | `*/10 * * * *` |
| `selfcheck-quick-cron.sh` | cron 封装，调用 `selfcheck.py --quick --write-state` | `*/10 * * * *` |

> **自检状态文件**：cron 每 10 分钟将结果写入 `/var/lib/openclaw/selfcheck-state.json`（含 timestamp、passed/failed 计数及逐项明细）。自检面板直接读取此文件，无需重新执行检查。
| `mihomo-guard.sh` | 代理故障自动切换 | `*/5 * * * *` |
| `ensure-browser.sh` | Chromium 自愈 | `*/10 * * * *` |
| `ensure-telegram-alive.sh` | Telegram 存活保活 | `*/5 * * * *` |
| `nightly-backup.sh` | 夜间备份 | `0 4 * * *` |
| `pin-sbx-restart.sh` | 沙箱容器固定重启 | 按需 |
| `entrypoint.sh` | 启动前锁清理 | 容器 entrypoint |
| `task-engine/taskctl.py` | 任务创建/运行/验收（含 `--accept`/`reset`） | 按需 |
| `task-engine/stale_guard.py` | 停滞看门狗（只读检测） | `17 */6 * * *` |
| `task-engine/stale_alert.sh` | 停滞告警（带去重） | `17 */6 * * *` |

## 必读文档

1. **[docs/architecture.md](docs/architecture.md)** - 架构与数据流
2. **[docs/operations.md](docs/operations.md)** - 日常运维
3. **[docs/gotchas.md](docs/gotchas.md)** - 踩坑记录（来自真实事故）
4. **[docs/troubleshooting.md](docs/troubleshooting.md)** - 排障指南
5. **[docs/deployment.md](docs/deployment.md)** - 部署详解
6. **[docs/backup-restore.md](docs/backup-restore.md)** - 备份与恢复
7. **[docs/multi-agent.md](docs/multi-agent.md)** - 多 agent 隔离运行
8. **[docs/sandbox-permissions.md](docs/sandbox-permissions.md)** - 沙箱权限说明

## 安全提醒

- `openclaw.json` 和 `runtime.env` 权限设为 600
- API key 走 `${ENV}` 变量，不硬编码
- Telegram allowFrom 仅限授权用户
- 配置 `gateway.bind` 设为 `127.0.0.1`

## License

[MIT](LICENSE)
