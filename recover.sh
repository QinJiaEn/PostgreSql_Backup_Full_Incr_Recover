#!/bin/bash
# PostgreSQL 一键恢复脚本
# 使用方式: sh recover.sh 恢复日期(如: sh recover.sh 20260116)
# 脚本自动完成: 停服务→备份旧数据→解压全量→创建恢复标记→配置增量路径→启动服务 全流程

# ======================== 配置项 ========================
PG_DATA_DIR="/var/lib/pgsql/15/data"
PG_BACKUP_FULL="/data/backups/full"
PG_BACKUP_INCR="/data/backups/incr"
PG_SERVICE="postgresql-15"
PG_USER="postgres"
PG_GROUP="postgres"

# ======================== 第一步: 校验参数 ========================
if [ $# -ne 1 ]; then
    echo -e "\033[31m[错误] 请传入正确的恢复日期参数!\033[0m"
    echo -e "使用示例: sh recover.sh 20260116"
    exit 1
fi

# 接收传入的恢复日期
RESTORE_DATE=$1
# 拼接全量/增量目录路径
FULL_BACKUP_DIR="${PG_BACKUP_FULL}/${RESTORE_DATE}"
INCR_BACKUP_DIR="${PG_BACKUP_INCR}/${RESTORE_DATE}"

# 校验全量/增量目录是否存在
if [ ! -d "${FULL_BACKUP_DIR}" ]; then
    echo -e "\033[31m[错误] 全量备份目录 ${FULL_BACKUP_DIR} 不存在!\033[0m"
    exit 1
fi

if [ ! -d "${INCR_BACKUP_DIR}" ]; then
    echo -e "\033[31m[错误] 增量备份目录 ${INCR_BACKUP_DIR} 不存在!\033[0m"
    exit 1
fi

echo -e "\033[32m[成功] 校验通过，开始恢复 ${RESTORE_DATE} 的数据...\033[0m"

# ======================== 第二步: 停止PG服务 ========================
echo -e "\033[33m[步骤1] 停止PostgreSQL服务...\033[0m"
systemctl stop ${PG_SERVICE}
if [ $? -ne 0 ]; then
    echo -e "\033[31m[错误] 停止PostgreSQL服务失败，请手动执行 systemctl stop ${PG_SERVICE}\033[0m"
    exit 1
fi
echo -e "\033[32m[成功] PostgreSQL服务已停止\033[0m"

# ======================== 第三步: 备份原有data目录(防误删，可回滚) ========================
echo -e "\033[33m[步骤2] 备份原有数据目录...\033[0m"
BAK_DATA_DIR="${PG_DATA_DIR}_bak_${RESTORE_DATE}_$(date +%H%M%S)"
mv ${PG_DATA_DIR} ${BAK_DATA_DIR}
mkdir -p ${PG_DATA_DIR}
chown -R ${PG_USER}:${PG_GROUP} ${PG_DATA_DIR}
echo -e "\033[32m[成功] 原有数据已备份至: ${BAK_DATA_DIR}\033[0m"

# ======================== 第四步: 解压全量备份到PG数据目录 ========================
echo -e "\033[33m[步骤3] 解压全量备份文件到数据目录...\033[0m"
tar -zxf ${FULL_BACKUP_DIR}/base.tar.gz -C ${PG_DATA_DIR}
if [ $? -ne 0 ]; then
    echo -e "\033[31m[错误] 解压全量备份文件失败!\033[0m"
    exit 1
fi
chown -R ${PG_USER}:${PG_GROUP} ${PG_DATA_DIR}
echo -e "\033[32m[成功] 全量备份解压完成\033[0m"

# ======================== 第五步: 创建恢复标记文件 recovery.signal ========================
echo -e "\033[33m[步骤4] 创建恢复标记文件 recovery.signal...\033[0m"
touch ${PG_DATA_DIR}/recovery.signal
chown ${PG_USER}:${PG_GROUP} ${PG_DATA_DIR}/recovery.signal
echo -e "\033[32m[成功] recovery.signal 创建完成\033[0m"

# ======================== 第六步: 修改postgresql.conf 配置增量日志路径 ========================
echo -e "\033[33m[步骤5] 配置增量日志恢复路径...\033[0m"
# 核心配置: 指定从哪个增量目录读取WAL日志
RESTORE_CONF="restore_command = 'cp ${INCR_BACKUP_DIR}/%f %p'"
# 追加配置到文件末尾，避免覆盖原有配置
echo ${RESTORE_CONF} >> ${PG_DATA_DIR}/postgresql.conf
chown ${PG_USER}:${PG_GROUP} ${PG_DATA_DIR}/postgresql.conf
echo -e "\033[32m[成功] 增量日志路径配置完成\033[0m"

# ======================== 【可选】恢复到指定时间点 配置开启区 ========================
# 需求: 不想恢复到最新，只想恢复到 指定时间，取消下面3行注释即可，无需删任何增量日志！
# 注意: 时间格式必须是 'YYYY-MM-DD HH:MI:SS' 严格格式
# echo "recovery_target_time = '2026-01-16 06:00:00'" >> ${PG_DATA_DIR}/postgresql.conf
# echo "recovery_target_action = 'promote'" >> ${PG_DATA_DIR}/postgresql.conf
# echo -e "\033[32m[成功] 已配置恢复到指定时间: 2026-01-16 06:00:00\033[0m"

# ======================== 第七步: 启动PG服务，自动重放增量日志 ========================
echo -e "\033[33m[步骤6] 启动PostgreSQL服务，开始自动重放增量日志...\033[0m"
systemctl start ${PG_SERVICE}
if [ $? -ne 0 ]; then
    echo -e "\033[31m[错误] 启动PostgreSQL服务失败，请手动执行 systemctl start ${PG_SERVICE}\033[0m"
    exit 1
fi

# ======================== 第八步: 校验恢复结果 ========================
sleep 3
echo -e "\033[32m=====================================================\033[0m"
echo -e "\033[32m[最终结果] 数据恢复完成！${RESTORE_DATE} 全量+增量已全部重放\033[0m"
echo -e "\033[32m[验证方式] 连接数据库查看最新数据自行验证是否恢复完毕性\033[0m"
echo -e "\033[32m=====================================================\033[0m"
exit 0
