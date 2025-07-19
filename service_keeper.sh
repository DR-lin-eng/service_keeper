# 守护进程主循环
daemon_loop() {
    echo "$(date): 保活守护进程启动" >> "$LOG_DIR/daemon.log"
    
    while true; do
        # 重新加载设置
        load_settings
        
        # 检查服务状态
        if [[ -f "$CONFIG_FILE" ]]; then
            while IFS='=' read -r name commands; do
                if [[ -n "$name" ]]; then
                    local cmd_count=$(echo "$commands" | tr '|' '\n' | wc -l)
                    local cmd_index=1
                    
                    while IFS='|' read -ra CMDS; do
                        for cmd in "${CMDS[@]}"; do
                            if ! is_command_running "$name" "$cmd_index"; then
                                echo "$(date): 检测到服务 '$name' 命令 $cmd_index 已停止，正在重启..." >> "$LOG_DIR/daemon.log"
                                start_command "$name" "$cmd_index" "$cmd" >> "$LOG_DIR/daemon.log" 2>&1
                            else
                                # 检查并清理日志文件
                                local log_file="$LOG_DIR/${name}_${cmd_index}.log"
                                check_and_clean_log "$log_file"
                            fi
                            ((cmd_index++))
                        done
                    done <<< "$commands"
                fi
            done < "$CONFIG_FILE"
        fi
        
        # 清理守护进程自己的日志
        check_and_clean_log "$LOG_DIR/daemon.log"
        
        sleep 30
    done
}#!/bin/bash

# 服务保活管理脚本 - 增强版
# 支持一个服务多命令、二级菜单优化、独立运行

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="$SCRIPT_DIR/services.conf"
PID_DIR="$SCRIPT_DIR/pids"
LOG_DIR="$SCRIPT_DIR/logs"
DAEMON_PID_FILE="$SCRIPT_DIR/service_keeper_daemon.pid"
SETTINGS_FILE="$SCRIPT_DIR/settings.conf"

# 创建必要目录
mkdir -p "$PID_DIR" "$LOG_DIR"

# 默认设置
DEFAULT_LOG_MAX_SIZE="1M"

# 初始化设置文件
init_settings() {
    if [[ ! -f "$SETTINGS_FILE" ]]; then
        cat > "$SETTINGS_FILE" << EOF
# Service Keeper 设置文件
LOG_MAX_SIZE=${DEFAULT_LOG_MAX_SIZE}
LOG_AUTO_CLEAN=true
LOG_BACKUP_COUNT=3
EOF
    fi
}

# 读取设置
load_settings() {
    init_settings
    source "$SETTINGS_FILE"
    
    # 设置默认值（如果配置文件中没有）
    LOG_MAX_SIZE=${LOG_MAX_SIZE:-$DEFAULT_LOG_MAX_SIZE}
    LOG_AUTO_CLEAN=${LOG_AUTO_CLEAN:-true}
    LOG_BACKUP_COUNT=${LOG_BACKUP_COUNT:-3}
}

# 保存设置
save_settings() {
    cat > "$SETTINGS_FILE" << EOF
# Service Keeper 设置文件
LOG_MAX_SIZE=${LOG_MAX_SIZE}
LOG_AUTO_CLEAN=${LOG_AUTO_CLEAN}
LOG_BACKUP_COUNT=${LOG_BACKUP_COUNT}
EOF
}

# 初始化
load_settings

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
PURPLE='\033[0;35m'
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
    print_color $BLUE "====================== 服务保活管理器 ======================"
    print_color $GREEN "1. 服务管理"
    print_color $GREEN "2. 启动服务"
    print_color $GREEN "3. 停止服务"
    print_color $GREEN "4. 重启服务"
    print_color $GREEN "5. 查看服务状态"
    print_color $GREEN "6. 查看服务日志"
    print_color $GREEN "7. 删除服务"
    print_color $CYAN "8. 启动保活守护进程"
    print_color $CYAN "9. 停止保活守护进程"
    print_color $PURPLE "10. 日志管理设置"
    print_color $YELLOW "11. 设置开机自启"
    print_color $YELLOW "12. 取消开机自启"
    print_color $RED "0. 退出"
    print_color $BLUE "=========================================================="
    
    # 显示守护进程状态
    if is_daemon_running; then
        print_color $GREEN "保活守护进程: 运行中"
    else
        print_color $YELLOW "保活守护进程: 未运行"
    fi
    
    # 显示服务统计
    show_service_summary
    echo
    echo -n "请选择操作 [0-12]: "
}

