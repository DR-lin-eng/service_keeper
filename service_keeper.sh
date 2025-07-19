#!/bin/bash

# 服务保活管理脚本
# 支持多命令管理、开机自启、交互式操作

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="$SCRIPT_DIR/services.conf"
PID_DIR="$SCRIPT_DIR/pids"
LOG_DIR="$SCRIPT_DIR/logs"

# 创建必要目录
mkdir -p "$PID_DIR" "$LOG_DIR"

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 打印彩色输出
print_color() {
    local color=$1
    shift
    echo -e "${color}$*${NC}"
}

# 显示菜单
show_menu() {
    clear
    print_color $BLUE "==================== 服务保活管理器 ===================="
    print_color $GREEN "1. 添加新服务"
    print_color $GREEN "2. 启动服务"
    print_color $GREEN "3. 停止服务"
    print_color $GREEN "4. 重启服务"
    print_color $GREEN "5. 查看服务状态"
    print_color $GREEN "6. 查看服务日志"
    print_color $GREEN "7. 删除服务"
    print_color $GREEN "8. 设置开机自启"
    print_color $GREEN "9. 取消开机自启"
    print_color $YELLOW "0. 退出"
    print_color $BLUE "======================================================="
    echo -n "请选择操作 [0-9]: "
}

# 检查服务是否运行
is_service_running() {
    local service_name=$1
    local pid_file="$PID_DIR/${service_name}.pid"
    
    if [[ -f "$pid_file" ]]; then
        local pid=$(cat "$pid_file")
        if kill -0 "$pid" 2>/dev/null; then
            return 0
        else
            rm -f "$pid_file"
            return 1
        fi
    fi
    return 1
}

# 启动服务
start_service() {
    local service_name=$1
    local command=$2
    local log_file="$LOG_DIR/${service_name}.log"
    local pid_file="$PID_DIR/${service_name}.pid"
    
    if is_service_running "$service_name"; then
        print_color $YELLOW "服务 '$service_name' 已经在运行"
        return 1
    fi
    
    print_color $BLUE "启动服务: $service_name"
    nohup bash -c "$command" > "$log_file" 2>&1 &
    local pid=$!
    echo "$pid" > "$pid_file"
    
    sleep 2
    if is_service_running "$service_name"; then
        print_color $GREEN "✓ 服务 '$service_name' 启动成功 (PID: $pid)"
    else
        print_color $RED "✗ 服务 '$service_name' 启动失败"
        rm -f "$pid_file"
    fi
}

# 停止服务
stop_service() {
    local service_name=$1
    local pid_file="$PID_DIR/${service_name}.pid"
    
    if ! is_service_running "$service_name"; then
        print_color $YELLOW "服务 '$service_name' 未运行"
        return 1
    fi
    
    local pid=$(cat "$pid_file")
    print_color $BLUE "停止服务: $service_name (PID: $pid)"
    
    kill "$pid" 2>/dev/null
    sleep 2
    
    if kill -0 "$pid" 2>/dev/null; then
        print_color $YELLOW "强制终止服务..."
        kill -9 "$pid" 2>/dev/null
    fi
    
    rm -f "$pid_file"
    print_color $GREEN "✓ 服务 '$service_name' 已停止"
}

# 添加服务
add_service() {
    echo
    print_color $BLUE "=== 添加新服务 ==="
    read -p "请输入服务名称: " service_name
    
    if [[ -z "$service_name" ]]; then
        print_color $RED "服务名称不能为空"
        return 1
    fi
    
    # 检查服务是否已存在
    if grep -q "^${service_name}=" "$CONFIG_FILE" 2>/dev/null; then
        print_color $RED "服务 '$service_name' 已存在"
        return 1
    fi
    
    read -p "请输入要执行的命令: " command
    
    if [[ -z "$command" ]]; then
        print_color $RED "命令不能为空"
        return 1
    fi
    
    # 保存到配置文件
    echo "$service_name=$command" >> "$CONFIG_FILE"
    print_color $GREEN "✓ 服务 '$service_name' 添加成功"
    
    read -p "是否立即启动此服务? [y/N]: " start_now
    if [[ "$start_now" =~ ^[Yy] ]]; then
        start_service "$service_name" "$command"
    fi
}

