#!/bin/bash

# Service Keeper - 服务保活管理脚本
# 版本: 2.4 彻底修复版
# 功能: 多命令服务管理、日志轮转、保活守护、开机自启、快捷键

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

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
PURPLE='\033[0;35m'
NC='\033[0m'

# 打印彩色输出
print_color() {
    local color=$1
    shift
    echo -e "${color}$*${NC}"
}

# 清理服务名 - 新增函数
clean_service_name() {
    local name="$1"
    # 移除单引号、双引号和多余空格
    name="${name//\'/}"
    name="${name//\"/}"
    name="${name// /}"
    # 移除非标准字符，只保留字母数字下划线短横线
    name=$(echo "$name" | sed 's/[^a-zA-Z0-9_-]//g')
    echo "$name"
}

# 初始化设置文件
init_settings() {
    if [[ ! -f "$SETTINGS_FILE" ]]; then
        cat > "$SETTINGS_FILE" << 'EOF'
LOG_MAX_SIZE=1M
LOG_AUTO_CLEAN=true
LOG_BACKUP_COUNT=3
EOF
    fi
}

# 读取设置
load_settings() {
    init_settings
    if [[ -f "$SETTINGS_FILE" ]]; then
        source "$SETTINGS_FILE"
    fi
    LOG_MAX_SIZE=${LOG_MAX_SIZE:-$DEFAULT_LOG_MAX_SIZE}
    LOG_AUTO_CLEAN=${LOG_AUTO_CLEAN:-true}
    LOG_BACKUP_COUNT=${LOG_BACKUP_COUNT:-3}
}

# 保存设置
save_settings() {
    cat > "$SETTINGS_FILE" << EOF
LOG_MAX_SIZE=${LOG_MAX_SIZE}
LOG_AUTO_CLEAN=${LOG_AUTO_CLEAN}
LOG_BACKUP_COUNT=${LOG_BACKUP_COUNT}
EOF
}

# 初始化
load_settings

# 设置快捷键
setup_shortcut() {
    local script_path="$SCRIPT_DIR/$(basename "$0")"
    local bashrc_file="$HOME/.bashrc"
    local alias_line="alias h='$script_path'"
    
    if ! grep -q "alias h=" "$bashrc_file" 2>/dev/null; then
        echo "$alias_line" >> "$bashrc_file"
        print_color $GREEN "✓ 快捷键 'h' 已设置，重新登录后生效"
        print_color $CYAN "或者执行: source ~/.bashrc"
    else
        print_color $YELLOW "快捷键 'h' 已存在"
    fi
}

