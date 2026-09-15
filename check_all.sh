#!/bin/bash
# ============================================================
#  Linux 系统自动化巡检脚本集（CentOS / RHEL 版）
#  作者：杨淞淇
#  功能：磁盘/内存/CPU/服务/端口/日志 一键巡检 + 告警 + 报告生成
#  兼容：CentOS 7 / 8、RHEL 7+、Rocky / AlmaLinux
#        （脚本内含发行版判断，也可在 Ubuntu 上运行）
# ============================================================

# ============ 配置区（可按需修改）============
REPORT_DIR="/var/log/ops-check"
REPORT_FILE="${REPORT_DIR}/report_$(date +%Y%m%d_%H%M%S).txt"

# 告警阈值
DISK_THRESHOLD=85          # 磁盘使用率告警阈值（%）
MEM_THRESHOLD=85           # 内存使用率告警阈值（%）
LOAD_THRESHOLD=4.0         # 系统负载告警阈值

# 需要监控的关键服务（CentOS 常见服务名）
SERVICES=("sshd" "crond" "firewalld" "nginx" "mysqld")

# 需要监控的日志文件（脚本会自动跳过不存在的）
LOG_FILES=(
    "/var/log/messages"    # CentOS 系统日志
    "/var/log/secure"      # CentOS 安全日志（登录、sudo）
)

# ============ 强制英文输出（避免中文 locale 导致 df 表头解析失败）============
export LC_ALL=C
export LANG=C

# ============ 颜色输出 ============
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# ============ 全局计数 ============
ALERT_COUNT=0
OK_COUNT=0
SKIP_COUNT=0

# ============ 工具函数 ============

init_report() {
    if [ ! -d "$REPORT_DIR" ]; then
        sudo mkdir -p "$REPORT_DIR" 2>/dev/null || mkdir -p "$REPORT_DIR"
    fi
    # 确保当前用户有写权限
    sudo chmod 755 "$REPORT_DIR" 2>/dev/null
}

log_line() {
    echo -e "$1" | tee -a "$REPORT_FILE"
}

ok_item() {
    OK_COUNT=$((OK_COUNT + 1))
    log_line "  ${GREEN}[正常]${NC} $1"
}

alert_item() {
    ALERT_COUNT=$((ALERT_COUNT + 1))
    log_line "  ${RED}[告警]${NC} $1"
}

skip_item() {
    SKIP_COUNT=$((SKIP_COUNT + 1))
    log_line "  ${YELLOW}[跳过]${NC} $1"
}

divider() {
    log_line "------------------------------------------------------------"
}

# 获取发行版信息
get_os_info() {
    if [ -f /etc/redhat-release ]; then
        cat /etc/redhat-release
    elif [ -f /etc/os-release ]; then
        grep PRETTY_NAME /etc/os-release | cut -d'"' -f2
    else
        echo "未知系统"
    fi
}

# ============ 巡检项 1：系统基础信息 ============
check_system_info() {
    log_line ""
    log_line "${BLUE}【1】系统基础信息${NC}"
    divider
    log_line "  主机名    : $(hostname)"
    log_line "  系统版本  : $(get_os_info)"
    log_line "  内核版本  : $(uname -r)"
    log_line "  运行时间  : $(uptime -p 2>/dev/null || uptime)"
    log_line "  当前时间  : $(date '+%Y-%m-%d %H:%M:%S')"
    log_line "  登录用户  : $(whoami)"
    log_line "  系统架构  : $(uname -m)"
}