# 列出所有服务
list_services() {
    if [[ ! -f "$CONFIG_FILE" ]]; then
        print_color $YELLOW "暂无配置的服务"
        return 1
    fi
    
    print_color $BLUE "=== 已配置的服务 ==="
    local index=1
    while IFS='=' read -r name command; do
        if [[ -n "$name" ]]; then
            local status="已停止"
            local color=$RED
            if is_service_running "$name"; then
                status="运行中"
                color=$GREEN
            fi
            
            printf "%2d. %-20s " $index "$name"
            print_color $color "[$status]"
            printf " %s\n" "$command"
            ((index++))
        fi
    done < "$CONFIG_FILE"
    return 0
}

# 选择服务
select_service() {
    if [[ ! -f "$CONFIG_FILE" ]]; then
        print_color $YELLOW "暂无配置的服务"
        return 1
    fi
    
    print_color $BLUE "=== 已配置的服务 ==="
    local index=1
    while IFS='=' read -r name command; do
        if [[ -n "$name" ]]; then
            local status="已停止"
            local color=$RED
            if is_service_running "$name"; then
                status="运行中"
                color=$GREEN
            fi
            
            printf "%2d. %-20s " $index "$name"
            print_color $color "[$status]"
            printf " %s\n" "$command"
            ((index++))
        fi
    done < "$CONFIG_FILE"
    
    echo
    read -p "请输入服务名称: " service_name
    
    if [[ -z "$service_name" ]]; then
        print_color $RED "服务名称不能为空"
        return 1
    fi
    
    # 验证服务是否存在
    if ! grep -q "^${service_name}=" "$CONFIG_FILE" 2>/dev/null; then
        print_color $RED "服务 '$service_name' 不存在"
        return 1
    fi
    
    # 直接输出服务名称到标准输出
    printf "%s" "$service_name"
}

# 获取服务命令
get_service_command() {
    local service_name=$1
    grep "^${service_name}=" "$CONFIG_FILE" | cut -d'=' -f2-
}

# 查看服务状态
show_status() {
    echo
    print_color $BLUE "=== 服务状态总览 ==="
    
    if [[ ! -f "$CONFIG_FILE" ]]; then
        print_color $YELLOW "暂无配置的服务"
        return 1
    fi
    
    local total_services=0
    local running_services=0
    
    while IFS='=' read -r name command; do
        if [[ -n "$name" ]]; then
            ((total_services++))
            local status="已停止"
            local color=$RED
            local pid="N/A"
            
            if is_service_running "$name"; then
                status="运行中"
                color=$GREEN
                ((running_services++))
                local pid_file="$PID_DIR/${name}.pid"
                if [[ -f "$pid_file" ]]; then
                    pid=$(cat "$pid_file")
                fi
            fi
            
            printf "%-20s " "$name"
            print_color $color "[$status]"
            printf " PID: %-8s %s\n" "$pid" "$command"
        fi
    done < "$CONFIG_FILE"
    
    echo
    print_color $BLUE "统计信息:"
    print_color $GREEN "总服务数: $total_services"
    print_color $GREEN "运行中: $running_services"
    print_color $RED "已停止: $((total_services - running_services))"
}

# 查看日志
show_logs() {
    echo
    service_name=$(select_service)
    if [[ $? -eq 0 && -n "$service_name" ]]; then
        local log_file="$LOG_DIR/${service_name}.log"
        if [[ -f "$log_file" ]]; then
            print_color $BLUE "=== $service_name 服务日志 ==="
            echo "日志文件: $log_file"
            echo "----------------------------------------"
            tail -n 50 "$log_file"
            echo
            read -p "按回车键继续..."
        else
            print_color $YELLOW "日志文件不存在: $log_file"
            read -p "按回车键继续..."
        fi
    fi
}

