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
mkdir -p /data/{state/workspace,scripts,etc/openclaw,opt,backups}

# 3. 复制模板
cp templates/docker-compose.gateway.yml /data/scripts/
cp templates/openclaw.json /data/state/
cp templates/runtime.env.example /data/etc/openclaw/runtime.env

# 4. 编辑环境变量（填入你的 API key）
vim /data/etc/openclaw/runtime.env

# 5. 启动
cd /data/scripts && docker compose -f docker-compose.gateway.yml up -d

# 6. 验证
openclaw health && openclaw doctor
```

## 目录结构

```
├── templates/              配置模板
│   ├── docker-compose.gateway.yml   Docker Compose（YOUR_ 占位符）
│   ├── openclaw.json                Gateway 配置模板
│   ├── runtime.env.example          环境变量模板（带注释）
│   └── mihomo-config.yaml           代理配置模板
├── scripts/                运维脚本
│   ├── quickstart.sh        一键初始化
│   ├── selfcheck.py         22 项自检
│   ├── mihomo-guard.sh      代理节点自动切换
│   ├── ensure-browser.sh    Chromium 自愈
│   └── entrypoint.sh        启动锁清理
├── docs/                   详细文档
│   ├── architecture.md     架构详解
│   ├── operations.md       运维手册
│   ├── troubleshooting.md  排障指南
│   └── gotchas.md          踩坑记录（17 条铁律）
└── LICENSE                 MIT
```

## 运维脚本

| 脚本 | 用途 | 建议 cron |
|---|---|---|
| `selfcheck.py` | 22 项健康检查 | `*/10 * * * *` |
| `mihomo-guard.sh` | 代理故障自动切换 | `*/5 * * * *` |
| `ensure-browser.sh` | Chromium 恢复 | `*/10 * * * *` |
| `entrypoint.sh` | 启动前锁清理 | 容器 entrypoint |

## 必读文档

1. **[docs/architecture.md](docs/architecture.md)** - 架构与数据流
2. **[docs/operations.md](docs/operations.md)** - 日常运维
3. **[docs/gotchas.md](docs/gotchas.md)** - 踩坑记录（来自真实事故）
4. **[docs/troubleshooting.md](docs/troubleshooting.md)** - 排障指南

## 安全提醒

- `openclaw.json` 和 `runtime.env` 权限设为 600
- API key 走 `${ENV}` 变量，不硬编码
- Telegram allowFrom 仅限授权用户
- 配置 `gateway.bind` 设为 loopback

## License

[MIT](LICENSE)
