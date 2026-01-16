#!/bin/bash
# 保存为 /data/scripts/incr_10min.sh

DB_HOST="127.0.0.1"
DB_USER="postgres"
BUFFER_DIR="/data/backups/wal_buffer"
INCR_ROOT="/data/backups/incr"
MAX_SIZE_MB=2048 # 2G 限制

# 今天的增量目录
TODAY=$(date +%Y%m%d)
TARGET_DIR="$INCR_ROOT/$TODAY"
mkdir -p "$TARGET_DIR"

# 1. 强制切换 WAL (让数据库把这段时间的的日志吐出来) 你可以使用 linux的crontab 来添加自定义时间的任务来实现 隔段时间自动执行增量任务
/usr/pgsql-15/bin/psql -h "$DB_HOST" -U "$DB_USER" -d tax  -c "SELECT pg_switch_wal();" >/dev/null 2>&1

# 等待一秒让 archive_command 执行完成
sleep 1

# 2. 搬运 WAL 文件
# 把 buffer 里的文件移动到今天的目录里
if [ "$(ls -A $BUFFER_DIR)" ]; then
    mv "$BUFFER_DIR"/* "$TARGET_DIR"/ 
    echo "已归档 WAL 到 $TARGET_DIR"
    chown -R postgres:postgres "$TARGET_DIR"  # 新增核心行：修复当前增量目录的权限！
fi

# 3. 空间检查 (针对 incr 目录)
CURRENT_SIZE=$(du -sm "$INCR_ROOT" | awk '{print $1}')

while [ "$CURRENT_SIZE" -gt "$MAX_SIZE_MB" ]; do
    # 找最老的一个日期目录
    OLDEST=$(ls -d "$INCR_ROOT"/*/ 2>/dev/null | sort | head -n 1)
    if [ -z "$OLDEST" ]; then break; fi
    
    echo "增量目录空间不足 (${CURRENT_SIZE}MB)，删除最旧日期目录: $OLDEST"
    rm -rf "$OLDEST"
    
    CURRENT_SIZE=$(du -sm "$INCR_ROOT" | awk '{print $1}')
done
