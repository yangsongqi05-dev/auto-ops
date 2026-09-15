#!/bin/bash
# ============================================================
#  日志自动清理脚本（CentOS / RHEL 版）
#  功能：按保留天数清理指定目录下的历史日志，支持 dry-run 预演
#  作者：杨淞淇
#  兼容：CentOS 7 / 8、RHEL 7+、Rocky / AlmaLinux
# ============================================================

# ============ 配置区 ============
KEEP_DAYS=7                         # 保留最近 N 天的日志
LOG_DIRS=(                          # 需要清理的日志目录
    "/var/log"
    "/var/log/nginx"
    "/tmp/logs"
)
# 只清理匹配这些后缀的文件
LOG_PATTERNS=("*.log" "*.log.*" "*.gz" "*.old" "*.1" "*.2")
# 清理记录
CLEAN_LOG="/var/log/ops-check/clean_$(date +%Y%m%d).log"
DRY_RUN=false                       # true = 只显示不删除

# 需要保护、绝不清理的文件（白名单）
PROTECTED=(
    "messages"
    "secure"
    "cron"
    "maillog"
    "boot.log"
    "yum.log"
    "wtmp"
    "btmp"
    "lastlog"
)

# ============ 参数解析 ============
while getopts "d:n:h" opt; do
    case $opt in
        d) LOG_DIRS=("$OPTARG") ;;
        n) KEEP_DAYS="$OPTARG" ;;
        h) DRY_RUN=true ;;
        *) echo "用法: $0 [-d 日志目录] [-n 保留天数] [-h 预演模式]"; exit 1 ;;
    esac
done

# ============ 颜色 ============
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'

# ============ 初始化 ============
init() {
    local dir
    dir=$(dirname "$CLEAN_LOG")
    [ ! -d "$dir" ] && { sudo mkdir -p "$dir" 2>/dev/null || mkdir -p "$dir"; }
}

log_msg() {
    echo -e "$1" | tee -a "$CLEAN_LOG"
}

# 检查文件是否在白名单中
is_protected() {
    local fname
    fname=$(basename "$1")
    # 去掉压缩后缀再比对
    fname=$(echo "$fname" | sed -E 's/\.(gz|old|[0-9]+)$//')
    for p in "${PROTECTED[@]}"; do
        [ "$fname" = "$p" ] && return 0
    done
    return 1
}

# ============ 清理函数 ============
clean_dir() {
    local target_dir="$1"

    if [ ! -d "$target_dir" ]; then
        log_msg "  ${YELLOW}[跳过]${NC} 目录不存在: ${target_dir}"
        return
    fi

    log_msg ""
    log_msg "  扫描目录: ${target_dir}"

    local total=0
    local freed=0
    local skipped=0

    for pattern in "${LOG_PATTERNS[@]}"; do
        while IFS= read -r -d '' file; do
            # 白名单保护
            if is_protected "$file"; then
                skipped=$((skipped + 1))
                continue
            fi

            local size
            size=$(du -k "$file" 2>/dev/null | cut -f1)
            [ -z "$size" ] && size=0

            if [ "$DRY_RUN" = true ]; then
                log_msg "  ${YELLOW}[预演]${NC} 将删除: ${file} (${size} KB)"
            else
                if sudo rm -f "$file" 2>/dev/null || rm -f "$file" 2>/dev/null; then
                    log_msg "  ${GREEN}[已删除]${NC} ${file} (${size} KB)"
                    freed=$((freed + size))
                else
                    log_msg "  ${RED}[失败]${NC} 无法删除: ${file}"
                fi
            fi
            total=$((total + 1))
        done < <(find "$target_dir" -maxdepth 1 -type f -name "$pattern" -mtime +"$KEEP_DAYS" -print0 2>/dev/null)
    done

    log_msg "  小计: 处理 ${total} 个文件，保护 ${skipped} 个关键日志"
    [ "$DRY_RUN" = false ] && [ "$freed" -gt 0 ] && log_msg "  释放空间: $((freed / 1024)) MB"
}

# ============ 主流程 ============
main() {
    init

    log_msg "============================================================"
    log_msg "         日志自动清理"
    log_msg "============================================================"
    log_msg "  执行时间  : $(date '+%Y-%m-%d %H:%M:%S')"
    log_msg "  保留天数  : ${KEEP_DAYS} 天"
    log_msg "  执行模式  : $([ "$DRY_RUN" = true ] && echo '预演（不实际删除）' || echo '实际删除')"
    log_msg "  系统版本  : $(cat /etc/redhat-release 2>/dev/null || grep PRETTY_NAME /etc/os-release 2>/dev/null | cut -d'"' -f2)"
    log_msg "------------------------------------------------------------"

    # 清理前记录磁盘占用
    local before
    before=$(df -h / | awk 'NR==2{print $4}')
    log_msg "  清理前 / 剩余空间: ${before}"

    for d in "${LOG_DIRS[@]}"; do
        clean_dir "$d"
    done

    log_msg ""
    log_msg "------------------------------------------------------------"
    log_msg "  当前 /var/log 占用: $(sudo du -sh /var/log 2>/dev/null | cut -f1)"
    log_msg "  清理后 / 剩余空间: $(df -h / | awk 'NR==2{print $4" ("$5" 已用)"}')"
    log_msg "============================================================"

    echo ""
    echo "清理完成。日志记录: ${CLEAN_LOG}"
    [ "$DRY_RUN" = true ] && echo -e "${YELLOW}这是预演模式，文件未被删除。去掉 -h 参数可实际执行。${NC}"
}

main
