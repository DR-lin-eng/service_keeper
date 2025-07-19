# Service Keeper

<div align="center">

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Shell](https://img.shields.io/badge/Shell-Bash-green.svg)](https://www.gnu.org/software/bash/)
[![Platform](https://img.shields.io/badge/Platform-Linux-blue.svg)](https://www.linux.org/)

**🚀 强大的Linux服务保活管理器**

一个功能完整的交互式服务管理脚本，支持多服务管理、自动保活、开机自启和实时监控。

[功能特性](#功能特性) • [快速开始](#快速开始) • [使用指南](#使用指南) • [高级功能](#高级功能) • [贡献](#贡献)

</div>

---

## 🌟 功能特性

### 核心功能
- **🎯 交互式管理** - 直观的菜单界面，轻松管理所有服务
- **📦 多服务支持** - 同时管理多个不同的服务命令
- **🔄 自动保活** - 智能检测服务状态，自动重启异常退出的服务
- **🚀 开机自启** - 集成SystemD，支持系统级开机自动启动
- **📊 实时监控** - 查看服务运行状态、PID信息和资源占用
- **📝 日志管理** - 每个服务独立日志文件，方便故障排查

### 管理功能
- ✅ 添加/删除服务
- ✅ 启动/停止/重启服务
- ✅ 查看服务状态列表
- ✅ 实时日志查看
- ✅ PID文件管理
- ✅ 配置文件管理

---

## 🚀 快速开始

### 一键安装并运行

```bash
# 方法1：直接下载运行
curl -fsSL https://raw.githubusercontent.com/DR-lin-eng/service_keeper/main/service_keeper.sh -o service_keeper.sh
chmod +x service_keeper.sh
./service_keeper.sh
```

```bash
# 方法2：克隆仓库
git clone https://github.com/DR-lin-eng/service_keeper.git
cd service_keeper
chmod +x service_keeper.sh
./service_keeper.sh
```

### 快速添加服务示例

启动脚本后，按照菜单提示：

```
请选择操作 [0-9]: 1
请输入服务名称: gost-relay
请输入要执行的命令: gost -L relay+phts://:50001
是否立即启动此服务? [y/N]: y
```

---

## 📖 使用指南

### 主菜单界面

```
==================== 服务保活管理器 ====================
1. 添加新服务
2. 启动服务
3. 停止服务
4. 重启服务
5. 查看服务状态
6. 查看服务日志
7. 删除服务
8. 设置开机自启
9. 取消开机自启
0. 退出
=======================================================
```

### 基本操作流程

#### 1. 添加服务
- 选择菜单项 `1`
- 输入服务名称（如：`nginx-proxy`）
- 输入完整命令（如：`nginx -g "daemon off;"`）
- 选择是否立即启动

#### 2. 管理服务
- **启动服务**：菜单项 `2`，选择要启动的服务
- **停止服务**：菜单项 `3`，选择要停止的服务
- **重启服务**：菜单项 `4`，自动停止后重新启动

#### 3. 监控服务
- **查看状态**：菜单项 `5`，显示所有服务的运行状态
- **查看日志**：菜单项 `6`，实时查看服务日志输出

#### 4. 开机自启
- **设置自启**：菜单项 `8`，创建SystemD服务
- **取消自启**：菜单项 `9`，移除SystemD配置

---

## 🔧 高级功能

### 服务保活监控

启动后台保活进程，每30秒检查一次服务状态：

```bash
# 启动保活监控（后台运行）
nohup ./service_keeper.sh --keep-alive > keeper.log 2>&1 &
```

### 批量自动启动

系统启动时自动启动所有配置的服务：

```bash
# 手动触发自动启动
./service_keeper.sh --autostart
```

### 文件结构

```
service_keeper/
├── service_keeper.sh    # 主脚本文件
├── services.conf        # 服务配置文件
├── pids/               # PID文件目录
│   └── *.pid
├── logs/               # 日志文件目录
│   └── *.log
└── README.md           # 说明文档
```

### 配置文件格式

`services.conf` 文件格式：
```
service_name1=command1
service_name2=command2
gost-relay=gost -L relay+phts://:50001
```

---

## 💡 使用场景

### 网络代理服务
```bash
服务名称: gost-proxy
命令: gost -L relay+phts://:50001
```

### Web应用服务
```bash
服务名称: webapp
命令: python3 /path/to/app.py
```

### 数据库服务
```bash
服务名称: redis-server
命令: redis-server /etc/redis/redis.conf
```

### 定时任务
```bash
服务名称: backup-service
命令: /bin/bash /path/to/backup.sh
```

---

## ⚙️ 系统要求

- **操作系统**: Linux (支持SystemD)
- **Shell**: Bash 4.0+
- **权限**: 普通用户权限（设置开机自启需要sudo）
- **依赖**: 标准Linux工具 (ps, kill, nohup等)

---

## 🤝 贡献

欢迎贡献代码！请遵循以下步骤：

1. Fork 本项目
2. 创建特性分支 (`git checkout -b feature/AmazingFeature`)
3. 提交更改 (`git commit -m 'Add some AmazingFeature'`)
4. 推送到分支 (`git push origin feature/AmazingFeature`)
5. 打开 Pull Request

### 开发计划

- [ ] 支持Docker容器服务管理
- [ ] Web界面管理
- [ ] 服务依赖关系管理
- [ ] 资源监控和告警
- [ ] 配置文件热重载

---

## 📄 许可证

本项目采用 MIT 许可证。详细信息请参见 [LICENSE](LICENSE) 文件。

---

## 🙋‍♂️ 支持

如果您遇到问题或有建议，请：

- 🐛 [提交Issue](https://github.com/DR-lin-eng/service_keeper/issues)
- 💬 [讨论区](https://github.com/DR-lin-eng/service_keeper/discussions)
- ⭐ 如果本项目对您有帮助，请给个Star！

---

## 📊 统计

<div align="center">

[![GitHub stars](https://img.shields.io/github/stars/DR-lin-eng/service_keeper.svg?style=social&label=Star)](https://github.com/DR-lin-eng/service_keeper)
[![GitHub forks](https://img.shields.io/github/forks/DR-lin-eng/service_keeper.svg?style=social&label=Fork)](https://github.com/DR-lin-eng/service_keeper/fork)

**让服务管理变得简单！**

</div>