# 显示服务概要
show_service_summary() {
    if [[ ! -f "$CONFIG_FILE" ]]; then
        print_color $YELLOW "当前无配置服务"
        return
    fi
    
    local total_services=0
    local running_services=0
    local total_commands=0
    local running_commands=0
    
    while IFS='=' read -r name commands; do
        if [[ -n "$name" ]]; then
            ((total_services++))
            local service_running=false
            
            # 统计命令数
            local cmd_count=$(echo "$commands" | tr '|' '\n' | wc -l)
            ((total_commands += cmd_count))
            
            # 检查服务是否有运行的命令
            for ((i=1; i<=cmd_count; i++)); do
                if is_command_running "$name" "$i"; then
                    ((running_commands++))
                    service_running=true
                fi
            done
            
            if [[ "$service_running" == "true" ]]; then
                ((running_services++))
            fi
        fi
    done < "$CONFIG_FILE"
    
    printf "服务: %d/%d运行中 | 命令: %d/%d运行中\n" "$running_services" "$total_services" "$running_commands" "$total_commands"
}

# 服务管理菜单
service_management_menu() {
    while true; do
        clear
        print_color $BLUE "====================== 服务管理 ======================"
        print_color $GREEN "1. 添加新服务"
        print_color $GREEN "2. 管理现有服务"
        print_color $YELLOW "0. 返回主菜单"
        print_color $BLUE "======================================================"
        echo
        echo -n "请选择操作 [0-2]: "
        read choice
        
        case $choice in
            1) add_new_service ;;
            2) manage_existing_service ;;
            0) return ;;
            *) 
                print_color $RED "无效选择"
                sleep 1
                ;;
        esac
    done
}

# 添加新服务
add_new_service() {
    clear
    print_color $BLUE "====================== 添加新服务 ======================"
    echo
    read -p "请输入服务名称: " service_name
    
    if [[ -z "$service_name" ]]; then
        print_color $RED "服务名称不能为空"
        sleep 2
        return
    fi
    
    # 检查服务名称格式
    if [[ ! "$service_name" =~ ^[a-zA-Z0-9_-]+$ ]]; then
        print_color $RED "服务名称只能包含字母、数字、下划线和短横线"
        sleep 2
        return
    fi
    
    # 检查服务是否已存在
    if grep -q "^${service_name}=" "$CONFIG_FILE" 2>/dev/null; then
        print_color $RED "服务 '$service_name' 已存在"
        sleep 2
        return
    fi
    
    echo
    print_color $CYAN "为服务 '$service_name' 添加命令:"
    local commands=""
    local cmd_num=1
    
    while true; do
        echo
        read -p "请输入第${cmd_num}个命令 (直接回车完成添加): " command
        
        if [[ -z "$command" ]]; then
            if [[ $cmd_num -eq 1 ]]; then
                print_color $RED "至少需要添加一个命令"
                continue
            else
                break
            fi
        fi
        
        if [[ -n "$commands" ]]; then
            commands="${commands}|${command}"
        else
            commands="$command"
        fi
        
        print_color $GREEN "✓ 已添加命令 $cmd_num: $command"
        ((cmd_num++))
    done
    
    # 确认信息
    echo
    print_color $CYAN "服务信息确认:"
    print_color $GREEN "服务名称: $service_name"
    print_color $GREEN "命令列表:"
    echo "$commands" | tr '|' '\n' | nl -w2 -s'. '
    echo
    read -p "确认添加此服务? [y/N]: " confirm
    
    if [[ ! "$confirm" =~ ^[Yy] ]]; then
        print_color $YELLOW "已取消添加"
        sleep 1
        return
    fi
    
    # 保存到配置文件
    echo "$service_name=$commands" >> "$CONFIG_FILE"
    print_color $GREEN "✓ 服务 '$service_name' 添加成功"
    
    echo
    read -p "是否立即启动此服务的所有命令? [y/N]: " start_now
    if [[ "$start_now" =~ ^[Yy] ]]; then
        echo
        start_all_service_commands "$service_name"
    fi
    
    echo
    read -p "按回车键继续..."
}

# 管理现有服务
manage_existing_service() {
    local service_name
    service_name=$(select_service_for_management)
    
    if [[ $? -ne 0 || -z "$service_name" ]]; then
        return
    fi
    
    while true; do
        clear
        print_color $BLUE "================= 管理服务: $service_name ================="
        
        # 显示当前服务的命令
        show_service_commands "$service_name"
        
        echo
        print_color $GREEN "1. 添加新命令"
        print_color $GREEN "2. 删除命令"
        print_color $GREEN "3. 修改命令"
        print_color $YELLOW "4. 启动所有命令"
        print_color $YELLOW "5. 停止所有命令"
        print_color $RED "6. 删除整个服务"
        print_color $BLUE "0. 返回"
        print_color $BLUE "======================================================"
        echo -n "请选择操作 [0-6]: "
        read choice
        
        case $choice in
            1) add_command_to_service "$service_name" ;;
            2) remove_command_from_service "$service_name" ;;
            3) modify_service_command "$service_name" ;;
            4) 
                echo
                start_all_service_commands "$service_name"
                read -p "按回车键继续..."
                ;;
            5) 
                echo
                stop_all_service_commands "$service_name"
                read -p "按回车键继续..."
                ;;
            6) 
                echo
                if confirm_delete_service "$service_name"; then
                    return
                fi
                ;;
            0) return ;;
            *) 
                print_color $RED "无效选择"
                sleep 1
                ;;
        esac
    done
}

