#!/bin/bash

# 服务保活管理脚本 - 重构版
# 支持多命令管理、开机自启、交互式操作、独立运行

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="$SCRIPT_DIR/services.conf"
PID_DIR="$SCRIPT_DIR/pids"
LOG_DIR="$SCRIPT_DIR/logs"
DAEMON_PID_FILE="$SCRIPT_DIR/service_keeper_daemon.pid"

# 创建必要目录
mkdir -p "$PID_DIR" "$LOG_DIR"

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# 打印彩色输出
print_color() {
    local color=$1
    shift
    echo -e "${color}$*${NC}"
}

# 显示主菜单
show_main_menu() {
    clear
    print_color $BLUE "==================== 服务保活管理器 ===================="
    print_color $GREEN "1. 添加新服务"
    print_color $GREEN "2. 启动服务"
    print_color $GREEN "3. 停止服务"
    print_color $GREEN "4. 重启服务"
    print_color $GREEN "5. 查看服务状态"
    print_color $GREEN "6. 查看服务日志"
    print_color $GREEN "7. 删除服务"
    print_color $CYAN "8. 启动保活守护进程"
    print_color $CYAN "9. 停止保活守护进程"
    print_color $YELLOW "10. 设置开机自启"
    print_color $YELLOW "11. 取消开机自启"
    print_color $RED "0. 退出"
    print_color $BLUE "======================================================="
    
    # 显示守护进程状态
    if is_daemon_running; then
        print_color $GREEN "保活守护进程: 运行中"
    else
        print_color $YELLOW "保活守护进程: 未运行"
    fi
    echo
    echo -n "请选择操作 [0-11]: "
}