# ============ 巡检项 2：磁盘使用率 ============
check_disk() {
    log_line ""
    log_line "${BLUE}【2】磁盘使用率巡检（阈值 ${DISK_THRESHOLD}%）${NC}"
    divider

    local alert_tmp="/tmp/ops_check_disk_alert"
    rm -f "$alert_tmp"

    # 跳过表头、虚拟文件系统、以及临时/可移动挂载点
    df -hP \
      | grep -vE '^Filesystem|^文件系统|tmpfs|devtmpfs|overlay|squashfs' \
      | grep -vE ' /(run|media|mnt|proc|sys|dev)(/|$)' \
      | while read -r line; do
        local usage mount_point
        usage=$(echo "$line" | awk '{print $5}' | tr -d '%')
        mount_point=$(echo "$line" | awk '{print $6}')

        # 只处理纯数字的使用率，过滤表头和异常行
        case "$usage" in
            ''|*[!0-9]*) continue ;;
        esac
        [ -z "$mount_point" ] && continue

        if [ "$usage" -ge "$DISK_THRESHOLD" ]; then
            echo -e "  ${RED}[告警]${NC} 挂载点 ${mount_point} 使用率 ${usage}%（超过阈值 ${DISK_THRESHOLD}%）" | tee -a "$REPORT_FILE"
            echo "1" >> "$alert_tmp"
        else
            echo -e "  ${GREEN}[正常]${NC} 挂载点 ${mount_point} 使用率 ${usage}%" | tee -a "$REPORT_FILE"
        fi
    done

    # 统计告警数（由于用了管道子shell，需通过临时文件回传）
    if [ -f "$alert_tmp" ]; then
        local cnt
        cnt=$(wc -l < "$alert_tmp")
        ALERT_COUNT=$((ALERT_COUNT + cnt))
        rm -f "$alert_tmp"
    fi

    # 额外：inode 使用率检查（容易被忽略但会导致无法创建新文件）
    log_line ""
    log_line "  ${BLUE}-- inode 使用率 --${NC}"
    df -iP \
      | grep -vE '^Filesystem|^文件系统|tmpfs|devtmpfs|overlay' \
      | grep -vE ' /(run|media|mnt|proc|sys|dev)(/|$)' \
      | while read -r line; do
        local iuse imnt
        iuse=$(echo "$line" | awk '{print $5}' | tr -d '%')
        imnt=$(echo "$line" | awk '{print $6}')
        case "$iuse" in
            ''|*[!0-9]*) continue ;;
        esac
        [ -z "$imnt" ] && continue
        if [ "$iuse" -ge 90 ]; then
            echo -e "  ${RED}[告警]${NC} ${imnt} inode 使用率 ${iuse}%" | tee -a "$REPORT_FILE"
        else
            echo -e "  ${GREEN}[正常]${NC} ${imnt} inode 使用率 ${iuse}%" | tee -a "$REPORT_FILE"
        fi
    done
}

# ============ 巡检项 3：内存使用率 ============
check_memory() {
    log_line ""
    log_line "${BLUE}【3】内存使用率巡检（阈值 ${MEM_THRESHOLD}%）${NC}"
    divider

    local total used percent
    total=$(free -m | awk '/^Mem:/{print $2}')
    used=$(free -m | awk '/^Mem:/{print $3}')
    percent=$((used * 100 / total))

    log_line "  总内存    : ${total} MB"
    log_line "  已使用    : ${used} MB"
    log_line "  可用      : $(free -m | awk '/^Mem:/{print $7}') MB"

    if [ "$percent" -ge "$MEM_THRESHOLD" ]; then
        alert_item "内存使用率 ${percent}%（超过阈值 ${MEM_THRESHOLD}%）"
    else
        ok_item "内存使用率 ${percent}%"
    fi

    # 额外：Swap 使用情况
    local swap_total swap_used
    swap_total=$(free -m | awk '/^Swap:/{print $2}')
    swap_used=$(free -m | awk '/^Swap:/{print $3}')
    if [ "$swap_total" -gt 0 ]; then
        log_line "  Swap      : ${swap_used} MB / ${swap_total} MB"
    fi
}

