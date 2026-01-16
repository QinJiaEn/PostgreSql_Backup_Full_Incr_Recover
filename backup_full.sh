#!/bin/bash

# ================= 配置区域 =================
DB_HOST="127.0.0.1"
DB_USER="postgres"
BACKUP_ROOT="/data/backups/full"
MAX_SIZE_MB=2048  # 2G 限制

# 日期格式 YYYYMMDD
TODAY=$(date +%Y%m%d)
TARGET_DIR="$BACKUP_ROOT/$TODAY"
LOG_FILE="/data/backups/backup_full.log"

# PG 工具路径 根据个人pg版本修改,我用的是15 脚本中都按15举例
PG_BASEBACKUP="/usr/pgsql-15/bin/pg_basebackup"

# ================= 1. 空间检查与清理 =================
check_clean() {
    CURRENT_SIZE=$(du -sm "$BACKUP_ROOT" | awk '{print $1}')
    echo "[$(date)] [检查] 全量目录大小: ${CURRENT_SIZE}MB" >> "$LOG_FILE"
    
    while [ "$CURRENT_SIZE" -gt "$MAX_SIZE_MB" ]; do
        # 找到最老的日期目录 (例如 20260113)
        OLDEST_DIR=$(ls -d "$BACKUP_ROOT"/*/ 2>/dev/null | sort | head -n 1)
        
        if [ -n "$OLDEST_DIR" ]; then
            echo "[$(date)] [清理] 容量超标，删除最旧全量备份: $OLDEST_DIR" >> "$LOG_FILE"
            rm -rf "$OLDEST_DIR"
            CURRENT_SIZE=$(du -sm "$BACKUP_ROOT" | awk '{print $1}')
        else
            break
        fi
    done
}

check_clean

# ================= 2. 执行物理全量备份 =================
echo "[$(date)] [开始] 执行全量备份 -> $TARGET_DIR" >> "$LOG_FILE"
mkdir -p "$TARGET_DIR"

# -F t: 输出为 tar 包 (节省空间)
# -z: gzip 压缩
# -D: 目标目录
if $PG_BASEBACKUP -h "$DB_HOST" -U "$DB_USER" -D "$TARGET_DIR" -F t -z; then
    echo "[$(date)] [成功] 全量备份完成" >> "$LOG_FILE"
    chown -R postgres:postgres "$TARGET_DIR"
else
    echo "[$(date)] [失败] 全量备份出错" >> "$LOG_FILE"
    # 失败则删除空目录
    rm -rf "$TARGET_DIR"
    exit 1
fi