# 显示服务的命令列表
show_service_commands() {
    local service_name=$1
    local commands
    commands=$(get_service_commands "$service_name")
    
    print_color $CYAN "当前命令列表:"
    local cmd_num=1
    while IFS='|' read -ra CMDS; do
        for cmd in "${CMDS[@]}"; do
            local status="停止"
            local color=$RED
            local pid="N/A"
            
            if is_command_running "$service_name" "$cmd_num"; then
                status="运行中"
                color=$GREEN
                pid=$(get_command_pid "$service_name" "$cmd_num")
            fi
            
            printf "%2d. " $cmd_num
            print_color $color "[$status]"
            printf " PID: %-8s %s\n" "$pid" "$cmd"
            ((cmd_num++))
        done
    done <<< "$commands"
}

# 选择服务进行管理
select_service_for_management() {
    clear
    print_color $BLUE "====================== 选择服务 ======================"
    
    if ! show_services_list; then
        echo
        read -p "按回车键返回..."
        return 1
    fi
    
    echo
    read -p "请输入服务序号 (0返回): " choice
    
    if [[ "$choice" == "0" ]]; then
        return 1
    fi
    
    local service_name
    service_name=$(get_service_by_index "$choice")
    
    if [[ -z "$service_name" ]]; then
        print_color $RED "无效的服务序号"
        sleep 1
        return 1
    fi
    
    echo "$service_name"
}

# 显示服务二级菜单
show_service_menu() {
    local action=$1
    clear
    print_color $BLUE "================= $action ================="
    
    if ! show_services_list; then
        echo
        read -p "按回车键返回主菜单..."
        return 1
    fi
    
    echo
    read -p "请输入服务序号 (0返回主菜单): " choice
    
    if [[ "$choice" == "0" ]]; then
        return 1
    fi
    
    local service_name
    service_name=$(get_service_by_index "$choice")
    
    if [[ -z "$service_name" ]]; then
        print_color $RED "无效的服务序号"
        sleep 1
        return 1
    fi
    
    echo "$service_name"
}

# 显示服务列表
show_services_list() {
    if [[ ! -f "$CONFIG_FILE" ]]; then
        print_color $YELLOW "暂无配置的服务"
        return 1
    fi
    
    local index=1
    while IFS='=' read -r name commands; do
        if [[ -n "$name" ]]; then
            local cmd_count=$(echo "$commands" | tr '|' '\n' | wc -l)
            local running_count=0
            
            # 统计运行中的命令数
            for ((i=1; i<=cmd_count; i++)); do
                if is_command_running "$name" "$i"; then
                    ((running_count++))
                fi
            done
            
            local status_color=$RED
            local status="已停止"
            if [[ $running_count -gt 0 ]]; then
                if [[ $running_count -eq $cmd_count ]]; then
                    status_color=$GREEN
                    status="运行中"
                else
                    status_color=$YELLOW
                    status="部分运行"
                fi
            fi
            
            printf "%2d. %-20s " $index "$name"
            print_color $status_color "[$status]"
            printf " 命令数: %d (运行: %d)\n" "$cmd_count" "$running_count"
            
            ((index++))
        fi
    done < "$CONFIG_FILE"
    
    return 0
}

# 根据索引获取服务名
get_service_by_index() {
    local target_index=$1
    local current_index=1
    
    while IFS='=' read -r name commands; do
        if [[ -n "$name" ]]; then
            if [[ $current_index -eq $target_index ]]; then
                echo "$name"
                return 0
            fi
            ((current_index++))
        fi
    done < "$CONFIG_FILE"
    
    return 1
}

# 检查命令是否运行
is_command_running() {
    local service_name=$1
    local cmd_index=$2
    local pid_file="$PID_DIR/${service_name}_${cmd_index}.pid"
    
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

# 检查并清理日志文件
check_and_clean_log() {
    local log_file=$1
    
    if [[ ! -f "$log_file" ]]; then
        return 0
    fi
    
    # 如果关闭了自动清理，直接返回
    if [[ "$LOG_AUTO_CLEAN" != "true" ]]; then
        return 0
    fi
    
    # 获取文件大小（字节）
    local file_size=$(stat -f%z "$log_file" 2>/dev/null || stat -c%s "$log_file" 2>/dev/null || echo 0)
    local max_bytes
    
    # 转换大小限制为字节
    case "${LOG_MAX_SIZE}" in
        *K|*k) max_bytes=$((${LOG_MAX_SIZE%[Kk]} * 1024)) ;;
        *M|*m) max_bytes=$((${LOG_MAX_SIZE%[Mm]} * 1024 * 1024)) ;;
        *G|*g) max_bytes=$((${LOG_MAX_SIZE%[Gg]} * 1024 * 1024 * 1024)) ;;
        *) max_bytes=${LOG_MAX_SIZE} ;;
    esac
    
    if [[ $file_size -gt $max_bytes ]]; then
        rotate_log_file "$log_file"
    fi
}

