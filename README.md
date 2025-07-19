# Service Keeper

<div align="center">

![Service Keeper Logo](https://img.shields.io/badge/Service-Keeper-blue?style=for-the-badge&logo=linux)

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Shell](https://img.shields.io/badge/Shell-Bash-green.svg)](https://www.gnu.org/software/bash/)
[![Platform](https://img.shields.io/badge/Platform-Linux-blue.svg)](https://www.linux.org/)
[![Version](https://img.shields.io/badge/Version-2.2-red.svg)](https://github.com/DR-lin-eng/service_keeper)

**🚀 专业级Linux服务保活管理器**

一个功能完备的交互式服务管理解决方案，支持多命令服务、智能保活、自动日志管理和动态配置。

[快速开始](#-快速开始) • [功能特性](#-功能特性) • [使用指南](#-使用指南) • [高级功能](#-高级功能) • [FAQ](#-常见问题)

</div>

---

## 🌟 功能特性

### 🎯 核心功能
- **🔄 多命令服务管理** - 一个服务可包含多个独立运行的命令
- **⚡ 智能保活机制** - 30秒检查周期，自动重启异常退出的服务
- **📊 实时状态监控** - 详细的PID、运行时间、资源占用监控
- **🎨 交互式界面** - 直观的菜单系统，支持二级管理界面
- **🔧 动态配置管理** - 运行时添加、删除、修改服务命令

### 📝 日志管理
- **📁 智能日志轮转** - 可配置大小限制（默认1M）
- **🗂️ 多级备份机制** - 支持0-10个历史备份文件
- **🧹 自动清理功能** - 后台自动检查和清理超大日志
- **👁️ 实时日志监控** - 支持tail -f式实时查看

### 🚀 系统集成
- **🏁 开机自启动** - SystemD服务集成
- **🛡️ 进程独立运行** - 使用nohup确保服务不依赖管理器
- **⚙️ 配置持久化** - 所有设置自动保存和恢复
- **🔒 安全权限管理** - 支持普通用户和sudo权限

---

## 🚀 快速开始

### 一键安装

```bash
# 方法1：直接下载
curl -fsSL https://raw.githubusercontent.com/DR-lin-eng/service_keeper/main/service_keeper.sh -o service_keeper.sh
chmod +x service_keeper.sh

# 方法2：克隆仓库
git clone https://github.com/DR-lin-eng/service_keeper.git
cd service_keeper
chmod +x service_keeper.sh
```

### 启动管理器

```bash
./service_keeper.sh
```

### 快速配置示例

1. **创建你的第一个服务**
   ```
   选择: 1 (添加新服务)
   服务名称: gost-proxy
   命令1: gost -L relay+phts://:50001
   命令2: gost -L relay+phts://:50002
   ```

2. **启动保活守护进程**
   ```
   选择: 9 (启动保活守护进程)
   ```

3. **设置开机自启**（可选）
   ```
   选择: 12 (设置开机自启)
   ```

---

## 📖 使用指南

### 主界面功能

```
====================== 服务保活管理器 ======================
1. 添加新服务          ← 创建新的多命令服务
2. 管理现有服务        ← 动态编辑服务配置
3. 启动服务           ← 批量启动服务的所有命令
4. 停止服务           ← 批量停止服务的所有命令
5. 重启服务           ← 批量重启服务的所有命令
6. 查看服务状态        ← 详细状态、PID、运行时间
7. 查看服务日志        ← 单命令或全部日志查看
8. 删除服务           ← 安全删除服务和相关文件
9. 启动保活守护进程     ← 启动30秒检查的守护进程
10. 停止保活守护进程    ← 停止守护进程
11. 日志管理设置       ← 配置日志大小、轮转、备份
12. 设置开机自启       ← SystemD服务集成
13. 取消开机自启       ← 移除开机自启
0. 退出
==========================================================
```

### 服务管理界面

当选择"管理现有服务"时，进入服务管理界面：

```
================== 管理服务: web-cluster ==================

服务详情:
  服务名称: web-cluster
  命令总数: 3

命令列表:
  1. [运行中] PID: 12345
     命令: nginx -g "daemon off;"
     日志: 2.5M

  2. [运行中] PID: 12346  
     命令: redis-server
     日志: 1.2M

  3. [已停止] PID: N/A
     命令: node app.js
     日志: 856K

1. 添加新命令到此服务    ← 动态扩展服务
2. 删除命令              ← 移除不需要的命令
3. 修改命令              ← 更新命令内容
4. 启动单个命令          ← 精确控制单个命令
5. 停止单个命令          ← 精确控制单个命令
6. 重启单个命令          ← 精确控制单个命令
7. 启动所有命令          ← 批量启动
8. 停止所有命令          ← 批量停止
9. 重启所有命令          ← 批量重启
10. 查看服务日志         ← 日志查看和管理
11. 删除整个服务         ← 完全删除服务
0. 返回
======================================================
```

---

## 🎯 使用场景

### 🌐 网络代理集群
```bash
服务名: proxy-cluster
├── gost -L relay+phts://:50001      # 主代理服务器
├── gost -L relay+phts://:50002      # 备用代理服务器  
├── gost -L relay+phts://:50003      # 负载均衡代理
└── python monitor.py               # 代理监控脚本
```

### 🖥️ Web应用栈
```bash
服务名: webapp-stack
├── nginx -g "daemon off;"          # Web服务器
├── node backend/server.js          # 后端API服务
├── redis-server                    # 缓存服务
├── python celery_worker.py         # 异步任务处理
└── python log_processor.py         # 日志处理服务
```

### 📊 数据处理管道
```bash
服务名: data-pipeline
├── python data_collector.py        # 数据收集
├── python data_validator.py        # 数据验证
├── python data_transformer.py      # 数据转换
├── python data_loader.py           # 数据加载
└── python monitor_dashboard.py     # 监控面板
```

### 🔍 监控和运维
```bash
服务名: monitoring
├── prometheus --config.file=/etc/prometheus.yml
├── grafana-server --config=/etc/grafana.ini
├── node_exporter --web.listen-address=:9100
└── alertmanager --config.file=/etc/alertmanager.yml
```

---

## 🔧 高级功能

### 📊 日志管理配置

```
====================== 日志管理设置 ======================
当前设置:
  日志大小限制: 1M
  自动清理: true  
  备份数量: 3

日志文件统计:
  gost_1.log                     2.1M
  gost_2.log                     1.8M
  nginx_1.log                    856K
  redis_1.log                    234K

  总计: 4 个文件，5.0M

1. 设置日志大小限制    ← 支持B/K/M/G单位
2. 启用/禁用自动清理   ← 开关自动轮转功能
3. 设置备份数量        ← 0-10个备份文件
4. 手动清理所有日志    ← 一键清理所有日志
0. 返回主菜单
======================================================
```

### 🔄 动态服务管理

#### 添加命令到现有服务
```bash
# 为已存在的代理服务添加新的代理端口
选择: 2 → 选择服务: proxy-cluster
选择: 1 → 输入新命令: gost -L relay+phts://:50004
确认添加 → 立即启动新命令
```

#### 修改现有命令
```bash
# 修改配置参数或端口
选择: 2 → 选择服务: webapp-stack  
选择: 3 → 选择命令序号: 2
输入新命令: node backend/server.js --port=8081
确认修改 → 立即启动新命令
```

#### 精确控制单个命令
```bash
# 只重启服务中的某个特定命令
选择: 2 → 选择服务: webapp-stack
选择: 6 → 选择命令: 1 (nginx)
# 只有nginx会被重启，其他命令继续运行
```

### ⚙️ 命令行工具

Service Keeper也支持命令行操作：

```bash
# 显示帮助信息
./service_keeper.sh --help

# 直接启动守护进程
./service_keeper.sh --start-daemon

# 直接停止守护进程  
./service_keeper.sh --stop-daemon

# 开机自启所有服务（用于SystemD）
./service_keeper.sh --autostart

# 运行守护进程主循环（内部使用）
./service_keeper.sh --daemon
```

---

## 📁 项目结构

```
service_keeper/
├── service_keeper.sh           # 主程序脚本
├── services.conf              # 服务配置文件
├── settings.conf              # 日志管理配置
├── pids/                      # PID文件目录
│   ├── service_1.pid         # 服务命令1的PID
│   ├── service_2.pid         # 服务命令2的PID
│   └── service_keeper_daemon.pid  # 守护进程PID
└── logs/                      # 日志文件目录
    ├── service_1.log         # 服务命令1的当前日志
    ├── service_1.1.log       # 服务命令1的备份日志1
    ├── service_1.2.log       # 服务命令1的备份日志2
    ├── service_2.log         # 服务命令2的当前日志
    ├── daemon.log            # 守护进程日志
    └── autostart.log         # 开机自启日志
```

### 配置文件格式

#### services.conf
```ini
# 服务名=命令1|命令2|命令3
gost-proxy=gost -L relay+phts://:50001|gost -L relay+phts://:50002
webapp=nginx -g "daemon off;"|redis-server|node app.js
monitoring=prometheus|grafana-server
```

#### settings.conf  
```ini
# Service Keeper 设置文件
LOG_MAX_SIZE=1M
LOG_AUTO_CLEAN=true
LOG_BACKUP_COUNT=3
```

---

## ⚡ 性能和监控

### 系统资源占用
- **内存占用**: < 10MB（包括守护进程）
- **CPU占用**: < 1%（守护进程30秒检查一次）
- **磁盘I/O**: 最小化，仅在状态变化时写入

### 监控能力
- **实时状态**: PID、运行时间、内存占用
- **日志监控**: 文件大小、轮转状态、备份数量
- **服务统计**: 总服务数、运行中服务数、命令数统计
- **守护进程**: 自动检查间隔、重启统计

### 故障恢复
- **自动重启**: 异常退出的服务30秒内自动重启
- **日志保护**: 超大日志自动轮转防止磁盘满
- **配置备份**: 配置文件自动备份防止丢失
- **进程隔离**: 单个命令故障不影响其他命令

---

## 🛠️ 系统要求

### 最低要求
- **操作系统**: Linux (内核 2.6+)
- **Shell**: Bash 4.0+
- **权限**: 普通用户权限（部分功能需要sudo）
- **依赖**: 标准Linux工具 (ps, kill, nohup, tail等)

### 推荐环境
- **操作系统**: Ubuntu 18.04+, CentOS 7+, Debian 9+
- **内存**: 512MB+
- **磁盘**: 100MB+ 可用空间（用于日志存储）
- **SystemD**: 支持开机自启功能

### 兼容性测试
- ✅ Ubuntu 20.04/22.04
- ✅ CentOS 7/8
- ✅ Debian 10/11
- ✅ RHEL 7/8
- ✅ Amazon Linux 2
- ✅ Arch Linux

---

## 🔍 常见问题

### Q: 如何确保服务真正独立运行？
**A**: Service Keeper使用`nohup`启动所有服务命令，确保即使管理器退出，服务仍然继续运行。守护进程也是独立运行的。

### Q: 日志文件过大怎么办？
**A**: 启用自动日志轮转功能（默认开启），设置合适的大小限制。系统会自动备份和清理日志文件。

### Q: 如何监控多个相关服务？
**A**: 将相关的服务命令添加到同一个服务中，比如`web-stack`包含nginx、redis、node等。可以批量管理也可以单独控制。

### Q: 守护进程会占用太多资源吗？
**A**: 守护进程非常轻量，每30秒检查一次，CPU和内存占用几乎可以忽略不计。

### Q: 如何备份配置？
**A**: 所有配置保存在`services.conf`和`settings.conf`中，定期备份这两个文件即可。

### Q: 服务启动失败怎么排查？
**A**: 查看对应的日志文件（如`service_1.log`），检查命令是否正确、权限是否足够、端口是否被占用等。

---

## 🤝 贡献指南

我们欢迎各种形式的贡献！

### 如何贡献
1. Fork 本项目
2. 创建特性分支 (`git checkout -b feature/AmazingFeature`)
3. 提交更改 (`git commit -m 'Add some AmazingFeature'`)
4. 推送到分支 (`git push origin feature/AmazingFeature`)
5. 创建 Pull Request


### 报告问题
如果您发现bug或有功能建议：
- 🐛 [提交Issue](https://github.com/DR-lin-eng/service_keeper/issues)
- 💬 [参与讨论](https://github.com/DR-lin-eng/service_keeper/discussions)

---

## 📄 许可证

本项目采用 MIT 许可证。详细信息请参见 [LICENSE](LICENSE) 文件。

---

## 🎉 致谢

感谢所有贡献者和用户的支持！特别感谢：
- 所有提交bug报告和功能建议的用户
- 参与测试和代码review的贡献者
- Linux开源社区提供的优秀工具和库

---

<div align="center">

### 🌟 如果这个项目对您有帮助，请给个Star！

[![GitHub stars](https://img.shields.io/github/stars/DR-lin-eng/service_keeper.svg?style=social&label=Star)](https://github.com/DR-lin-eng/service_keeper)
[![GitHub forks](https://img.shields.io/github/forks/DR-lin-eng/service_keeper.svg?style=social&label=Fork)](https://github.com/DR-lin-eng/service_keeper/fork)

**让Linux服务管理变得简单而强大！**

[回到顶部](#service-keeper)

</div>