# 删除服务
delete_service() {
    local service_name=$1
    
    # 先停止服务
    if is_service_running "$service_name"; then
        stop_service "$service_name"
    fi
    
    # 从配置文件删除
    grep -v "^${service_name}=" "$CONFIG_FILE" > "${CONFIG_FILE}.tmp" 2>/dev/null
    mv "${CONFIG_FILE}.tmp" "$CONFIG_FILE" 2>/dev/null
    
    # 删除相关文件
    rm -f "$PID_DIR/${service_name}.pid"
    rm -f "$LOG_DIR/${service_name}.log"
    
    print_color $GREEN "✓ 服务 '$service_name' 已删除"
}

# 设置开机自启
setup_autostart() {
    local script_path="$SCRIPT_DIR/$(basename "$0")"
    local service_file="/etc/systemd/system/service-keeper.service"
    
    print_color $BLUE "设置开机自启动..."
    
    # 创建systemd服务文件
    sudo tee "$service_file" > /dev/null << EOF
[Unit]
Description=Service Keeper - Auto start managed services
After=network.target

[Service]
Type=oneshot
ExecStart=$script_path --autostart
RemainAfterExit=true
User=$(whoami)

[Install]
WantedBy=multi-user.target
EOF

    # 启用服务
    sudo systemctl daemon-reload
    sudo systemctl enable service-keeper.service
    
    print_color $GREEN "✓ 开机自启动设置成功"
    print_color $YELLOW "重启后将自动启动所有配置的服务"
}

# 取消开机自启
remove_autostart() {
    print_color $BLUE "取消开机自启动..."
    
    sudo systemctl disable service-keeper.service 2>/dev/null
    sudo rm -f /etc/systemd/system/service-keeper.service
    sudo systemctl daemon-reload
    
    print_color $GREEN "✓ 开机自启动已取消"
}

# 自动启动所有服务
autostart_all() {
    if [[ ! -f "$CONFIG_FILE" ]]; then
        exit 0
    fi
    
    echo "自动启动所有服务..."
    while IFS='=' read -r name command; do
        if [[ -n "$name" ]]; then
            start_service "$name" "$command"
        fi
    done < "$CONFIG_FILE"
}

# 服务保活循环
keep_alive() {
    while true; do
        if [[ -f "$CONFIG_FILE" ]]; then
            while IFS='=' read -r name command; do
                if [[ -n "$name" ]] && ! is_service_running "$name"; then
                    print_color $YELLOW "检测到服务 '$name' 已停止，正在重启..."
                    start_service "$name" "$command"
                fi
            done < "$CONFIG_FILE"
        fi
        sleep 30
    done
}

# 处理命令行参数
if [[ "$1" == "--autostart" ]]; then
    autostart_all
    exit 0
elif [[ "$1" == "--keep-alive" ]]; then
    keep_alive
    exit 0
fi

# 主循环
while true; do
    show_menu
    read choice
    
    case $choice in
        1) add_service ;;
        2) 
            echo
            service_name=$(select_service)
            if [[ $? -eq 0 && -n "$service_name" ]]; then
                command=$(get_service_command "$service_name")
                start_service "$service_name" "$command"
            fi
            ;;
        3)
            echo
            service_name=$(select_service)
            if [[ $? -eq 0 && -n "$service_name" ]]; then
                stop_service "$service_name"
            fi
            ;;
        4)
            echo
            service_name=$(select_service)
            if [[ $? -eq 0 && -n "$service_name" ]]; then
                command=$(get_service_command "$service_name")
                stop_service "$service_name"
                sleep 1
                start_service "$service_name" "$command"
            fi
            ;;
        5) 
            show_status
            echo
            read -p "按回车键继续..."
            ;;
        6) show_logs ;;
        7) 
            echo
            service_name=$(select_service)
            if [[ $? -eq 0 && -n "$service_name" ]]; then
                delete_service "$service_name"
            fi
            ;;
        8) setup_autostart ;;
        9) remove_autostart ;;
        0) 
            print_color $GREEN "再见!"
            exit 0
            ;;
        *)
            print_color $RED "无效选择，请重试"
            ;;
    esac
    
    if [[ "$choice" != "5" && "$choice" != "6" && "$choice" != "0" ]]; then
        echo
        read -p "按回车键继续..."
    fi
done