# 轮转日志文件
rotate_log_file() {
    local log_file=$1
    local dir_name=$(dirname "$log_file")
    local base_name=$(basename "$log_file" .log)
    
    print_color $YELLOW "日志文件 $(basename "$log_file") 超过大小限制，正在轮转..."
    
    # 轮转备份文件
    for ((i=LOG_BACKUP_COUNT; i>=1; i--)); do
        local old_backup="${dir_name}/${base_name}.${i}.log"
        local new_backup="${dir_name}/${base_name}.$((i+1)).log"
        
        if [[ -f "$old_backup" ]]; then
            if [[ $i -eq $LOG_BACKUP_COUNT ]]; then
                rm -f "$old_backup"  # 删除最老的备份
            else
                mv "$old_backup" "$new_backup"
            fi
        fi
    done
    
    # 移动当前日志文件为第一个备份
    if [[ -f "$log_file" ]]; then
        mv "$log_file" "${dir_name}/${base_name}.1.log"
        touch "$log_file"  # 创建新的空日志文件
        print_color $GREEN "✓ 日志轮转完成"
    fi
}

# 获取日志文件大小（人类可读格式）
get_human_readable_size() {
    local file=$1
    if [[ ! -f "$file" ]]; then
        echo "0B"
        return
    fi
    
    local size=$(stat -f%z "$file" 2>/dev/null || stat -c%s "$file" 2>/dev/null || echo 0)
    
    if [[ $size -lt 1024 ]]; then
        echo "${size}B"
    elif [[ $size -lt $((1024*1024)) ]]; then
        echo "$((size/1024))K"
    elif [[ $size -lt $((1024*1024*1024)) ]]; then
        echo "$((size/(1024*1024)))M"
    else
        echo "$((size/(1024*1024*1024)))G"
    fi
}