# ============ 巡检项 4：系统负载 ============
check_load() {
    log_line ""
    log_line "${BLUE}【4】系统负载巡检（阈值 ${LOAD_THRESHOLD}）${NC}"
    divider

    local load1 load5 load15 cpu_cores
    load1=$(uptime | awk -F'load average:' '{print $2}' | awk -F',' '{print $1}' | tr -d ' ')
    load5=$(uptime | awk -F'load average:' '{print $2}' | awk -F',' '{print $2}' | tr -d ' ')
    load15=$(uptime | awk -F'load average:' '{print $2}' | awk -F',' '{print $3}' | tr -d ' ')
    cpu_cores=$(nproc 2>/dev/null || grep -c ^processor /proc/cpuinfo)

    log_line "  CPU 核心数: ${cpu_cores}"
    log_line "  1 分钟负载: ${load1}"
    log_line "  5 分钟负载: ${load5}"
    log_line "  15 分钟负载: ${load15}"

    if awk "BEGIN{exit !($load1 >= $LOAD_THRESHOLD)}"; then
        alert_item "系统 1 分钟负载 ${load1}（超过阈值 ${LOAD_THRESHOLD}）"
    else
        ok_item "系统负载正常（${load1} / 核心数 ${cpu_cores}）"
    fi
}

# ============ 巡检项 5：关键服务状态 ============
check_services() {
    log_line ""
    log_line "${BLUE}【5】关键服务状态巡检${NC}"
    divider

    for svc in "${SERVICES[@]}"; do
        if systemctl list-unit-files 2>/dev/null | grep -q "^${svc}.service"; then
            if systemctl is-active --quiet "$svc" 2>/dev/null; then
                ok_item "服务 ${svc} 运行中"
            else
                alert_item "服务 ${svc} 未运行"
            fi
        else
            skip_item "服务 ${svc} 未安装"
        fi
    done

    # 额外：CentOS 专属 —— SELinux 状态
    log_line ""
    log_line "  ${BLUE}-- SELinux 状态（CentOS 安全机制）--${NC}"
    if command -v getenforce >/dev/null 2>&1; then
        local se
        se=$(getenforce 2>/dev/null)
        if [ "$se" = "Enforcing" ]; then
            ok_item "SELinux 已启用（Enforcing）"
        else
            log_line "  ${YELLOW}[注意]${NC} SELinux 当前状态：${se}（生产环境建议 Enforcing）"
        fi
    else
        skip_item "未安装 SELinux 工具"
    fi

    # 额外：CentOS 专属 —— 防火墙状态
    log_line ""
    log_line "  ${BLUE}-- 防火墙状态 --${NC}"
    if systemctl list-unit-files 2>/dev/null | grep -q "^firewalld.service"; then
        if systemctl is-active --quiet firewalld 2>/dev/null; then
            ok_item "firewalld 运行中"
            log_line "     当前开放端口: $(firewall-cmd --list-ports 2>/dev/null | tr '\n' ' ')"
        else
            alert_item "firewalld 未运行"
        fi
    else
        skip_item "未安装 firewalld"
    fi
}

# ============ 巡检项 6：端口监听情况 ============
check_ports() {
    log_line ""
    log_line "${BLUE}【6】关键端口监听情况${NC}"
    divider

    local ports=(22 80 443 3306 6379)
    local port_names=("SSH" "HTTP" "HTTPS" "MySQL" "Redis")

    # CentOS 7 默认有 netstat（net-tools），CentOS 8+ 用 ss
    local cmd=""
    command -v netstat >/dev/null 2>&1 && cmd="netstat -tlnp"
    [ -z "$cmd" ] && command -v ss >/dev/null 2>&1 && cmd="ss -tlnp"

    if [ -z "$cmd" ]; then
        skip_item "netstat 和 ss 均不可用，无法检查端口"
        return
    fi

    for i in "${!ports[@]}"; do
        local p="${ports[$i]}"
        local n="${port_names[$i]}"
        if $cmd 2>/dev/null | grep -q ":${p} "; then
            ok_item "端口 ${p} (${n}) 正在监听"
        else
            log_line "  ${YELLOW}[未启用]${NC} 端口 ${p} (${n}) 未监听"
        fi
    done
}