# 检查命令是否运行
is_command_running() {
    local service_name=$(clean_service_name "$1")
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

# 获取服务的所有命令
get_service_commands() {
    local service_name=$(clean_service_name "$1")
    if [[ -f "$CONFIG_FILE" ]]; then
        grep "^${service_name}=" "$CONFIG_FILE" | cut -d'=' -f2-
    fi
}

# 获取日志文件大小
get_human_readable_size() {
    local file=$1
    if [[ ! -f "$file" ]]; then
        echo "0B"
        return
    fi
    
    local size=$(stat -c%s "$file" 2>/dev/null || stat -f%z "$file" 2>/dev/null || echo 0)
    
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

# 检查并清理日志文件
check_and_clean_log() {
    local log_file=$1
    
    if [[ ! -f "$log_file" ]] || [[ "$LOG_AUTO_CLEAN" != "true" ]]; then
        return 0
    fi
    
    local file_size=$(stat -c%s "$log_file" 2>/dev/null || stat -f%z "$log_file" 2>/dev/null || echo 0)
    local max_bytes
    
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
    
    for ((i=LOG_BACKUP_COUNT; i>=1; i--)); do
        local old_backup="${dir_name}/${base_name}.${i}.log"
        local new_backup="${dir_name}/${base_name}.$((i+1)).log"
        
        if [[ -f "$old_backup" ]]; then
            if [[ $i -eq $LOG_BACKUP_COUNT ]]; then
                rm -f "$old_backup"
            else
                mv "$old_backup" "$new_backup"
            fi
        fi
    done
    
    if [[ -f "$log_file" ]]; then
        mv "$log_file" "${dir_name}/${base_name}.1.log"
        touch "$log_file"
        print_color $GREEN "✓ 日志轮转完成"
    fi
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
    local service_names=()
    
    while IFS='=' read -r name commands; do
        if [[ -n "$name" ]]; then
            ((total_services++))
            service_names+=("$name")
            local service_running=false
            local cmd_count=$(echo "$commands" | tr '|' '\n' | wc -l)
            ((total_commands += cmd_count))
            
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
    
    if [[ ${#service_names[@]} -gt 0 ]]; then
        printf "已配置服务: "
        for i in "${!service_names[@]}"; do
            if [[ $i -gt 0 ]]; then
                printf ", "
            fi
            printf "%s" "${service_names[$i]}"
        done
        echo
    fi
}

# 显示主菜单
show_main_menu() {
    clear
    print_color $BLUE "====================== 服务保活管理器 ======================"
    print_color $GREEN "1. 添加新服务"
    print_color $GREEN "2. 管理现有服务"
    print_color $GREEN "3. 启动服务"
    print_color $GREEN "4. 停止服务"
    print_color $GREEN "5. 重启服务"
    print_color $GREEN "6. 查看服务状态"
    print_color $GREEN "7. 查看服务日志"
    print_color $GREEN "8. 删除服务"
    print_color $CYAN "9. 启动保活守护进程"
    print_color $CYAN "10. 停止保活守护进程"
    print_color $PURPLE "11. 日志管理设置"
    print_color $YELLOW "12. 设置开机自启"
    print_color $YELLOW "13. 取消开机自启"
    print_color $PURPLE "14. 设置快捷键"
    print_color $RED "0. 退出"
    print_color $BLUE "=========================================================="
    
    if is_daemon_running; then
        print_color $GREEN "保活守护进程: 运行中"
    else
        print_color $YELLOW "保活守护进程: 未运行"
    fi
    
    show_service_summary
    echo
    echo -n "请选择操作 [0-14]: "
}

# 显示服务列表 - 增强版本
show_services_list() {
    if [[ ! -f "$CONFIG_FILE" ]]; then
        print_color $YELLOW "暂无配置的服务"
        return 1
    fi
    
    print_color $CYAN "已配置的服务列表:"
    echo
    local index=1
    local has_services=false
    
    while IFS='=' read -r name commands; do
        if [[ -n "$name" ]]; then
            has_services=true
            
            # 清理服务名
            local clean_name=$(clean_service_name "$name")
            
            # 使用数组处理命令
            local cmd_array=()
            while IFS= read -r line; do
                [[ -n "$line" ]] && cmd_array+=("$line")
            done <<< "$(echo "$commands" | tr '|' '\n')"
            
            local cmd_count=${#cmd_array[@]}
            local running_count=0
            
            for ((i=1; i<=cmd_count; i++)); do
                if is_command_running "$clean_name" "$i"; then
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
            
            printf "%2d. %-20s " $index "$clean_name"
            print_color $status_color "[$status]"
            printf " 命令数: %d (运行: %d)\n" "$cmd_count" "$running_count"
            
            # 显示前3个命令的简要信息
            for i in "${!cmd_array[@]}"; do
                if [[ $i -lt 3 ]]; then
                    local cmd_index=$((i + 1))
                    local cmd="${cmd_array[i]}"
                    local cmd_status="停止"
                    local cmd_color=$RED
                    
                    if is_command_running "$clean_name" "$cmd_index"; then
                        cmd_status="运行"
                        cmd_color=$GREEN
                    fi
                    
                    printf "     %d. " $cmd_index
                    print_color $cmd_color "[$cmd_status]"
                    printf " %s\n" "${cmd:0:50}..."
                elif [[ $i -eq 3 && ${#cmd_array[@]} -gt 3 ]]; then
                    printf "     ... 还有 %d 个命令\n" $((${#cmd_array[@]} - 3))
                    break
                fi
            done
            echo
            
            ((index++))
        fi
    done < "$CONFIG_FILE"
    
    if [[ "$has_services" == "false" ]]; then
        print_color $YELLOW "暂无配置的服务"
        return 1
    fi
    
    return 0
}

# 根据索引获取服务名 - 修复版本
get_service_by_index() {
    local target_index=$1
    local current_index=1
    
    if [[ ! -f "$CONFIG_FILE" ]]; then
        return 1
    fi
    
    while IFS='=' read -r name commands; do
        if [[ -n "$name" ]]; then
            if [[ $current_index -eq $target_index ]]; then
                # 返回清理后的服务名
                clean_service_name "$name"
                return 0
            fi
            ((current_index++))
        fi
    done < "$CONFIG_FILE"
    
    return 1
}

# 选择服务
select_service() {
    local action=$1
    clear
    print_color $BLUE "================= $action ================="
    echo
    
    if ! show_services_list; then
        echo
        read -p "按回车键返回主菜单..."
        return 1
    fi
    
    echo
    print_color $BLUE "======================================================"
    read -p "请输入服务序号 (0返回主菜单): " choice
    
    if [[ "$choice" == "0" ]]; then
        return 1
    fi
    
    local service_name
    service_name=$(get_service_by_index "$choice")
    
    if [[ -z "$service_name" ]]; then
        print_color $RED "无效的服务序号"
        sleep 2
        return 1
    fi
    
    echo "$service_name"
}

# 启动单个命令
start_command() {
    local service_name=$(clean_service_name "$1")
    local cmd_index=$2
    local command="$3"
    local log_file="$LOG_DIR/${service_name}_${cmd_index}.log"
    local pid_file="$PID_DIR/${service_name}_${cmd_index}.pid"
    
    if is_command_running "$service_name" "$cmd_index"; then
        print_color $YELLOW "命令 $cmd_index 已经在运行"
        return 1
    fi
    
    print_color $BLUE "启动命令 $cmd_index: $command"
    
    check_and_clean_log "$log_file"
    
    nohup bash -c "exec $command" > "$log_file" 2>&1 &
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
    local service_name=$(clean_service_name "$1")
    local cmd_index=$2
    local pid_file="$PID_DIR/${service_name}_${cmd_index}.pid"
    
    if ! is_command_running "$service_name" "$cmd_index"; then
        print_color $YELLOW "命令 $cmd_index 未运行"
        return 1
    fi
    
    local pid=$(cat "$pid_file")
    print_color $BLUE "停止命令 $cmd_index (PID: $pid)"
    
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
start_all_commands() {
    local service_name=$(clean_service_name "$1")
    local commands
    commands=$(get_service_commands "$service_name")
    
    if [[ -z "$commands" ]]; then
        print_color $RED "服务 '$service_name' 不存在"
        return 1
    fi
    
    print_color $BLUE "启动服务 '$service_name' 的所有命令..."
    
    # 使用数组避免子shell问题
    local cmd_array=()
    while IFS= read -r line; do
        [[ -n "$line" ]] && cmd_array+=("$line")
    done <<< "$(echo "$commands" | tr '|' '\n')"
    
    for i in "${!cmd_array[@]}"; do
        local cmd_index=$((i + 1))
        start_command "$service_name" "$cmd_index" "${cmd_array[i]}"
    done
}

# 停止服务的所有命令
stop_all_commands() {
    local service_name=$(clean_service_name "$1")
    local commands
    commands=$(get_service_commands "$service_name")
    
    if [[ -z "$commands" ]]; then
        print_color $RED "服务 '$service_name' 不存在"
        return 1
    fi
    
    print_color $BLUE "停止服务 '$service_name' 的所有命令..."
    
    local cmd_count=$(echo "$commands" | tr '|' '\n' | wc -l)
    for ((i=1; i<=cmd_count; i++)); do
        stop_command "$service_name" "$i"
    done
}

# 添加服务
add_service() {
    clear
    print_color $BLUE "====================== 添加新服务 ======================"
    echo
    read -p "请输入服务名称: " service_name
    
    # 清理服务名
    service_name=$(clean_service_name "$service_name")
    
    if [[ -z "$service_name" ]]; then
        print_color $RED "服务名称格式错误（只能包含字母、数字、下划线和短横线）"
        sleep 2
        return
    fi
    
    if [[ -f "$CONFIG_FILE" ]] && grep -q "^${service_name}=" "$CONFIG_FILE"; then
        print_color $RED "服务 '$service_name' 已存在"
        sleep 2
        return
    fi
    
    echo
    print_color $CYAN "为服务 '$service_name' 添加命令:"
    print_color $YELLOW "提示: 你可以添加多个命令，每个命令将独立运行和监控"
    echo
    
    local commands=""
    local cmd_num=1
    
    while true; do
        echo
        print_color $BLUE "=== 添加第 $cmd_num 个命令 ==="
        read -p "请输入命令内容 (直接回车完成添加): " command
        
        if [[ -z "$command" ]]; then
            if [[ $cmd_num -eq 1 ]]; then
                print_color $RED "至少需要添加一个命令"
                continue
            else
                break
            fi
        fi
        
        echo
        print_color $CYAN "命令预览: $command"
        read -p "确认添加此命令? [Y/n]: " confirm
        if [[ "$confirm" =~ ^[Nn] ]]; then
            print_color $YELLOW "已跳过此命令"
            continue
        fi
        
        if [[ -n "$commands" ]]; then
            commands="${commands}|${command}"
        else
            commands="$command"
        fi
        
        print_color $GREEN "✓ 已添加命令 $cmd_num: $command"
        ((cmd_num++))
        
        echo
        read -p "是否继续添加更多命令? [y/N]: " continue_add
        if [[ ! "$continue_add" =~ ^[Yy] ]]; then
            break
        fi
    done
    
    echo
    print_color $BLUE "==================== 服务信息摘要 ===================="
    print_color $CYAN "服务名称: $service_name"
    print_color $CYAN "命令总数: $((cmd_num-1))"
    echo
    print_color $GREEN "命令列表:"
    local cmd_index=1
    # 使用数组避免子shell问题
    local cmd_array=()
    while IFS= read -r line; do
        [[ -n "$line" ]] && cmd_array+=("$line")
    done <<< "$(echo "$commands" | tr '|' '\n')"
    
    for cmd in "${cmd_array[@]}"; do
        printf "  %d. %s\n" $cmd_index "$cmd"
        ((cmd_index++))
    done
    echo
    print_color $BLUE "====================================================="
    
    read -p "确认创建此服务? [Y/n]: " final_confirm
    if [[ "$final_confirm" =~ ^[Nn] ]]; then
        print_color $YELLOW "已取消创建服务"
        sleep 1
        return
    fi
    
    echo "$service_name=$commands" >> "$CONFIG_FILE"
    print_color $GREEN "✓ 服务 '$service_name' 创建成功！"
    
    echo
    read -p "是否立即启动此服务的所有命令? [Y/n]: " start_now
    if [[ ! "$start_now" =~ ^[Nn] ]]; then
        echo
        start_all_commands "$service_name"
    fi
    
    echo
    read -p "按回车键继续..."
}

# 管理现有服务菜单
manage_existing_service_menu() {
    local service_name
    service_name=$(select_service "管理现有服务")
    
    if [[ $? -eq 0 && -n "$service_name" ]]; then
        manage_service "$service_name"
    fi
}

# 管理单个服务 - 完全修复版本
manage_service() {
    local service_name="$1"
    
    # 清理服务名中的异常字符
    service_name=$(clean_service_name "$service_name")
    
    # 验证服务是否存在
    if [[ ! -f "$CONFIG_FILE" ]] || ! grep -q "^${service_name}=" "$CONFIG_FILE"; then
        print_color $RED "错误: 服务 '$service_name' 不存在"
        echo
        print_color $CYAN "调试信息:"
        echo "  原始参数: '$1'"
        echo "  清理后: '$service_name'"
        echo "  配置文件中的服务:"
        if [[ -f "$CONFIG_FILE" ]]; then
            grep "^[^=]*=" "$CONFIG_FILE" | cut -d'=' -f1 | sed 's/^/    /'
        fi
        echo
        read -p "按回车键继续..."
        return
    fi
    
    while true; do
        clear
        print_color $BLUE "================== 管理服务: $service_name =================="
        echo
        
        show_service_details "$service_name"
        
        echo
        print_color $GREEN "1. 添加新命令到此服务"
        print_color $GREEN "2. 删除命令"
        print_color $GREEN "3. 修改命令"
        print_color $GREEN "4. 启动单个命令"
        print_color $GREEN "5. 停止单个命令"
        print_color $GREEN "6. 重启单个命令"
        print_color $CYAN "7. 启动所有命令"
        print_color $CYAN "8. 停止所有命令"
        print_color $CYAN "9. 重启所有命令"
        print_color $YELLOW "10. 查看服务日志"
        print_color $RED "11. 删除整个服务"
        print_color $BLUE "0. 返回"
        print_color $BLUE "======================================================"
        echo -n "请选择操作 [0-11]: "
        read choice
        
        case $choice in
            1) add_command_to_service "$service_name" ;;
            2) remove_command_from_service "$service_name" ;;
            3) modify_command_in_service "$service_name" ;;
            4) start_single_command_menu "$service_name" ;;
            5) stop_single_command_menu "$service_name" ;;
            6) restart_single_command_menu "$service_name" ;;
            7) 
                echo
                start_all_commands "$service_name"
                echo
                read -p "按回车键继续..."
                ;;
            8) 
                echo
                stop_all_commands "$service_name"
                echo
                read -p "按回车键继续..."
                ;;
            9) 
                echo
                print_color $BLUE "重启服务所有命令..."
                stop_all_commands "$service_name"
                sleep 2
                start_all_commands "$service_name"
                echo
                read -p "按回车键继续..."
                ;;
            10) show_service_logs "$service_name" ;;
            11) 
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

# 显示服务详细信息 - 完全修复版本
show_service_details() {
    local service_name=$(clean_service_name "$1")
    
    if [[ -z "$service_name" ]]; then
        print_color $RED "错误: 服务名为空"
        return 1
    fi
    
    local commands
    commands=$(get_service_commands "$service_name")
    
    if [[ -z "$commands" ]]; then
        print_color $RED "错误: 服务 '$service_name' 不存在或无命令"
        return 1
    fi
    
    # 使用数组避免子shell问题
    local cmd_array=()
    while IFS= read -r line; do
        [[ -n "$line" ]] && cmd_array+=("$line")
    done <<< "$(echo "$commands" | tr '|' '\n')"
    
    local cmd_count=${#cmd_array[@]}
    
    print_color $CYAN "服务详情:"
    printf "  服务名称: %s\n" "$service_name"
    printf "  命令总数: %d\n" "$cmd_count"
    echo
    
    print_color $CYAN "命令列表:"
    for i in "${!cmd_array[@]}"; do
        local cmd_index=$((i + 1))
        local cmd="${cmd_array[i]}"
        local status="已停止"
        local color=$RED
        local pid="N/A"
        
        if is_command_running "$service_name" "$cmd_index"; then
            status="运行中"
            color=$GREEN
            local pid_file="$PID_DIR/${service_name}_${cmd_index}.pid"
            if [[ -f "$pid_file" ]]; then
                pid=$(cat "$pid_file")
            fi
        fi
        
        printf "  %d. " $cmd_index
        print_color $color "[$status]"
        printf " PID: %-8s\n" "$pid"
        printf "     命令: %s\n" "$cmd"
        
        local log_file="$LOG_DIR/${service_name}_${cmd_index}.log"
        local log_size=$(get_human_readable_size "$log_file")
        printf "     日志: %s\n" "$log_size"
        echo
    done
}

# 添加命令到现有服务
add_command_to_service() {
    local service_name=$(clean_service_name "$1")
    
    clear
    print_color $BLUE "================ 为服务 '$service_name' 添加新命令 ================"
    echo
    
    print_color $CYAN "当前命令列表:"
    show_service_details "$service_name"
    
    echo
    print_color $GREEN "添加新命令:"
    read -p "请输入新命令: " new_command
    
    if [[ -z "$new_command" ]]; then
        print_color $RED "命令不能为空"
        sleep 2
        return
    fi
    
    echo
    print_color $CYAN "新命令预览: $new_command"
    read -p "确认添加此命令? [Y/n]: " confirm
    if [[ "$confirm" =~ ^[Nn] ]]; then
        print_color $YELLOW "已取消添加"
        sleep 1
        return
    fi
    
    local current_commands
    current_commands=$(get_service_commands "$service_name")
    local new_commands="${current_commands}|${new_command}"
    
    if [[ -f "$CONFIG_FILE" ]]; then
        # 使用临时文件确保安全更新
        local temp_file="${CONFIG_FILE}.tmp"
        grep -v "^${service_name}=" "$CONFIG_FILE" > "$temp_file" 2>/dev/null || true
        echo "${service_name}=${new_commands}" >> "$temp_file"
        mv "$temp_file" "$CONFIG_FILE"
    fi
    
    print_color $GREEN "✓ 新命令添加成功！"
    
    echo
    read -p "是否立即启动新命令? [Y/n]: " start_now
    if [[ ! "$start_now" =~ ^[Nn] ]]; then
        local cmd_count=$(echo "$new_commands" | tr '|' '\n' | wc -l)
        echo
        start_command "$service_name" "$cmd_count" "$new_command"
    fi
    
    echo
    read -p "按回车键继续..."
}

# 删除服务中的命令 - 修复版本
remove_command_from_service() {
    local service_name=$(clean_service_name "$1")
    local commands
    commands=$(get_service_commands "$service_name")
    
    # 使用数组避免子shell问题
    local cmd_array=()
    while IFS= read -r line; do
        [[ -n "$line" ]] && cmd_array+=("$line")
    done <<< "$(echo "$commands" | tr '|' '\n')"
    
    local cmd_count=${#cmd_array[@]}
    
    if [[ $cmd_count -eq 1 ]]; then
        print_color $RED "服务只有一个命令，不能删除。如需删除请删除整个服务。"
        sleep 2
        return
    fi
    
    clear
    print_color $BLUE "================ 从服务 '$service_name' 删除命令 ================"
    echo
    
    print_color $CYAN "当前命令列表:"
    for i in "${!cmd_array[@]}"; do
        local cmd_index=$((i + 1))
        local cmd="${cmd_array[i]}"
        local status="已停止"
        local color=$RED
        
        if is_command_running "$service_name" "$cmd_index"; then
            status="运行中"
            color=$GREEN
        fi
        
        printf "  %d. " $cmd_index
        print_color $color "[$status]"
        printf " %s\n" "$cmd"
    done
    
    echo
    read -p "请输入要删除的命令序号 (1-$cmd_count): " cmd_to_delete
    
    if [[ ! "$cmd_to_delete" =~ ^[1-9][0-9]*$ ]] || [[ $cmd_to_delete -gt $cmd_count ]]; then
        print_color $RED "无效的命令序号"
        sleep 2
        return
    fi
    
    local cmd_to_delete_content="${cmd_array[$((cmd_to_delete - 1))]}"
    
    echo
    print_color $RED "警告: 即将删除命令: $cmd_to_delete_content"
    read -p "确认删除? [y/N]: " confirm
    if [[ ! "$confirm" =~ ^[Yy] ]]; then
        print_color $YELLOW "已取消删除"
        sleep 1
        return
    fi
    
    if is_command_running "$service_name" "$cmd_to_delete"; then
        print_color $BLUE "正在停止命令..."
        stop_command "$service_name" "$cmd_to_delete"
    fi
    
    # 重建命令列表，排除要删除的命令
    local new_cmd_array=()
    for i in "${!cmd_array[@]}"; do
        local cmd_index=$((i + 1))
        if [[ $cmd_index -ne $cmd_to_delete ]]; then
            new_cmd_array+=("${cmd_array[i]}")
        fi
    done
    
    # 将数组转换为以|分隔的字符串
    local new_commands=""
    for i in "${!new_cmd_array[@]}"; do
        if [[ $i -eq 0 ]]; then
            new_commands="${new_cmd_array[i]}"
        else
            new_commands="${new_commands}|${new_cmd_array[i]}"
        fi
    done
    
    if [[ -f "$CONFIG_FILE" ]]; then
        # 使用临时文件确保安全更新
        local temp_file="${CONFIG_FILE}.tmp"
        grep -v "^${service_name}=" "$CONFIG_FILE" > "$temp_file" 2>/dev/null || true
        echo "${service_name}=${new_commands}" >> "$temp_file"
        mv "$temp_file" "$CONFIG_FILE"
    fi
    
    reorganize_service_files "$service_name"
    
    print_color $GREEN "✓ 命令删除成功！"
    echo
    read -p "按回车键继续..."
}

# 重新整理服务文件
reorganize_service_files() {
    local service_name=$(clean_service_name "$1")
    local commands
    commands=$(get_service_commands "$service_name")
    
    local running_pids=()
    local max_old_index=20
    
    for ((i=1; i<=max_old_index; i++)); do
        local old_pid_file="$PID_DIR/${service_name}_${i}.pid"
        if [[ -f "$old_pid_file" ]] && is_command_running "$service_name" "$i"; then
            running_pids[$i]=$(cat "$old_pid_file")
        fi
    done
    
    rm -f "$PID_DIR/${service_name}_"*.pid
    
    # 使用数组避免子shell问题
    local cmd_array=()
    while IFS= read -r line; do
        [[ -n "$line" ]] && cmd_array+=("$line")
    done <<< "$(echo "$commands" | tr '|' '\n')"
    
    local new_cmd_index=1
    local old_cmd_index=1
    for cmd in "${cmd_array[@]}"; do
        while [[ $old_cmd_index -le $max_old_index ]]; do
            if [[ -n "${running_pids[$old_cmd_index]}" ]]; then
                if kill -0 "${running_pids[$old_cmd_index]}" 2>/dev/null; then
                    echo "${running_pids[$old_cmd_index]}" > "$PID_DIR/${service_name}_${new_cmd_index}.pid"
                    break
                fi
            fi
            ((old_cmd_index++))
        done
        ((old_cmd_index++))
        ((new_cmd_index++))
    done
}

# 修改服务中的命令 - 修复版本
modify_command_in_service() {
    local service_name=$(clean_service_name "$1")
    local commands
    commands=$(get_service_commands "$service_name")
    
    # 使用数组避免子shell问题
    local cmd_array=()
    while IFS= read -r line; do
        [[ -n "$line" ]] && cmd_array+=("$line")
    done <<< "$(echo "$commands" | tr '|' '\n')"
    
    local cmd_count=${#cmd_array[@]}
    
    clear
    print_color $BLUE "================ 修改服务 '$service_name' 中的命令 ================"
    echo
    
    print_color $CYAN "当前命令列表:"
    for i in "${!cmd_array[@]}"; do
        local cmd_index=$((i + 1))
        local cmd="${cmd_array[i]}"
        printf "  %d. %s\n" $cmd_index "$cmd"
    done
    
    echo
    read -p "请输入要修改的命令序号 (1-$cmd_count): " cmd_to_modify
    
    if [[ ! "$cmd_to_modify" =~ ^[1-9][0-9]*$ ]] || [[ $cmd_to_modify -gt $cmd_count ]]; then
        print_color $RED "无效的命令序号"
        sleep 2
        return
    fi
    
    local current_cmd="${cmd_array[$((cmd_to_modify - 1))]}"
    
    echo
    print_color $CYAN "当前命令: $current_cmd"
    read -p "请输入新命令: " new_cmd
    
    if [[ -z "$new_cmd" ]]; then
        print_color $RED "命令不能为空"
        sleep 2
        return
    fi
    
    echo
    print_color $CYAN "新命令: $new_cmd"
    read -p "确认修改? [Y/n]: " confirm
    if [[ "$confirm" =~ ^[Nn] ]]; then
        print_color $YELLOW "已取消修改"
        sleep 1
        return
    fi
    
    if is_command_running "$service_name" "$cmd_to_modify"; then
        print_color $BLUE "正在停止旧命令..."
        stop_command "$service_name" "$cmd_to_modify"
    fi
    
    # 更新命令数组
    cmd_array[$((cmd_to_modify - 1))]="$new_cmd"
    
    # 将数组转换为以|分隔的字符串
    local new_commands=""
    for i in "${!cmd_array[@]}"; do
        if [[ $i -eq 0 ]]; then
            new_commands="${cmd_array[i]}"
        else
            new_commands="${new_commands}|${cmd_array[i]}"
        fi
    done
    
    if [[ -f "$CONFIG_FILE" ]]; then
        # 使用临时文件确保安全更新
        local temp_file="${CONFIG_FILE}.tmp"
        grep -v "^${service_name}=" "$CONFIG_FILE" > "$temp_file" 2>/dev/null || true
        echo "${service_name}=${new_commands}" >> "$temp_file"
        mv "$temp_file" "$CONFIG_FILE"
    fi
    
    print_color $GREEN "✓ 命令修改成功！"
    
    echo
    read -p "是否立即启动新命令? [Y/n]: " start_now
    if [[ ! "$start_now" =~ ^[Nn] ]]; then
        echo
        start_command "$service_name" "$cmd_to_modify" "$new_cmd"
    fi
    
    echo
    read -p "按回车键继续..."
}

# 启动单个命令菜单
start_single_command_menu() {
    local service_name=$(clean_service_name "$1")
    select_and_operate_command "$service_name" "启动" "start"
}

# 停止单个命令菜单
stop_single_command_menu() {
    local service_name=$(clean_service_name "$1")
    select_and_operate_command "$service_name" "停止" "stop"
}

# 重启单个命令菜单
restart_single_command_menu() {
    local service_name=$(clean_service_name "$1")
    select_and_operate_command "$service_name" "重启" "restart"
}

# 选择并操作命令 - 修复版本
select_and_operate_command() {
    local service_name=$(clean_service_name "$1")
    local action="$2"
    local operation="$3"
    local commands
    commands=$(get_service_commands "$service_name")
    
    # 使用数组避免子shell问题
    local cmd_array=()
    while IFS= read -r line; do
        [[ -n "$line" ]] && cmd_array+=("$line")
    done <<< "$(echo "$commands" | tr '|' '\n')"
    
    local cmd_count=${#cmd_array[@]}
    
    clear
    print_color $BLUE "================ ${action}单个命令: $service_name ================"
    echo
    
    print_color $CYAN "选择要${action}的命令:"
    for i in "${!cmd_array[@]}"; do
        local cmd_index=$((i + 1))
        local cmd="${cmd_array[i]}"
        local status="已停止"
        local color=$RED
        
        if is_command_running "$service_name" "$cmd_index"; then
            status="运行中"
            color=$GREEN
        fi
        
        printf "  %d. " $cmd_index
        print_color $color "[$status]"
        printf " %s\n" "$cmd"
    done
    
    echo
    read -p "请输入命令序号 (1-$cmd_count, 0返回): " cmd_choice
    
    if [[ "$cmd_choice" == "0" ]]; then
        return
    fi
    
    if [[ ! "$cmd_choice" =~ ^[1-9][0-9]*$ ]] || [[ $cmd_choice -gt $cmd_count ]]; then
        print_color $RED "无效的命令序号"
        sleep 2
        return
    fi
    
    local selected_cmd="${cmd_array[$((cmd_choice - 1))]}"
    
    echo
    case $operation in
        "start")
            start_command "$service_name" "$cmd_choice" "$selected_cmd"
            ;;
        "stop")
            stop_command "$service_name" "$cmd_choice"
            ;;
        "restart")
            print_color $BLUE "重启命令: $selected_cmd"
            stop_command "$service_name" "$cmd_choice"
            sleep 2
            start_command "$service_name" "$cmd_choice" "$selected_cmd"
            ;;
    esac
    
    echo
    read -p "按回车键继续..."
}

# 确认删除服务
confirm_delete_service() {
    local service_name=$(clean_service_name "$1")
    
    print_color $RED "警告: 即将删除服务 '$service_name' 及其所有命令！"
    print_color $YELLOW "这将会："
    print_color $YELLOW "• 停止所有运行中的命令"
    print_color $YELLOW "• 删除服务配置"
    print_color $YELLOW "• 删除所有PID文件"
    print_color $YELLOW "• 可选择保留或删除日志文件"
    echo
    read -p "确认删除服务 '$service_name'? [y/N]: " confirm
    
    if [[ "$confirm" =~ ^[Yy] ]]; then
        delete_service "$service_name"
        print_color $GREEN "✓ 服务 '$service_name' 已删除"
        sleep 2
        return 0
    else
        print_color $YELLOW "已取消删除"
        sleep 1
        return 1
    fi
}

# 启动服务菜单
start_service_menu() {
    local service_name
    service_name=$(select_service "启动服务")
    
    if [[ $? -eq 0 && -n "$service_name" ]]; then
        echo
        start_all_commands "$service_name"
        echo
        read -p "按回车键继续..."
    fi
}

# 停止服务菜单
stop_service_menu() {
    local service_name
    service_name=$(select_service "停止服务")
    
    if [[ $? -eq 0 && -n "$service_name" ]]; then
        echo
        stop_all_commands "$service_name"
        echo
        read -p "按回车键继续..."
    fi
}

# 重启服务菜单
restart_service_menu() {
    local service_name
    service_name=$(select_service "重启服务")
    
    if [[ $? -eq 0 && -n "$service_name" ]]; then
        echo
        print_color $BLUE "重启服务: $service_name"
        stop_all_commands "$service_name"
        echo
        sleep 2
        start_all_commands "$service_name"
        echo
        read -p "按回车键继续..."
    fi
}

# 查看服务状态 - 修复版本
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
            local clean_name=$(clean_service_name "$name")
            
            # 使用数组避免子shell问题
            local cmd_array=()
            while IFS= read -r line; do
                [[ -n "$line" ]] && cmd_array+=("$line")
            done <<< "$(echo "$commands" | tr '|' '\n')"
            
            local cmd_count=${#cmd_array[@]}
            total_commands=$((total_commands + cmd_count))
            local service_running_count=0
            
            print_color $CYAN "服务: $clean_name"
            
            for i in "${!cmd_array[@]}"; do
                local cmd_index=$((i + 1))
                local cmd="${cmd_array[i]}"
                local status="已停止"
                local color=$RED
                local pid="N/A"
                
                if is_command_running "$clean_name" "$cmd_index"; then
                    status="运行中"
                    color=$GREEN
                    service_running=true
                    ((running_commands++))
                    ((service_running_count++))
                    
                    local pid_file="$PID_DIR/${clean_name}_${cmd_index}.pid"
                    if [[ -f "$pid_file" ]]; then
                        pid=$(cat "$pid_file")
                    fi
                fi
                
                printf "  命令 %d: " $cmd_index
                print_color $color "[$status]"
                printf " PID: %-8s %s\n" "$pid" "$cmd"
                
                local log_file="$LOG_DIR/${clean_name}_${cmd_index}.log"
                local log_size=$(get_human_readable_size "$log_file")
                printf "           日志: %s\n" "$log_size"
            done
            
            if [[ "$service_running" == "true" ]]; then
                ((running_services++))
            fi
            echo
        fi
    done < "$CONFIG_FILE"
    
    print_color $BLUE "======================================================="
    print_color $CYAN "统计信息:"
    print_color $GREEN "总服务数: $total_services"
    print_color $GREEN "总命令数: $total_commands"
    
    echo
    if is_daemon_running; then
        local daemon_pid=$(cat "$DAEMON_PID_FILE")
        print_color $GREEN "保活守护进程: 运行中 (PID: $daemon_pid)"
    else
        print_color $YELLOW "保活守护进程: 未运行"
    fi
    
    print_color $CYAN "日志设置: 大小限制 $LOG_MAX_SIZE, 自动清理 $LOG_AUTO_CLEAN, 备份数量 $LOG_BACKUP_COUNT"
    
    echo
    read -p "按回车键返回主菜单..."
}

# 查看日志菜单
show_logs_menu() {
    local service_name
    service_name=$(select_service "查看服务日志")
    
    if [[ $? -eq 0 && -n "$service_name" ]]; then
        show_service_logs "$service_name"
    fi
}

# 查看服务日志 - 修复版本
show_service_logs() {
    local service_name=$(clean_service_name "$1")
    local commands
    commands=$(get_service_commands "$service_name")
    
    # 使用数组避免子shell问题
    local cmd_array=()
    while IFS= read -r line; do
        [[ -n "$line" ]] && cmd_array+=("$line")
    done <<< "$(echo "$commands" | tr '|' '\n')"
    
    local cmd_count=${#cmd_array[@]}
    
    clear
    print_color $BLUE "================= $service_name 服务日志 ================="
    echo
    
    if [[ $cmd_count -eq 1 ]]; then
        show_single_log "$service_name" "1"
    else
        print_color $CYAN "该服务有 $cmd_count 个命令，请选择要查看的日志:"
        echo
        
        for i in "${!cmd_array[@]}"; do
            local cmd_index=$((i + 1))
            local cmd="${cmd_array[i]}"
            local log_file="$LOG_DIR/${service_name}_${cmd_index}.log"
            local log_size=$(get_human_readable_size "$log_file")
            local status="停止"
            local color=$RED
            
            if is_command_running "$service_name" "$cmd_index"; then
                status="运行中"
                color=$GREEN
            fi
            
            printf "%2d. 命令 %d " $cmd_index $cmd_index
            print_color $color "[$status]"
            printf " 日志: %s\n" "$log_size"
            printf "    %s\n" "$cmd"
            echo
        done
        
        print_color $BLUE "======================================================"
        echo "$((cmd_count + 1)). 查看所有日志"
        echo "0. 返回"
        echo
        read -p "请选择 [0-$((cmd_count + 1))]: " choice
        
        if [[ "$choice" == "0" ]]; then
            return
        elif [[ "$choice" == "$((cmd_count + 1))" ]]; then
            show_all_service_logs "$service_name"
        elif [[ "$choice" =~ ^[1-9][0-9]*$ ]] && [[ $choice -le $cmd_count ]]; then
            show_single_log "$service_name" "$choice"
        else
            print_color $RED "无效选择"
            sleep 2
        fi
    fi
}

# 显示单个命令的日志
show_single_log() {
    local service_name=$(clean_service_name "$1")
    local cmd_index="$2"
    local log_file="$LOG_DIR/${service_name}_${cmd_index}.log"
    
    clear
    print_color $BLUE "============ $service_name 命令 $cmd_index 日志 ============"
    echo "日志文件: $log_file"
    echo "文件大小: $(get_human_readable_size "$log_file")"
    print_color $BLUE "======================================================"
    
    if [[ -f "$log_file" ]]; then
        echo "最近50行日志:"
        echo
        tail -n 50 "$log_file"
        echo
        print_color $BLUE "======================================================"
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

# 显示所有服务日志 - 修复版本
show_all_service_logs() {
    local service_name=$(clean_service_name "$1")
    local commands
    commands=$(get_service_commands "$service_name")
    
    clear
    print_color $BLUE "============ $service_name 所有命令日志 ============"
    echo
    
    # 使用数组避免子shell问题
    local cmd_array=()
    while IFS= read -r line; do
        [[ -n "$line" ]] && cmd_array+=("$line")
    done <<< "$(echo "$commands" | tr '|' '\n')"
    
    for i in "${!cmd_array[@]}"; do
        local cmd_index=$((i + 1))
        local cmd="${cmd_array[i]}"
        local log_file="$LOG_DIR/${service_name}_${cmd_index}.log"
        
        print_color $CYAN "=== 命令 $cmd_index: $cmd ==="
        if [[ -f "$log_file" ]]; then
            tail -n 10 "$log_file"
        else
            print_color $YELLOW "日志文件不存在"
        fi
        echo
    done
    
    read -p "按回车键继续..."
}

# 删除服务菜单
delete_service_menu() {
    local service_name
    service_name=$(select_service "删除服务")
    
    if [[ $? -eq 0 && -n "$service_name" ]]; then
        echo
        if confirm_delete_service "$service_name"; then
            echo
            read -p "按回车键继续..."
        fi
    fi
}

# 删除服务
delete_service() {
    local service_name=$(clean_service_name "$1")
    
    stop_all_commands "$service_name"
    
    if [[ -f "$CONFIG_FILE" ]]; then
        grep -v "^${service_name}=" "$CONFIG_FILE" > "${CONFIG_FILE}.tmp" 2>/dev/null || true
        mv "${CONFIG_FILE}.tmp" "$CONFIG_FILE" 2>/dev/null || true
    fi
    
    rm -f "$PID_DIR/${service_name}_"*.pid
    
    read -p "是否同时删除所有日志文件? [y/N]: " delete_log
    if [[ "$delete_log" =~ ^[Yy] ]]; then
        rm -f "$LOG_DIR/${service_name}_"*.log
    fi
}

# 日志管理设置菜单
log_management_menu() {
    while true; do
        clear
        print_color $BLUE "====================== 日志管理设置 ======================"
        
        print_color $CYAN "当前设置:"
        printf "  日志大小限制: %s\n" "$LOG_MAX_SIZE"
        printf "  自动清理: %s\n" "$LOG_AUTO_CLEAN"
        printf "  备份数量: %s\n" "$LOG_BACKUP_COUNT"
        
        echo
        print_color $GREEN "1. 设置日志大小限制"
        print_color $GREEN "2. 启用/禁用自动清理"
        print_color $GREEN "3. 设置备份数量"
        print_color $GREEN "4. 手动清理所有日志"
        print_color $YELLOW "0. 返回主菜单"
        print_color $BLUE "======================================================"
        echo -n "请选择操作 [0-4]: "
        read choice
        
        case $choice in
            1) set_log_size_limit ;;
            2) toggle_auto_clean ;;
            3) set_backup_count ;;
            4) manual_clean_logs ;;
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

# 启动守护进程
start_daemon() {
    if is_daemon_running; then
        print_color $YELLOW "保活守护进程已经在运行"
        return 1
    fi
    
    print_color $BLUE "正在启动保活守护进程..."
    
    nohup bash -c "exec $0 --daemon" > /dev/null 2>&1 &
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

# 停止守护进程
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

# 守护进程主循环 - 修复版本
daemon_loop() {
    echo "$(date): 保活守护进程启动" >> "$LOG_DIR/daemon.log"
    
    while true; do
        load_settings
        
        if [[ -f "$CONFIG_FILE" ]]; then
            while IFS='=' read -r name commands; do
                if [[ -n "$name" ]]; then
                    local clean_name=$(clean_service_name "$name")
                    
                    # 使用数组避免子shell问题
                    local cmd_array=()
                    while IFS= read -r line; do
                        [[ -n "$line" ]] && cmd_array+=("$line")
                    done <<< "$(echo "$commands" | tr '|' '\n')"
                    
                    for i in "${!cmd_array[@]}"; do
                        local cmd_index=$((i + 1))
                        local cmd="${cmd_array[i]}"
                        
                        if ! is_command_running "$clean_name" "$cmd_index"; then
                            echo "$(date): 检测到服务 '$clean_name' 命令 $cmd_index 已停止，正在重启..." >> "$LOG_DIR/daemon.log"
                            start_command "$clean_name" "$cmd_index" "$cmd" >> "$LOG_DIR/daemon.log" 2>&1
                        else
                            local log_file="$LOG_DIR/${clean_name}_${cmd_index}.log"
                            check_and_clean_log "$log_file"
                        fi
                    done
                fi
            done < "$CONFIG_FILE"
        fi
        
        check_and_clean_log "$LOG_DIR/daemon.log"
        sleep 30
    done
}

# 设置开机自启
setup_autostart() {
    local script_path="$SCRIPT_DIR/$(basename "$0")"
    local service_file="/etc/systemd/system/service-keeper.service"
    
    print_color $BLUE "设置开机自启动..."
    
    if ! sudo -n true 2>/dev/null; then
        print_color $RED "需要sudo权限来设置开机自启"
        return 1
    fi
    
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

    sudo systemctl daemon-reload
    sudo systemctl enable service-keeper.service
    
    print_color $GREEN "✓ 开机自启动设置成功"
    print_color $CYAN "重启后将自动启动所有配置的服务和守护进程"
}

# 取消开机自启
remove_autostart() {
    print_color $BLUE "取消开机自启动..."
    
    if ! sudo -n true 2>/dev/null; then
        print_color $RED "需要sudo权限来取消开机自启"
        return 1
    fi
    
    sudo systemctl disable service-keeper.service 2>/dev/null || true
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
    
    while IFS='=' read -r name commands; do
        if [[ -n "$name" ]]; then
            local clean_name=$(clean_service_name "$name")
            echo "$(date): 启动服务 $clean_name" >> "$LOG_DIR/autostart.log"
            start_all_commands "$clean_name" >> "$LOG_DIR/autostart.log" 2>&1
            sleep 2
        fi
    done < "$CONFIG_FILE"
    
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
    --setup-shortcut)
        setup_shortcut
        exit 0
        ;;
    --help|-h)
        echo "Service Keeper - 服务保活管理器"
        echo "版本: 2.4 彻底修复版"
        echo "用法: $0 [选项]"
        echo ""
        echo "选项:"
        echo "  --autostart      开机自动启动所有服务"
        echo "  --daemon         运行守护进程"
        echo "  --start-daemon   启动守护进程"
        echo "  --stop-daemon    停止守护进程"
        echo "  --setup-shortcut 设置快捷键"
        echo "  --help, -h       显示此帮助信息"
        echo ""
        echo "功能特性:"
        echo "  • 多命令服务管理"
        echo "  • 自动日志轮转"
        echo "  • 保活守护进程"
        echo "  • 开机自启动"
        echo "  • 详细状态监控"
        echo "  • 动态服务管理"
        echo "  • 快捷键支持"
        echo "  • 服务名清理功能"
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
            manage_existing_service_menu
            ;;
        3) 
            start_service_menu
            ;;
        4)
            stop_service_menu
            ;;
        5)
            restart_service_menu
            ;;
        6) 
            show_status
            ;;
        7) 
            show_logs_menu
            ;;
        8) 
            delete_service_menu
            ;;
        9)
            echo
            start_daemon
            echo
            read -p "按回车键继续..."
            ;;
        10)
            echo
            stop_daemon
            echo
            read -p "按回车键继续..."
            ;;
        11)
            log_management_menu
            ;;
        12) 
            echo
            setup_autostart
            echo
            read -p "按回车键继续..."
            ;;
        13) 
            echo
            remove_autostart
            echo
            read -p "按回车键继续..."
            ;;
        14)
            echo
            setup_shortcut
            echo
            read -p "按回车键继续..."
            ;;
        0) 
            print_color $GREEN "感谢使用 Service Keeper!"
            print_color $CYAN "项目地址: https://github.com/DR-lin-eng/service_keeper"
            exit 0
            ;;
        *)
            print_color $RED "无效选择，请重试"
            sleep 1
            ;;
    esac
done
