#!/bin/bash
# ============================================================
#  环境检查脚本 —— 运行前确认必备工具是否齐全
#  用法：bash env_check.sh
# ============================================================

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'

echo ""
echo "============================================================"
echo "          环境检查"
echo "============================================================"

# ---- 1. 系统信息 ----
echo ""
echo -e "${BLUE}【1】系统信息${NC}"
echo "------------------------------------------------------------"
echo "  系统版本  : $(cat /etc/redhat-release 2>/dev/null || echo 未知)"
echo "  内核版本  : $(uname -r)"
echo "  主机名    : $(hostname)"
echo "  CPU 核心  : $(nproc 2>/dev/null || grep -c ^processor /proc/cpuinfo)"
echo "  内存      : $(free -h | awk '/^Mem:/{print $2}')"

# ---- 2. 网络连通性 ----
echo ""
echo -e "${BLUE}【2】网络连通性${NC}"
echo "------------------------------------------------------------"
if ping -c 2 -W 2 www.baidu.com >/dev/null 2>&1; then
    echo -e "  ${GREEN}[正常]${NC} 可以上网"
else
    echo -e "  ${RED}[异常]${NC} 无法上网，请检查网络配置"
fi

# ---- 3. yum 源是否可用 ----
echo ""
echo -e "${BLUE}【3】yum 源状态${NC}"
echo "------------------------------------------------------------"
if yum repolist 2>/dev/null | grep -q "repolist:"; then
    REPO_CNT=$(yum repolist 2>/dev/null | awk '/repolist:/{print $2}')
    echo -e "  ${GREEN}[正常]${NC} 可用软件源数量: ${REPO_CNT}"
    yum repolist 2>/dev/null | tail -n +2 | head -5 | sed 's/^/    /'
else
    echo -e "  ${RED}[异常]${NC} yum 源不可用，请先换源"
fi

# ---- 4. 必备工具检查 ----
echo ""
echo -e "${BLUE}【4】必备工具${NC}"
echo "------------------------------------------------------------"

check_tool() {
    local tool="$1"
    local pkg="$2"
    if command -v "$tool" >/dev/null 2>&1; then
        echo -e "  ${GREEN}[已安装]${NC} ${tool}  ->  $(command -v $tool)"
    else
        echo -e "  ${YELLOW}[缺失]${NC}   ${tool}  ->  安装命令: yum install -y ${pkg}"
    fi
}

check_tool "netstat"   "net-tools"
check_tool "ss"        "iproute"
check_tool "vim"       "vim"
check_tool "wget"      "wget"
check_tool "curl"      "curl"
check_tool "awk"       "gawk"
check_tool "sed"       "sed"
check_tool "grep"      "grep"
check_tool "find"      "findutils"
check_tool "ps"        "procps-ng"
check_tool "df"        "coreutils"
check_tool "free"      "procps-ng"
check_tool "uptime"    "procps-ng"
check_tool "systemctl" "systemd"
check_tool "crontab"   "cronie"
check_tool "getenforce" "libselinux-utils"

# ---- 5. 服务状态 ----
echo ""
echo -e "${BLUE}【5】关键服务状态${NC}"
echo "------------------------------------------------------------"
for svc in sshd crond firewalld; do
    if systemctl list-unit-files 2>/dev/null | grep -q "^${svc}.service"; then
        STATUS=$(systemctl is-active "$svc" 2>/dev/null)
        if [ "$STATUS" = "active" ]; then
            echo -e "  ${GREEN}[运行中]${NC} ${svc}"
        else
            echo -e "  ${YELLOW}[未运行]${NC} ${svc}  -> 启动: systemctl start ${svc}"
        fi
    else
        echo -e "  ${YELLOW}[未安装]${NC} ${svc}"
    fi
done

# ---- 6. SELinux ----
echo ""
echo -e "${BLUE}【6】SELinux 状态${NC}"
echo "------------------------------------------------------------"
if command -v getenforce >/dev/null 2>&1; then
    echo "  当前模式: $(getenforce)"
else
    echo -e "  ${YELLOW}[未安装]${NC} libselinux-utils"
fi

# ---- 7. 磁盘空间 ----
echo ""
echo -e "${BLUE}【7】磁盘空间${NC}"
echo "------------------------------------------------------------"
df -hP | grep -vE '^Filesystem|tmpfs|devtmpfs' | sed 's/^/  /'

# ---- 8. 结果汇总 ----
echo ""
echo "============================================================"
MISSING=0
for t in netstat vim wget curl crontab getenforce; do
    command -v "$t" >/dev/null 2>&1 || MISSING=$((MISSING + 1))
done

if [ "$MISSING" -eq 0 ]; then
    echo -e "  ${GREEN}✅ 环境检查通过，可以开始部署巡检脚本${NC}"
else
    echo -e "  ${YELLOW}⚠️  有 ${MISSING} 个工具缺失，建议先安装：${NC}"
    echo "     yum install -y net-tools vim wget curl cronie libselinux-utils"
fi
echo "============================================================"
echo ""