# 显示服务选择菜单
show_service_menu() {
    local action=$1
    clear
    print_color $BLUE "==================== $action ===================="
    
    if [[ ! -f "$CONFIG_FILE" ]]; then
        print_color $YELLOW "暂无配置的服务"
        echo
        read -p "按回车键返回主菜单..."
        return 1
    fi
    
    print_color $GREEN "已配置的服务:"
    echo
    local index=1
    local services=()
    
    while IFS='=' read -r name command; do
        if [[ -n "$name" ]]; then
            services+=("$name")
            local status="已停止"
            local color=$RED
            local pid="N/A"
            
            if is_service_running "$name"; then
                status="运行中"
                color=$GREEN
                local pid_file="$PID_DIR/${name}.pid"
                if [[ -f "$pid_file" ]]; then
                    pid=$(cat "$pid_file")
                fi
            fi
            
            printf "%2d. %-20s " $index "$name"
            print_color $color "[$status]"
            printf " PID: %-8s\n" "$pid"
            printf "    命令: %s\n" "$command"
            echo
            ((index++))
        fi
    done < "$CONFIG_FILE"
    
    print_color $BLUE "======================================================="
    echo "请选择服务 (输入序号1-$((index-1)), 0返回主菜单):"
    read -p "选择: " choice
    
    if [[ "$choice" == "0" ]]; then
        return 1
    elif [[ "$choice" =~ ^[1-9][0-9]*$ ]] && [[ "$choice" -le "${#services[@]}" ]]; then
        selected_service="${services[$((choice-1))]}"
        echo "$selected_service"
        return 0
    else
        print_color $RED "无效选择"
        sleep 1
        return 1
    fi
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

# 检查守护进程是否运行
is_daemon_running() {
    if [[ -f "$DAEMON_PID_FILE" ]]; then
        local pid=$(cat "$DAEMON_PID_FILE")
        if kill -0 "$pid" 2>/dev/null; then
            return 0
        else
            rm -f "$DAEMON_PID_FILE"
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
    
    print_color $BLUE "正在启动服务: $service_name"
    print_color $CYAN "命令: $command"
    
    # 使用setsid确保进程独立运行
    setsid bash -c "exec $command" > "$log_file" 2>&1 &
    local pid=$!
    echo "$pid" > "$pid_file"
    
    # 等待进程启动
    sleep 3
    if is_service_running "$service_name"; then
        print_color $GREEN "✓ 服务 '$service_name' 启动成功 (PID: $pid)"
        print_color $CYAN "日志文件: $log_file"
    else
        print_color $RED "✗ 服务 '$service_name' 启动失败"
        print_color $YELLOW "请检查日志: $log_file"
        rm -f "$pid_file"
        return 1
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
    print_color $BLUE "正在停止服务: $service_name (PID: $pid)"
    
    # 优雅停止
    kill -TERM "$pid" 2>/dev/null
    sleep 3
    
    # 检查是否还在运行
    if kill -0 "$pid" 2>/dev/null; then
        print_color $YELLOW "强制终止服务..."
        kill -KILL "$pid" 2>/dev/null
        sleep 1
    fi
    
    rm -f "$pid_file"
    print_color $GREEN "✓ 服务 '$service_name' 已停止"
}

# 添加服务
add_service() {
    clear
    print_color $BLUE "==================== 添加新服务 ===================="
    echo
    read -p "请输入服务名称: " service_name
    
    if [[ -z "$service_name" ]]; then
        print_color $RED "服务名称不能为空"
        sleep 2
        return 1
    fi
    
    # 检查服务名称格式
    if [[ ! "$service_name" =~ ^[a-zA-Z0-9_-]+$ ]]; then
        print_color $RED "服务名称只能包含字母、数字、下划线和短横线"
        sleep 2
        return 1
    fi
    
    # 检查服务是否已存在
    if grep -q "^${service_name}=" "$CONFIG_FILE" 2>/dev/null; then
        print_color $RED "服务 '$service_name' 已存在"
        sleep 2
        return 1
    fi
    
    echo
    read -p "请输入要执行的命令: " command
    
    if [[ -z "$command" ]]; then
        print_color $RED "命令不能为空"
        sleep 2
        return 1
    fi
    
    # 确认信息
    echo
    print_color $CYAN "服务信息确认:"
    print_color $GREEN "服务名称: $service_name"
    print_color $GREEN "执行命令: $command"
    echo
    read -p "确认添加此服务? [y/N]: " confirm
    
    if [[ ! "$confirm" =~ ^[Yy] ]]; then
        print_color $YELLOW "已取消添加"
        sleep 1
        return 1
    fi
    
    # 保存到配置文件
    echo "$service_name=$command" >> "$CONFIG_FILE"
    print_color $GREEN "✓ 服务 '$service_name' 添加成功"
    
    echo
    read -p "是否立即启动此服务? [y/N]: " start_now
    if [[ "$start_now" =~ ^[Yy] ]]; then
        echo
        start_service "$service_name" "$command"
    fi
}

# 获取服务命令
get_service_command() {
    local service_name=$1
    grep "^${service_name}=" "$CONFIG_FILE" | cut -d'=' -f2-
}

# 启动服务菜单
start_service_menu() {
    local service_name
    service_name=$(show_service_menu "启动服务")
    
    if [[ $? -eq 0 && -n "$service_name" ]]; then
        local command
        command=$(get_service_command "$service_name")
        echo
        start_service "$service_name" "$command"
        echo
        read -p "按回车键继续..."
    fi
}

# 停止服务菜单
stop_service_menu() {
    local service_name
    service_name=$(show_service_menu "停止服务")
    
    if [[ $? -eq 0 && -n "$service_name" ]]; then
        echo
        stop_service "$service_name"
        echo
        read -p "按回车键继续..."
    fi
}

# 重启服务菜单
restart_service_menu() {
    local service_name
    service_name=$(show_service_menu "重启服务")
    
    if [[ $? -eq 0 && -n "$service_name" ]]; then
        local command
        command=$(get_service_command "$service_name")
        echo
        print_color $BLUE "正在重启服务: $service_name"
        stop_service "$service_name"
        echo
        sleep 2
        start_service "$service_name" "$command"
        echo
        read -p "按回车键继续..."
    fi
}

# 查看服务状态
show_status() {
    clear
    print_color $BLUE "==================== 服务状态总览 ===================="
    echo
    
    if [[ ! -f "$CONFIG_FILE" ]]; then
        print_color $YELLOW "暂无配置的服务"
        echo
        read -p "按回车键返回主菜单..."
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
            local uptime="N/A"
            
            if is_service_running "$name"; then
                status="运行中"
                color=$GREEN
                ((running_services++))
                local pid_file="$PID_DIR/${name}.pid"
                if [[ -f "$pid_file" ]]; then
                    pid=$(cat "$pid_file")
                    # 计算运行时间
                    local start_time=$(stat -c %Y "$pid_file" 2>/dev/null)
                    if [[ -n "$start_time" ]]; then
                        local current_time=$(date +%s)
                        local duration=$((current_time - start_time))
                        uptime=$(date -d@$duration -u +%H:%M:%S)
                    fi
                fi
            fi
            
            printf "%-20s " "$name"
            print_color $color "[$status]"
            printf " PID: %-8s 运行时间: %-10s\n" "$pid" "$uptime"
            printf "    命令: %s\n" "$command"
            echo
        fi
    done < "$CONFIG_FILE"
    
    print_color $BLUE "======================================================="
    print_color $CYAN "统计信息:"
    print_color $GREEN "总服务数: $total_services"
    print_color $GREEN "运行中: $running_services"
    print_color $RED "已停止: $((total_services - running_services))"
    
    # 显示守护进程状态
    echo
    if is_daemon_running; then
        print_color $GREEN "保活守护进程: 运行中"
    else
        print_color $YELLOW "保活守护进程: 未运行 (建议启动以自动重启异常退出的服务)"
    fi
    
    echo
    read -p "按回车键返回主菜单..."
}

# 查看日志菜单
show_logs_menu() {
    local service_name
    service_name=$(show_service_menu "查看服务日志")
    
    if [[ $? -eq 0 && -n "$service_name" ]]; then
        show_service_logs "$service_name"
    fi
}

# 查看服务日志
show_service_logs() {
    local service_name=$1
    local log_file="$LOG_DIR/${service_name}.log"
    
    clear
    print_color $BLUE "==================== $service_name 服务日志 ===================="
    echo "日志文件: $log_file"
    print_color $BLUE "======================================================="
    
    if [[ -f "$log_file" ]]; then
        echo "最近50行日志:"
        echo
        tail -n 50 "$log_file"
        echo
        print_color $BLUE "======================================================="
        echo "1. 查看完整日志  2. 实时监控日志  3. 清空日志  0. 返回"
        read -p "选择操作: " log_choice
        
        case $log_choice in
            1)
                clear
                print_color $BLUE "完整日志内容:"
                echo
                cat "$log_file"
                echo
                read -p "按回车键继续..."
                ;;
            2)
                clear
                print_color $BLUE "实时监控日志 (按Ctrl+C退出):"
                echo
                tail -f "$log_file"
                ;;
            3)
                read -p "确认清空日志文件? [y/N]: " confirm
                if [[ "$confirm" =~ ^[Yy] ]]; then
                    > "$log_file"
                    print_color $GREEN "✓ 日志已清空"
                fi
                sleep 1
                ;;
        esac
    else
        print_color $YELLOW "日志文件不存在"
        echo
        read -p "按回车键继续..."
    fi
}