# 日志管理设置菜单
log_management_menu() {
    while true; do
        clear
        print_color $BLUE "====================== 日志管理设置 ======================"
        
        # 显示当前设置
        print_color $CYAN "当前设置:"
        printf "  日志大小限制: %s\n" "$LOG_MAX_SIZE"
        printf "  自动清理: %s\n" "$LOG_AUTO_CLEAN"
        printf "  备份数量: %s\n" "$LOG_BACKUP_COUNT"
        
        # 显示日志统计
        echo
        print_color $CYAN "日志文件统计:"
        local total_size=0
        local file_count=0
        
        for log_file in "$LOG_DIR"/*.log; do
            if [[ -f "$log_file" ]]; then
                local size=$(stat -f%z "$log_file" 2>/dev/null || stat -c%s "$log_file" 2>/dev/null || echo 0)
                total_size=$((total_size + size))
                ((file_count++))
                
                printf "  %-30s %s\n" "$(basename "$log_file")" "$(get_human_readable_size "$log_file")"
            fi
        done
        
        if [[ $file_count -eq 0 ]]; then
            print_color $YELLOW "  暂无日志文件"
        else
            echo
            if [[ $total_size -lt 1024 ]]; then
                print_color $GREEN "  总计: $file_count 个文件，${total_size}B"
            elif [[ $total_size -lt $((1024*1024)) ]]; then
                print_color $GREEN "  总计: $file_count 个文件，$((total_size/1024))K"
            elif [[ $total_size -lt $((1024*1024*1024)) ]]; then
                print_color $GREEN "  总计: $file_count 个文件，$((total_size/(1024*1024)))M"
            else
                print_color $GREEN "  总计: $file_count 个文件，$((total_size/(1024*1024*1024)))G"
            fi
        fi
        
        echo
        print_color $GREEN "1. 设置日志大小限制"
        print_color $GREEN "2. 启用/禁用自动清理"
        print_color $GREEN "3. 设置备份数量"
        print_color $GREEN "4. 手动清理所有日志"
        print_color $GREEN "5. 立即检查并轮转大日志"
        print_color $YELLOW "0. 返回主菜单"
        print_color $BLUE "======================================================"
        echo -n "请选择操作 [0-5]: "
        read choice
        
        case $choice in
            1) set_log_size_limit ;;
            2) toggle_auto_clean ;;
            3) set_backup_count ;;
            4) manual_clean_logs ;;
            5) check_all_logs ;;
            0) return ;;
            *) 
                print_color $RED "无效选择"
                sleep 1
                ;;
        esac
    done
}

# 设置日志大小限制
set_log_size_limit() {
    echo
    print_color $CYAN "当前日志大小限制: $LOG_MAX_SIZE"
    print_color $YELLOW "支持的格式: 数字+单位 (B, K, M, G)"
    print_color $YELLOW "例如: 1M, 500K, 2G, 1048576"
    echo
    read -p "请输入新的大小限制: " new_size
    
    if [[ -z "$new_size" ]]; then
        print_color $YELLOW "已取消设置"
        sleep 1
        return
    fi
    
    # 验证格式
    if [[ ! "$new_size" =~ ^[0-9]+[BbKkMmGg]?$ ]]; then
        print_color $RED "格式错误，请使用数字+单位格式"
        sleep 2
        return
    fi
    
    LOG_MAX_SIZE="$new_size"
    save_settings
    print_color $GREEN "✓ 日志大小限制已设置为: $LOG_MAX_SIZE"
    sleep 2
}

# 切换自动清理
toggle_auto_clean() {
    echo
    if [[ "$LOG_AUTO_CLEAN" == "true" ]]; then
        LOG_AUTO_CLEAN="false"
        print_color $YELLOW "✓ 自动清理已禁用"
    else
        LOG_AUTO_CLEAN="true"
        print_color $GREEN "✓ 自动清理已启用"
    fi
    
    save_settings
    sleep 2
}

# 设置备份数量
set_backup_count() {
    echo
    print_color $CYAN "当前备份数量: $LOG_BACKUP_COUNT"
    echo
    read -p "请输入新的备份数量 (0-10): " new_count
    
    if [[ ! "$new_count" =~ ^[0-9]$|^10$ ]]; then
        print_color $RED "请输入0-10之间的数字"
        sleep 2
        return
    fi
    
    LOG_BACKUP_COUNT="$new_count"
    save_settings
    print_color $GREEN "✓ 备份数量已设置为: $LOG_BACKUP_COUNT"
    sleep 2
}

# 手动清理所有日志
manual_clean_logs() {
    echo
    print_color $RED "警告: 此操作将删除所有日志文件和备份"
    read -p "确认清理所有日志? [y/N]: " confirm
    
    if [[ "$confirm" =~ ^[Yy] ]]; then
        rm -f "$LOG_DIR"/*.log
        rm -f "$LOG_DIR"/*.log.*
        print_color $GREEN "✓ 所有日志文件已清理"
    else
        print_color $YELLOW "已取消清理"
    fi
    
    sleep 2
}

# 检查所有日志文件
check_all_logs() {
    echo
    print_color $BLUE "正在检查所有日志文件..."
    
    local rotated_count=0
    for log_file in "$LOG_DIR"/*.log; do
        if [[ -f "$log_file" ]]; then
            local old_size=$(get_human_readable_size "$log_file")
            check_and_clean_log "$log_file"
            local new_size=$(get_human_readable_size "$log_file")
            
            if [[ "$old_size" != "$new_size" ]]; then
                ((rotated_count++))
                print_color $GREEN "  $(basename "$log_file"): $old_size → $new_size"
            fi
        fi
    done
    
    if [[ $rotated_count -eq 0 ]]; then
        print_color $GREEN "✓ 所有日志文件都在大小限制内"
    else
        print_color $GREEN "✓ 已轮转 $rotated_count 个日志文件"
    fi
    
    sleep 2
}
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

# 获取服务的所有命令
get_service_commands() {
    local service_name=$1
    grep "^${service_name}=" "$CONFIG_FILE" | cut -d'=' -f2-
}

# 获取命令PID
get_command_pid() {
    local service_name=$1
    local cmd_index=$2
    local pid_file="$PID_DIR/${service_name}_${cmd_index}.pid"
    
    if [[ -f "$pid_file" ]]; then
        cat "$pid_file"
    else
        echo "N/A"
    fi
}

# 启动单个命令
start_command() {
    local service_name=$1
    local cmd_index=$2
    local command=$3
    local log_file="$LOG_DIR/${service_name}_${cmd_index}.log"
    local pid_file="$PID_DIR/${service_name}_${cmd_index}.pid"
    
    if is_command_running "$service_name" "$cmd_index"; then
        print_color $YELLOW "命令 $cmd_index 已经在运行"
        return 1
    fi
    
    print_color $BLUE "启动命令 $cmd_index: $command"
    
    # 检查并清理日志文件
    check_and_clean_log "$log_file"
    
    # 使用setsid确保进程独立运行
    setsid bash -c "exec $command" > "$log_file" 2>&1 &
    local pid=$!
    echo "$pid" > "$pid_file"
    
    sleep 2
    if is_command_running "$service_name" "$cmd_index"; then
        print_color $GREEN "✓ 命令 $cmd_index 启动成功 (PID: $pid)"
    else
        print_color $RED "✗ 命令 $cmd_index 启动失败"
        rm -f "$pid_file"
        return 1
    fi
}

# 停止单个命令
stop_command() {
    local service_name=$1
    local cmd_index=$2
    local pid_file="$PID_DIR/${service_name}_${cmd_index}.pid"
    
    if ! is_command_running "$service_name" "$cmd_index"; then
        print_color $YELLOW "命令 $cmd_index 未运行"
        return 1
    fi
    
    local pid=$(cat "$pid_file")
    print_color $BLUE "停止命令 $cmd_index (PID: $pid)"
    
    # 优雅停止
    kill -TERM "$pid" 2>/dev/null
    sleep 2
    
    if kill -0 "$pid" 2>/dev/null; then
        print_color $YELLOW "强制终止..."
        kill -KILL "$pid" 2>/dev/null
    fi
    
    rm -f "$pid_file"
    print_color $GREEN "✓ 命令 $cmd_index 已停止"
}

# 启动服务的所有命令
start_all_service_commands() {
    local service_name=$1
    local commands
    commands=$(get_service_commands "$service_name")
    
    print_color $BLUE "启动服务 '$service_name' 的所有命令..."
    
    local cmd_index=1
    while IFS='|' read -ra CMDS; do
        for cmd in "${CMDS[@]}"; do
            start_command "$service_name" "$cmd_index" "$cmd"
            ((cmd_index++))
        done
    done <<< "$commands"
}

# 停止服务的所有命令
stop_all_service_commands() {
    local service_name=$1
    local commands
    commands=$(get_service_commands "$service_name")
    
    print_color $BLUE "停止服务 '$service_name' 的所有命令..."
    
    local cmd_count=$(echo "$commands" | tr '|' '\n' | wc -l)
    for ((i=1; i<=cmd_count; i++)); do
        stop_command "$service_name" "$i"
    done
}

# 为服务添加新命令
add_command_to_service() {
    local service_name=$1
    
    echo
    read -p "请输入新命令: " new_command
    
    if [[ -z "$new_command" ]]; then
        print_color $RED "命令不能为空"
        sleep 1
        return
    fi
    
    local current_commands
    current_commands=$(get_service_commands "$service_name")
    local new_commands="${current_commands}|${new_command}"
    
    # 更新配置文件
    sed -i "s|^${service_name}=.*|${service_name}=${new_commands}|" "$CONFIG_FILE"
    
    print_color $GREEN "✓ 命令添加成功"
    
    echo
    read -p "是否立即启动新命令? [y/N]: " start_now
    if [[ "$start_now" =~ ^[Yy] ]]; then
        local cmd_count=$(echo "$new_commands" | tr '|' '\n' | wc -l)
        start_command "$service_name" "$cmd_count" "$new_command"
    fi
    
    echo
    read -p "按回车键继续..."
}

# 从服务中删除命令
remove_command_from_service() {
    local service_name=$1
    local commands
    commands=$(get_service_commands "$service_name")
    local cmd_count=$(echo "$commands" | tr '|' '\n' | wc -l)
    
    if [[ $cmd_count -eq 1 ]]; then
        print_color $RED "服务至少需要保留一个命令，请使用删除服务功能"
        sleep 2
        return
    fi
    
    echo
    print_color $CYAN "当前命令列表:"
    echo "$commands" | tr '|' '\n' | nl -w2 -s'. '
    echo
    read -p "请输入要删除的命令序号: " cmd_index
    
    if [[ ! "$cmd_index" =~ ^[1-9][0-9]*$ ]] || [[ $cmd_index -gt $cmd_count ]]; then
        print_color $RED "无效的命令序号"
        sleep 1
        return
    fi
    
    # 停止命令
    if is_command_running "$service_name" "$cmd_index"; then
        stop_command "$service_name" "$cmd_index"
    fi
    
    # 重建命令列表
    local new_commands=""
    local current_index=1
    while IFS='|' read -ra CMDS; do
        for cmd in "${CMDS[@]}"; do
            if [[ $current_index -ne $cmd_index ]]; then
                if [[ -n "$new_commands" ]]; then
                    new_commands="${new_commands}|${cmd}"
                else
                    new_commands="$cmd"
                fi
            fi
            ((current_index++))
        done
    done <<< "$commands"
    
    # 更新配置文件
    sed -i "s|^${service_name}=.*|${service_name}=${new_commands}|" "$CONFIG_FILE"
    
    # 重新整理PID和日志文件
    reorganize_service_files "$service_name"
    
    print_color $GREEN "✓ 命令删除成功"
    echo
    read -p "按回车键继续..."
}

# 重新整理服务文件
reorganize_service_files() {
    local service_name=$1
    local commands
    commands=$(get_service_commands "$service_name")
    
    # 获取当前运行的命令信息
    local running_commands=()
    local cmd_count_before=$(ls "$PID_DIR/${service_name}_"*.pid 2>/dev/null | wc -l)
    
    # 保存当前运行的命令
    for ((i=1; i<=cmd_count_before; i++)); do
        local pid_file="$PID_DIR/${service_name}_${i}.pid"
        if [[ -f "$pid_file" ]] && is_command_running "$service_name" "$i"; then
            running_commands[$i]=$(cat "$pid_file")
        fi
    done
    
    # 清理所有旧文件
    rm -f "$PID_DIR/${service_name}_"*.pid
    
    # 重新创建PID文件（只保留仍在运行的进程）
    local new_index=1
    for ((old_index=1; old_index<=cmd_count_before; old_index++)); do
        if [[ -n "${running_commands[$old_index]}" ]]; then
            # 检查进程是否仍在运行
            if kill -0 "${running_commands[$old_index]}" 2>/dev/null; then
                echo "${running_commands[$old_index]}" > "$PID_DIR/${service_name}_${new_index}.pid"
                
                # 移动对应的日志文件
                local old_log="$LOG_DIR/${service_name}_${old_index}.log"
                local new_log="$LOG_DIR/${service_name}_${new_index}.log"
                if [[ -f "$old_log" && "$old_log" != "$new_log" ]]; then
                    mv "$old_log" "$new_log"
                fi
                
                ((new_index++))
            fi
        fi
    done
    
    # 清理多余的日志文件
    for ((i=new_index; i<=cmd_count_before; i++)); do
        rm -f "$LOG_DIR/${service_name}_${i}.log"
    done
}

# 修改服务命令
modify_service_command() {
    local service_name=$1
    local commands
    commands=$(get_service_commands "$service_name")
    local cmd_count=$(echo "$commands" | tr '|' '\n' | wc -l)
    
    echo
    print_color $CYAN "当前命令列表:"
    echo "$commands" | tr '|' '\n' | nl -w2 -s'. '
    echo
    read -p "请输入要修改的命令序号: " cmd_index
    
    if [[ ! "$cmd_index" =~ ^[1-9][0-9]*$ ]] || [[ $cmd_index -gt $cmd_count ]]; then
        print_color $RED "无效的命令序号"
        sleep 1
        return
    fi
    
    # 获取当前命令
    local current_cmd
    current_cmd=$(echo "$commands" | tr '|' '\n' | sed -n "${cmd_index}p")
    
    echo
    print_color $CYAN "当前命令: $current_cmd"
    read -p "请输入新命令: " new_command
    
    if [[ -z "$new_command" ]]; then
        print_color $RED "命令不能为空"
        sleep 1
        return
    fi
    
    # 停止旧命令
    if is_command_running "$service_name" "$cmd_index"; then
        print_color $BLUE "停止旧命令..."
        stop_command "$service_name" "$cmd_index"
    fi
    
    # 构建新的命令列表
    local new_commands=""
    local current_index=1
    while IFS='|' read -ra CMDS; do
        for cmd in "${CMDS[@]}"; do
            local cmd_to_add="$cmd"
            if [[ $current_index -eq $cmd_index ]]; then
                cmd_to_add="$new_command"
            fi
            
            if [[ -n "$new_commands" ]]; then
                new_commands="${new_commands}|${cmd_to_add}"
            else
                new_commands="$cmd_to_add"
            fi
            ((current_index++))
        done
    done <<< "$commands"
    
    # 更新配置文件
    sed -i "s|^${service_name}=.*|${service_name}=${new_commands}|" "$CONFIG_FILE"
    
    print_color $GREEN "✓ 命令修改成功"
    
    echo
    read -p "是否立即启动新命令? [y/N]: " start_now
    if [[ "$start_now" =~ ^[Yy] ]]; then
        start_command "$service_name" "$cmd_index" "$new_command"
    fi
    
    echo
    read -p "按回车键继续..."
}

# 确认删除服务
confirm_delete_service() {
    local service_name=$1
    
    print_color $RED "警告: 即将删除服务 '$service_name' 及其所有命令"
    read -p "确认删除? [y/N]: " confirm
    
    if [[ "$confirm" =~ ^[Yy] ]]; then
        delete_service "$service_name"
        print_color $GREEN "✓ 服务 '$service_name' 已删除"
        sleep 1
        return 0
    else
        print_color $YELLOW "已取消删除"
        sleep 1
        return 1
    fi
}

# 删除服务
delete_service() {
    local service_name=$1
    
    # 停止所有命令
    stop_all_service_commands "$service_name"
    
    # 从配置文件删除
    grep -v "^${service_name}=" "$CONFIG_FILE" > "${CONFIG_FILE}.tmp" 2>/dev/null
    mv "${CONFIG_FILE}.tmp" "$CONFIG_FILE" 2>/dev/null
    
    # 删除相关文件
    rm -f "$PID_DIR/${service_name}_"*.pid
    
    # 询问是否删除日志
    read -p "是否同时删除所有日志文件? [y/N]: " delete_log
    if [[ "$delete_log" =~ ^[Yy] ]]; then
        rm -f "$LOG_DIR/${service_name}_"*.log
    fi
}

# 启动服务菜单
start_service_menu() {
    local service_name
    service_name=$(show_service_menu "启动服务")
    
    if [[ $? -eq 0 && -n "$service_name" ]]; then
        echo
        start_all_service_commands "$service_name"
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
        stop_all_service_commands "$service_name"
        echo
        read -p "按回车键继续..."
    fi
}

# 重启服务菜单
restart_service_menu() {
    local service_name
    service_name=$(show_service_menu "重启服务")
    
    if [[ $? -eq 0 && -n "$service_name" ]]; then
        echo
        print_color $BLUE "重启服务: $service_name"
        stop_all_service_commands "$service_name"
        echo
        sleep 2
        start_all_service_commands "$service_name"
        echo
        read -p "按回车键继续..."
    fi
}

# 查看服务状态
show_status() {
    clear
    print_color $BLUE "====================== 服务状态总览 ======================"
    echo
    
    if [[ ! -f "$CONFIG_FILE" ]]; then
        print_color $YELLOW "暂无配置的服务"
        echo
        read -p "按回车键返回主菜单..."
        return
    fi
    
    local total_services=0
    local running_services=0
    local total_commands=0
    local running_commands=0
    
    while IFS='=' read -r name commands; do
        if [[ -n "$name" ]]; then
            ((total_services++))
            local service_running=false
            local cmd_count=$(echo "$commands" | tr '|' '\n' | wc -l)
            total_commands=$((total_commands + cmd_count))
            local service_running_count=0
            
            print_color $CYAN "服务: $name"
            
            # 检查每个命令的状态
            local cmd_index=1
            while IFS='|' read -ra CMDS; do
                for cmd in "${CMDS[@]}"; do
                    local status="已停止"
                    local color=$RED
                    local pid="N/A"
                    local uptime="N/A"
                    
                    if is_command_running "$name" "$cmd_index"; then
                        status="运行中"
                        color=$GREEN
                        service_running=true
                        ((running_commands++))
                        ((service_running_count++))
                        
                        local pid_file="$PID_DIR/${name}_${cmd_index}.pid"
                        if [[ -f "$pid_file" ]]; then
                            pid=$(cat "$pid_file")
                            # 计算运行时间
                            local start_time=$(stat -f%m "$pid_file" 2>/dev/null || stat -c%Y "$pid_file" 2>/dev/null)
                            if [[ -n "$start_time" ]]; then
                                local current_time=$(date +%s)
                                local duration=$((current_time - start_time))
                                if command -v date >/dev/null 2>&1; then
                                    uptime=$(date -d@$duration -u +%H:%M:%S 2>/dev/null || date -r $duration +%H:%M:%S 2>/dev/null || echo "${duration}秒")
                                else
                                    uptime="${duration}秒"
                                fi
                            fi
                        fi
                    fi
                    
                    printf "  命令 %d: " $cmd_index
                    print_color $color "[$status]"
                    printf " PID: %-8s 运行时间: %-12s\n" "$pid" "$uptime"
                    printf "           %s\n" "$cmd"
                    
                    # 显示日志大小
                    local log_file="$LOG_DIR/${name}_${cmd_index}.log"
                    local log_size=$(get_human_readable_size "$log_file")
                    printf "           日志: %s\n" "$log_size"
                    
                    ((cmd_index++))
                done
            done <<< "$commands"
            
            # 服务整体状态
            if [[ "$service_running" == "true" ]]; then
                ((running_services++))
                if [[ $service_running_count -eq $cmd_count ]]; then
                    print_color $GREEN "  整体状态: 完全运行 ($service_running_count/$cmd_count)"
                else
                    print_color $YELLOW "  整体状态: 部分运行 ($service_running_count/$cmd_count)"
                fi
            else
                print_color $RED "  整体状态: 完全停止 (0/$cmd_count)"
            fi
            
            echo
        fi
    done < "$CONFIG_FILE"
    
    print_color $BLUE "======================================================="
    print_color $CYAN "统计信息:"
    print_color $GREEN "总服务数: $total_services (运行中: $running_services)"
    print_color $GREEN "总命令数: $total_commands (运行中: $running_commands)"
    
    # 显示守护进程状态
    echo
    if is_daemon_running; then
        local daemon_pid=$(cat "$DAEMON_PID_FILE")
        print_color $GREEN "保活守护进程: 运行中 (PID: $daemon_pid)"
    else
        print_color $YELLOW "保活守护进程: 未运行 (建议启动以自动重启异常退出的服务)"
    fi
    
    # 显示日志管理设置
    print_color $CYAN "日志设置: 大小限制 $LOG_MAX_SIZE, 自动清理 $LOG_AUTO_CLEAN, 备份数量 $LOG_BACKUP_COUNT"
    
    echo
    read -p "按回车键返回主菜单..."
}