# ============ 巡检项 7：日志错误扫描 ============
check_logs() {
    log_line ""
    log_line "${BLUE}【7】日志错误扫描${NC}"
    divider

    for logfile in "${LOG_FILES[@]}"; do
        if [ -f "$logfile" ]; then
            local err_cnt last_err
            # 收紧匹配：只匹配明确的错误特征，排除 sudo 审计等含 error 字样的正常记录
            local err_cnt last_err
            err_cnt=$(sudo tail -200 "$logfile" 2>/dev/null \
                      | grep -iE 'error:|critical:|emergency:|alert:|segfault|out of memory|authentication failure|Failed password|Connection refused|Permission denied' \
                      | grep -vcE 'sudo:|session opened|session closed')
            # 兜底：确保是纯数字
            case "$err_cnt" in
                ''|*[!0-9]*) err_cnt=0 ;;
            esac

            if [ "$err_cnt" -gt 0 ]; then
                alert_item "日志 ${logfile} 最近 200 行中发现 ${err_cnt} 条异常记录"
                last_err=$(sudo grep -iE 'error:|critical:|segfault|authentication failure|Failed password' "$logfile" 2>/dev/null \
                           | grep -vE 'sudo:' | tail -1 | cut -c1-80)
                [ -n "$last_err" ] && log_line "     最近一条: ${last_err}"
            else
                ok_item "日志 ${logfile} 未发现异常"
            fi
        else
            skip_item "日志文件 ${logfile} 不存在"
        fi
    done
}

# ============ 巡检项 8：CPU / 内存 占用 TOP5 ============
check_top_process() {
    log_line ""
    log_line "${BLUE}【8】资源占用 TOP5 进程${NC}"
    divider

    log_line "  ${BLUE}-- CPU 占用 TOP5 --${NC}"
    ps aux --sort=-%cpu 2>/dev/null | head -6 | awk 'NR==1{printf "    %-10s %-6s %-6s %s\n","USER","CPU%","MEM%","COMMAND"} NR>1{printf "    %-10s %-6s %-6s %s\n",$1,$3,$4,$11}'

    log_line ""
    log_line "  ${BLUE}-- 内存占用 TOP5 --${NC}"
    ps aux --sort=-%mem 2>/dev/null | head -6 | awk 'NR==1{printf "    %-10s %-6s %-6s %s\n","USER","CPU%","MEM%","COMMAND"} NR>1{printf "    %-10s %-6s %-6s %s\n",$1,$3,$4,$11}'
}

# ============ 巡检项 9：登录失败记录（安全）============
check_login_fail() {
    log_line ""
    log_line "${BLUE}【9】登录失败记录检查（最近 20 条）${NC}"
    divider

    if [ -f /var/log/secure ]; then
        local fail_cnt
        fail_cnt=$(sudo grep -c "Failed password" /var/log/secure 2>/dev/null || echo 0)
        if [ "$fail_cnt" -gt 10 ]; then
            alert_item "检测到 ${fail_cnt} 次登录失败，可能存在暴力破解尝试"
            log_line "     最近记录:"
            sudo grep "Failed password" /var/log/secure 2>/dev/null | tail -3 | while read -r l; do
                log_line "       $(echo "$l" | cut -c1-90)"
            done
        else
            ok_item "登录失败次数正常（${fail_cnt} 次）"
        fi
    else
        skip_item "日志 /var/log/secure 不存在"
    fi
}

# ============ 生成总结 ============
print_summary() {
    log_line ""
    log_line "${BLUE}【巡检总结】${NC}"
    divider
    log_line "  正常项 : ${OK_COUNT}"
    log_line "  告警项 : ${ALERT_COUNT}"
    log_line "  跳过项 : ${SKIP_COUNT}"
    log_line "  报告文件: ${REPORT_FILE}"

    if [ "$ALERT_COUNT" -gt 0 ]; then
        log_line ""
        log_line "  ${RED}>>> 发现 ${ALERT_COUNT} 项异常，请及时处理 <<<${NC}"
    else
        log_line ""
        log_line "  ${GREEN}>>> 系统状态良好，无异常项 <<<${NC}"
    fi
    divider
}

# ============ 主流程 ============
main() {
    init_report

    log_line "============================================================"
    log_line "         Linux 系统自动化巡检报告"
    log_line "============================================================"
    log_line "  巡检时间: $(date '+%Y-%m-%d %H:%M:%S')"

    check_system_info
    check_disk
    check_memory
    check_load
    check_services
    check_ports
    check_logs
    check_top_process
    check_login_fail
    print_summary

    echo ""
    echo "巡检完成，报告已保存至: ${REPORT_FILE}"
}

main "$@"