# 删除服务菜单
delete_service_menu() {
    local service_name
    service_name=$(show_service_menu "删除服务")
    
    if [[ $? -eq 0 && -n "$service_name" ]]; then
        echo
        print_color $RED "警告: 即将删除服务 '$service_name'"
        read -p "确认删除? [y/N]: " confirm
        
        if [[ "$confirm" =~ ^[Yy] ]]; then
            delete_service "$service_name"
            echo
            read -p "按回车键继续..."
        else
            print_color $YELLOW "已取消删除"
            sleep 1
        fi
    fi
}

# 删除服务
delete_service() {
    local service_name=$1
    
    # 先停止服务
    if is_service_running "$service_name"; then
        print_color $BLUE "正在停止服务..."
        stop_service "$service_name"
    fi
    
    # 从配置文件删除
    grep -v "^${service_name}=" "$CONFIG_FILE" > "${CONFIG_FILE}.tmp" 2>/dev/null
    mv "${CONFIG_FILE}.tmp" "$CONFIG_FILE" 2>/dev/null
    
    # 删除相关文件
    rm -f "$PID_DIR/${service_name}.pid"
    
    # 询问是否删除日志
    read -p "是否同时删除日志文件? [y/N]: " delete_log
    if [[ "$delete_log" =~ ^[Yy] ]]; then
        rm -f "$LOG_DIR/${service_name}.log"
        print_color $GREEN "✓ 服务 '$service_name' 及其日志已删除"
    else
        print_color $GREEN "✓ 服务 '$service_name' 已删除 (日志文件保留)"
    fi
}

