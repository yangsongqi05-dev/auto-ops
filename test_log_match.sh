#!/bin/bash
# ============================================================
#  日志匹配规则测试
#  验证：能识别真正的错误，排除 sudo 审计等正常记录
# ============================================================

# 构造测试数据：混合正常记录、sudo审计记录、真实错误
cat > /tmp/test_secure.log << 'EOF'
Sep 15 16:43:29 localhost sudo:    root : TTY=pts/1 ; PWD=/root/auto-ops ; USER=root ; COMMAND=/usr/bin/ls /root
Sep 15 16:43:30 localhost sshd[1234]: Accepted password for root from 192.168.110.1 port 5000 ssh2
Sep 15 16:43:31 localhost sudo:    ysq : TTY=pts/0 ; PWD=/home/ysq ; USER=root ; COMMAND=/usr/bin/error_check
Sep 15 16:43:32 localhost sshd[1235]: Failed password for invalid user admin from 192.168.1.100 port 4000 ssh2
Sep 15 16:43:33 localhost sshd[1236]: Failed password for root from 192.168.1.101 port 4001 ssh2
Sep 15 16:43:34 localhost kernel: nginx: error: unexpected end of file
Sep 15 16:43:35 localhost sudo: session opened for user root by ysq(uid=1000)
Sep 15 16:43:36 localhost sshd[1237]: Connection refused by 10.0.0.1
Sep 15 16:43:37 localhost su: Authentication failure for root
Sep 15 16:43:38 localhost sudo:    root : COMMAND=/usr/bin/error_test --verbose
EOF

echo ""
echo "============================================================"
echo "  日志匹配规则测试"
echo "============================================================"
echo ""
echo "【测试数据】共 10 行，其中："
echo "  - sudo 审计记录（应排除）：4 行"
echo "  - 正常登录/会话记录（应排除）：1 行"
echo "  - 真实错误（应识别）：5 行"
echo ""

# ---- 旧规则（有问题的）----
echo "------------------------------------------------------------"
echo "【旧规则】匹配结果"
echo "------------------------------------------------------------"
old_cnt=$(cat /tmp/test_secure.log | grep -icE 'error|fail|denied|refused|critical')
echo "  匹配到 ${old_cnt} 行（含误报）"
echo "  具体内容："
cat /tmp/test_secure.log | grep -inE 'error|fail|denied|refused|critical' | sed 's/^/    /'
echo ""

# ---- 新规则 ----
echo "------------------------------------------------------------"
echo "【新规则】匹配结果"
echo "------------------------------------------------------------"
new_cnt=$(cat /tmp/test_secure.log \
          | grep -iE 'error:|critical:|emergency:|alert:|segfault|out of memory|authentication failure|Failed password|Connection refused|Permission denied' \
          | grep -vcE 'sudo:|session opened|session closed')
case "$new_cnt" in ''|*[!0-9]*) new_cnt=0 ;; esac
echo "  匹配到 ${new_cnt} 行"
echo "  具体内容："
cat /tmp/test_secure.log \
  | grep -inE 'error:|critical:|emergency:|alert:|segfault|out of memory|authentication failure|Failed password|Connection refused|Permission denied' \
  | grep -vE 'sudo:' | sed 's/^/    /'
echo ""

echo "------------------------------------------------------------"
echo "【结论】"
echo "------------------------------------------------------------"
echo "  旧规则误报数：$((old_cnt - new_cnt)) 条"
echo "  新规则准确率：识别出 ${new_cnt} 条真实错误"
echo ""

# 清理
rm -f /tmp/test_secure.log