# 启动保活守护进程
start_daemon() {
    if is_daemon_running; then
        print_color $YELLOW "保活守护进程已经在运行"
        return 1
    fi
    
    print_color $BLUE "正在启动保活守护进程..."
    
    # 启动守护进程
    setsid bash -c "exec $0 --daemon" > /dev/null 2>&1 &
    local daemon_pid=$!
    echo "$daemon_pid" > "$DAEMON_PID_FILE"
    
    sleep 2
    if is_daemon_running; then
        print_color $GREEN "✓ 保活守护进程启动成功 (PID: $daemon_pid)"
        print_color $CYAN "守护进程将每30秒检查一次服务状态"
    else
        print_color $RED "✗ 保活守护进程启动失败"
        rm -f "$DAEMON_PID_FILE"
    fi
}

# 停止保活守护进程
stop_daemon() {
    if ! is_daemon_running; then
        print_color $YELLOW "保活守护进程未运行"
        return 1
    fi
    
    local daemon_pid=$(cat "$DAEMON_PID_FILE")
    print_color $BLUE "正在停止保活守护进程 (PID: $daemon_pid)..."
    
    kill -TERM "$daemon_pid" 2>/dev/null
    sleep 2
    
    if kill -0 "$daemon_pid" 2>/dev/null; then
        kill -KILL "$daemon_pid" 2>/dev/null
    fi
    
    rm -f "$DAEMON_PID_FILE"
    print_color $GREEN "✓ 保活守护进程已停止"
}

# 守护进程主循环
daemon_loop() {
    echo "$(date): 保活守护进程启动" >> "$LOG_DIR/daemon.log"
    
    while true; do
        if [[ -f "$CONFIG_FILE" ]]; then
            while IFS='=' read -r name command; do
                if [[ -n "$name" ]] && ! is_service_running "$name"; then
                    echo "$(date): 检测到服务 '$name' 已停止，正在重启..." >> "$LOG_DIR/daemon.log"
                    start_service "$name" "$command" >> "$LOG_DIR/daemon.log" 2>&1
                fi
            done < "$CONFIG_FILE"
        fi
        sleep 30
    done
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
WorkingDirectory=$SCRIPT_DIR

[Install]
WantedBy=multi-user.target
EOF

    # 启用服务
    sudo systemctl daemon-reload
    sudo systemctl enable service-keeper.service
    
    print_color $GREEN "✓ 开机自启动设置成功"
    print_color $CYAN "重启后将自动启动所有配置的服务和守护进程"
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
    echo "$(date): 开机自动启动服务..." >> "$LOG_DIR/autostart.log"
    
    if [[ ! -f "$CONFIG_FILE" ]]; then
        exit 0
    fi
    
    # 启动所有服务
    while IFS='=' read -r name command; do
        if [[ -n "$name" ]]; then
            start_service "$name" "$command" >> "$LOG_DIR/autostart.log" 2>&1
            sleep 2
        fi
    done < "$CONFIG_FILE"
    
    # 启动守护进程
    sleep 5
    start_daemon >> "$LOG_DIR/autostart.log" 2>&1
}

# 处理命令行参数
case "$1" in
    --autostart)
        autostart_all
        exit 0
        ;;
    --daemon)
        daemon_loop
        exit 0
        ;;
    --start-daemon)
        start_daemon
        exit 0
        ;;
    --stop-daemon)
        stop_daemon
        exit 0
        ;;
    --help|-h)
        echo "Service Keeper - 服务保活管理器"
        echo "用法: $0 [选项]"
        echo "选项:"
        echo "  --autostart      开机自动启动所有服务"
        echo "  --daemon         运行守护进程"
        echo "  --start-daemon   启动守护进程"
        echo "  --stop-daemon    停止守护进程"
        echo "  --help, -h       显示此帮助信息"
        exit 0
        ;;
esac

# 主循环
while true; do
    show_main_menu
    read choice
    
    case $choice in
        1) 
            add_service
            ;;
        2) 
            start_service_menu
            ;;
        3)
            stop_service_menu
            ;;
        4)
            restart_service_menu
            ;;
        5) 
            show_status
            ;;
        6) 
            show_logs_menu
            ;;
        7) 
            delete_service_menu
            ;;
        8)
            echo
            start_daemon
            echo
            read -p "按回车键继续..."
            ;;
        9)
            echo
            stop_daemon
            echo
            read -p "按回车键继续..."
            ;;
        10) 
            echo
            setup_autostart
            echo
            read -p "按回车键继续..."
            ;;
        11) 
            echo
            remove_autostart
            echo
            read -p "按回车键继续..."
            ;;
        0) 
            print_color $GREEN "感谢使用 Service Keeper!"
            exit 0
            ;;
        *)
            print_color $RED "无效选择，请重试"
            sleep 1
            ;;
    esac
done
