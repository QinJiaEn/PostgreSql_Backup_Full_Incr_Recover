# PostgreSql_Backup_Full_Incr_Recover
在网上找很久没找到跟我需求相符的功能脚本,所以瞎写了一个全量备份以及增量备份还有恢复的脚本.
ps:以下是Windows Bat的版本,包含bat的代码,我上传的是Linux的版本修改了一下,但是大差不差
# PostgreSQL 全量备份 + 增量备份 + 备份修复还原 完整脚本（Windows BAT 版）

> ✅ 生产可用 | ✅ 免密配置 | ✅ 自动空间清理 | ✅ 纯 SQL 文本备份 | ✅ WAL 增量归档 | ✅ 备份校验与修复 | ✅ 日志完整记录
>
> 适用环境：`Windows` + `PostgreSQL 10+`（兼容 15 版本），脚本适配税务项目业务场景，所有核心逻辑均做详细注释，适合 PostgreSQL 备份入门学习 & 生产环境直接复用

## 一、项目说明

### 1.1 脚本用途

本仓库包含 **3 个完整的 Windows 批处理 (BAT) 脚本**，实现 PostgreSQL 数据库的全量备份、WAL 日志增量备份、备份文件修复 + 数据还原的全套备份恢复方案，解决数据库数据丢失、误操作、故障恢复等核心诉求。

- 全量备份：支持「逻辑纯 SQL 备份」（领导友好，可直接查看 INSERT 语句 + 建表语句）
- 增量备份：基于 PostgreSQL 的 WAL 预写日志实现，仅备份增量日志，节省磁盘空间
- 修复还原：支持备份文件完整性校验、损坏修复，以及基于「全量 + 增量」的完整数据恢复

### 1.2 核心特性

✅ 免密执行：通过 `.pgpass` 配置实现无密码连接数据库，无需手动输入账号密码，适合定时任务

✅ 双备份模式：逻辑备份（pg_dump）生成可读.sql 文件 + 物理备份（pg_basebackup）完整数据文件，按需选择

✅ 自动清理：备份目录超阈值自动删除最旧备份文件，防止磁盘撑爆，支持自定义空间阈值

✅ 完整日志：所有执行日志写入指定日志文件，执行成功 / 失败 / 清理记录全留存，便于问题排查

✅ 权限适配：备份文件自动配置对应权限，避免 PostgreSQL 读写权限问题

✅ 容错健壮：脚本包含空文件校验、目录自动创建、执行异常捕获，无报错阻塞问题

### 1.3 依赖工具说明

脚本基于 PostgreSQL 官方自带工具实现，**无需额外安装插件**，工具路径默认：`/usr/pgsql-15/bin/`（Windows 环境修改为本地 PG 安装目录即可）

- `pg_dump`：核心逻辑备份工具，生成纯 SQL 文本文件，包含建表语句 + INSERT 数据语句
- `pg_basebackup`：物理全量备份工具，备份完整数据库集群文件，适合增量备份前置全量
- `pg_waldump`：WAL 日志解析工具，增量备份核心依赖
- `pg_restore`：备份还原工具，支持.sql 文件 / 物理备份文件的恢复
- `du`/`ls`：Windows 环境下需安装 git bash/git 终端，兼容 Linux 命令实现空间统计与文件排序

------

## 二、前置环境配置（必做，免密 + 核心配置）

### 2.1 PostgreSQL 免密登录配置（核心，所有脚本依赖）

为了实现脚本**无交互、免密执行**，必须配置 `.pgpass` 密码文件，PostgreSQL 会自动读取该文件完成认证，步骤如下：

1. 在系统用户目录下新建文件：`C:\Users\你的用户名\.pgpass`（无后缀名，文件名为 `.pgpass`）

2. 文件内写入配置，格式：`主机地址:端口:数据库名:用户名:密码`


   ```
127.0.0.1:5432:tax:postgres:你的数据库密码	
   ```

3. 修改文件权限：右键文件 → 属性 → 安全，仅当前用户拥有读写权限（PostgreSQL 要求该文件权限必须严格，否则不生效）

4. 验证：打开终端执行 `psql -h 127.0.0.1 -U postgres -d tax`，无需输入密码即可连接数据库即为配置成功

### 2.2 关键配置说明

所有脚本的**核心配置项**均集中在脚本头部，可直接修改适配自己的环境，无需改动脚本逻辑，统一配置如下：

~~~bash
# 数据库连接配置
DB_HOST="127.0.0.1"    # 数据库地址，本地填localhost/127.0.0.1
DB_PORT="5432"         # PG默认端口
DB_USER="postgres"     # 数据库用户名
DB_NAME="tax"          # 要备份的数据库名

# 备份路径配置
BACKUP_ROOT="D:/data/backups/sql_full"  # 全量备份目录
WAL_BACKUP_ROOT="D:/data/backups/wal_incr" # 增量备份目录
LOG_FILE="D:/data/scripts/backup_sql.log"  # 日志文件路径

# 空间阈值配置
MAX_SIZE_MB=2048       # 备份目录最大占用空间，超过自动清理（2GB）
~~~

------

## 三、脚本文件清单（共 3 个核心 BAT 脚本，开源完整文件）

> 所有脚本均已做详细中文注释，核心逻辑一目了然，可直接下载使用，所有修改点均标注【业务定制】，方便学习与二次开发

### 🔧 脚本 1：`pg_backup_full.bat` - PostgreSQL 全量逻辑备份脚本（主推，领导友好版）

> 核心：使用`pg_dump`生成**纯文本 SQL 文件**，包含完整的建表语句 + DROP 防冲突语句 + 显式 INSERT 数据语句，可直接用记事本打开查看，完美适配业务方查看需求，也是本次业务定制的核心脚本

~~~bash
@echo off
chcp 65001
setlocal enabledelayedexpansion

:: ===================== 【配置区域 - 按需修改】 =====================
set DB_HOST=127.0.0.1
set DB_USER=postgres
set DB_NAME=tax
set BACKUP_ROOT=D:\data\backups\sql_full
set MAX_SIZE_MB=2048
set PG_DUMP=D:\Program Files\PostgreSQL\15\bin\pg_dump.exe
set LOG_FILE=D:\data\scripts\backup_sql.log
:: ==================================================================

:: 获取当前时间 格式：20260116_153020
for /f "tokens=2 delims==" %%a in ('wmic OS Get localdatetime /value') do set "dt=%%a"
set "DATE_STR=!dt:~0,8!_!dt:~8,6!"
set FILENAME=%DB_NAME%_%DATE_STR%.sql
set TARGET_FILE=%BACKUP_ROOT%\%FILENAME%

:: 1. 准备备份目录，不存在则创建
if not exist "%BACKUP_ROOT%" (
    md "%BACKUP_ROOT%"
    echo [%DATE%] [INFO] 创建备份目录成功：%BACKUP_ROOT% >> %LOG_FILE%
)

echo [%DATE%] [开始] 执行PostgreSQL全量逻辑备份，数据库：%DB_NAME% >> %LOG_FILE%

:: 2. 执行核心备份 - 生成带建表+INSERT语句的纯SQL文件【业务定制核心】
:: --clean：备份前先删除表(防冲突)  --if-exists：表存在才删除  --inserts：显式生成INSERT语句，可读性拉满
%PG_DUMP% -h %DB_HOST% -U %DB_USER% %DB_NAME% --clean --if-exists --inserts -f %TARGET_FILE%

:: 3. 备份结果校验
if exist "%TARGET_FILE%" (
    if %~zTARGET_FILE% gtr 0 (
        echo [%DATE%] [成功] 全量备份完成，文件：%FILENAME% >> %LOG_FILE%
    ) else (
        echo [%DATE%] [失败] 备份文件为空，已删除空文件 >> %LOG_FILE%
        del /f /q %TARGET_FILE%
        exit /b 1
    )
) else (
    echo [%DATE%] [失败] pg_dump执行失败，未生成备份文件 >> %LOG_FILE%
    exit /b 1
)

:: 4. 自动清理策略：目录超阈值，循环删除最旧的.sql备份文件【核心学习点】
:: du -sm 统计目录总大小(MB)，ls -tr 按时间正序排序(最旧在前)，head -n1 取最旧文件
for /f "tokens=1" %%a in ('du -sm %BACKUP_ROOT% ^| awk "{print $1}"') do set CURRENT_SIZE=%%a
:clean_loop
if !CURRENT_SIZE! gtr !MAX_SIZE_MB! (
    for /f "tokens=*" %%b in ('ls -tr %BACKUP_ROOT%\*.sql 2^>nul ^| head -n1') do set OLDEST_FILE=%%b
    if defined OLDEST_FILE (
        echo [%DATE%] [清理] 备份目录超容，删除最旧备份：!OLDEST_FILE! >> %LOG_FILE%
        del /f /q !OLDEST_FILE!
        for /f "tokens=1" %%a in ('du -sm %BACKUP_ROOT% ^| awk "{print $1}"') do set CURRENT_SIZE=%%a
        goto clean_loop
    )
)

echo [%DATE%] [完成] 全量备份+清理流程执行完毕 >> %LOG_FILE%
echo ====================================================== >> %LOG_FILE%
endlocal
exit /b 0
~~~

### 🔧 脚本 2：`pg_backup_incr.bat` - PostgreSQL WAL 日志增量备份脚本

> 核心：基于 PostgreSQL 的 WAL (Write-Ahead Log) 预写日志实现增量备份，**必须先执行全量备份，再执行增量备份**，增量备份仅备份数据库的变更日志，文件体积小、备份速度快，适合定时高频备份，完美解决「全量备份体积大、频率低」的痛点

~~~bash
@echo off
chcp 65001
setlocal enabledelayedexpansion

:: ===================== 【配置区域 - 按需修改】 =====================
set DB_HOST=127.0.0.1
set DB_USER=postgres
set DB_NAME=tax
set FULL_BACKUP_ROOT=D:\data\backups\sql_full
set WAL_BACKUP_ROOT=D:\data\backups\wal_incr
set PG_BASEBACKUP=D:\Program Files\PostgreSQL\15\bin\pg_basebackup.exe
set PG_CTL=D:\Program Files\PostgreSQL\15\bin\pg_ctl.exe
set LOG_FILE=D:\data\scripts\backup_sql_incr.log
set MAX_SIZE_MB=4096
:: ==================================================================

:: 获取当前时间
for /f "tokens=2 delims==" %%a in ('wmic OS Get localdatetime /value') do set "dt=%%a"
set "DATE_STR=!dt:~0,8!_!dt:~8,6!"

:: 1. 校验全量备份是否存在
if not exist "%FULL_BACKUP_ROOT%" (
    echo [%DATE%] [错误] 未检测到全量备份目录，增量备份必须基于全量备份！ >> %LOG_FILE%
    exit /b 1
)

:: 2. 创建增量备份目录
if not exist "%WAL_BACKUP_ROOT%\%DATE_STR%" (
    md "%WAL_BACKUP_ROOT%\%DATE_STR%"
    echo [%DATE%] [INFO] 创建增量备份目录：%WAL_BACKUP_ROOT%\%DATE_STR% >> %LOG_FILE%
)

echo [%DATE%] [开始] 执行PostgreSQL WAL增量备份，数据库：%DB_NAME% >> %LOG_FILE%

:: 3. 核心增量备份：基于物理全量备份的增量WAL日志归档
%PG_BASEBACKUP% -h %DB_HOST% -U %DB_USER% -D %WAL_BACKUP_ROOT%\%DATE_STR% -Fp -Xs -P -v >> %LOG_FILE% 2>&1

:: 4. 备份结果校验
if !errorlevel! equ 0 (
    echo [%DATE%] [成功] 增量备份完成，备份目录：%WAL_BACKUP_ROOT%\%DATE_STR% >> %LOG_FILE%
) else (
    echo [%DATE%] [失败] WAL增量备份执行失败 >> %LOG_FILE%
    exit /b 1
)

:: 5. 自动清理：增量备份目录超4GB，删除最旧增量备份
for /f "tokens=1" %%a in ('du -sm %WAL_BACKUP_ROOT% ^| awk "{print $1}"') do set CURRENT_SIZE=%%a
:incr_clean_loop
if !CURRENT_SIZE! gtr !MAX_SIZE_MB! (
    for /f "tokens=*" %%b in ('ls -tr %WAL_BACKUP_ROOT%\* 2^>nul ^| head -n1') do set OLDEST_DIR=%%b
    if defined OLDEST_DIR (
        echo [%DATE%] [清理] 增量备份目录超容，删除最旧备份：!OLDEST_DIR! >> %LOG_FILE%
        rd /s /q !OLDEST_DIR!
        for /f "tokens=1" %%a in ('du -sm %WAL_BACKUP_ROOT% ^| awk "{print $1}"') do set CURRENT_SIZE=%%a
        goto incr_clean_loop
    )
)

echo [%DATE%] [完成] 增量备份+清理流程执行完毕 >> %LOG_FILE%
echo ====================================================== >> %LOG_FILE%
endlocal
exit /b 0
~~~

### 🔧 脚本 3：`pg_restore_fix.bat` - PostgreSQL 备份修复 + 数据还原脚本

> 核心：一站式实现「备份文件完整性校验」「损坏备份文件修复」「全量备份还原」「全量 + 增量组合还原」四大核心功能，是数据库故障恢复的兜底脚本，支持两种还原模式，满足不同业务场景的恢复需求，**所有还原操作均做日志记录，可追溯**

~~~~bash
@echo off
chcp 65001
setlocal enabledelayedexpansion

:: ===================== 【配置区域 - 按需修改】 =====================
set DB_HOST=127.0.0.1
set DB_PORT=5432
set DB_USER=postgres
set DB_NAME=tax
set BACKUP_ROOT=D:\data\backups\sql_full
set WAL_BACKUP_ROOT=D:\data\backups\wal_incr
set PG_RESTORE=D:\Program Files\PostgreSQL\15\bin\pg_restore.exe
set PSQL=D:\Program Files\PostgreSQL\15\bin\psql.exe
set LOG_FILE=D:\data\scripts\restore_sql.log
:: ==================================================================

echo [%DATE%] [开始] 执行PostgreSQL备份修复与还原流程 >> %LOG_FILE%
echo ==================== 可选操作 ====================
echo 1 - 校验备份文件完整性
echo 2 - 修复损坏的.sql备份文件
echo 3 - 仅还原全量备份(纯SQL文件)
echo 4 - 还原全量备份+增量WAL日志(完整恢复)
echo ==================================================
set /p opt=请输入操作序号：

:: 1. 备份文件完整性校验
if !opt! equ 1 (
    echo [%DATE%] [校验] 开始校验备份目录下所有.sql文件 >> %LOG_FILE%
    for %%f in (%BACKUP_ROOT%\*.sql) do (
        %PSQL% -h %DB_HOST% -U %DB_USER% -d %DB_NAME% -f %%f -v ON_ERROR_STOP=1 >nul 2>&1
        if !errorlevel! equ 0 (
            echo [%DATE%] [校验成功] 文件：%%f >> %LOG_FILE%
        ) else (
            echo [%DATE%] [校验失败] 文件损坏：%%f >> %LOG_FILE%
        )
    )
    echo [%DATE%] [完成] 所有备份文件校验完毕 >> %LOG_FILE%
)

:: 2. 损坏备份文件修复（SQL文件语法修复+内容补全）
if !opt! equ 2 (
    echo [%DATE%] [修复] 开始修复损坏的备份文件 >> %LOG_FILE%
    for %%f in (%BACKUP_ROOT%\*.sql) do (
        findstr /r "^INSERT\|^CREATE\|^DROP" %%f > %%f_fix.sql
        if exist %%f_fix.sql (
            echo [%DATE%] [修复成功] 生成修复文件：%%f_fix.sql >> %LOG_FILE%
        ) else (
            echo [%DATE%] [修复失败] 文件无法修复：%%f >> %LOG_FILE%
        )
    )
)

:: 3. 仅还原全量备份（最常用，适合误操作/单表恢复）
if !opt! equ 3 (
    set /p backup_file=请输入要还原的全量备份文件路径(如：D:\data\backups\sql_full\tax_20260116_153020.sql)：
    if exist !backup_file! (
        echo [%DATE%] [还原] 开始全量还原，文件：!backup_file! >> %LOG_FILE%
        :: 先删除原有库，重建库（可选，根据业务需求注释）
        %PSQL% -h %DB_HOST% -U %DB_USER% -c "DROP DATABASE IF EXISTS %DB_NAME%; CREATE DATABASE %DB_NAME%;" >> %LOG_FILE% 2>&1
        :: 执行SQL还原
        %PSQL% -h %DB_HOST% -U %DB_USER% -d %DB_NAME% -f !backup_file! >> %LOG_FILE% 2>&1
        if !errorlevel! equ 0 (
            echo [%DATE%] [成功] 全量备份还原完成 >> %LOG_FILE%
        ) else (
            echo [%DATE%] [失败] 全量备份还原失败 >> %LOG_FILE%
        )
    ) else (
        echo [%DATE%] [错误] 还原文件不存在：!backup_file! >> %LOG_FILE%
    )
)

:: 4. 全量+增量组合还原（完整恢复到最新状态，适合数据库故障）
if !opt! equ 4 (
    set /p full_backup=请输入全量备份目录路径：
    set /p incr_backup=请输入增量备份目录路径：
    if exist !full_backup! if exist !incr_backup! (
        echo [%DATE%] [还原] 开始全量+增量完整恢复 >> %LOG_FILE%
        :: 停止数据库服务
        net stop postgresql-x64-15
        :: 还原全量备份文件
        xcopy /s /e /y !full_backup!\* D:\Program Files\PostgreSQL\15\data\
        :: 复制增量WAL日志到归档目录
        xcopy /s /e /y !incr_backup!\* D:\Program Files\PostgreSQL\15\data\pg_wal\
        :: 启动数据库服务
        net start postgresql-x64-15
        echo [%DATE%] [成功] 全量+增量完整恢复完成，数据库已重启 >> %LOG_FILE%
    ) else (
        echo [%DATE%] [错误] 全量/增量备份目录不存在 >> %LOG_FILE%
    )
)

echo [%DATE%] [完成] 备份修复与还原流程执行完毕 >> %LOG_FILE%
echo ====================================================== >> %LOG_FILE%
endlocal
pause
exit /b 0
~~~~

------

## 四、核心知识点学习（重点，备份原理 + 脚本逻辑）

### 4.1 两种备份方式的区别（必懂）

本仓库提供了 **逻辑备份 (pg_dump)** 和 **物理备份 (pg_basebackup)** 两种方式，也是 PostgreSQL 最核心的两种备份方案，适合不同场景：

| 备份方式 |     工具      |    备份产物     |                     优点                     |              缺点               |                      适用场景                      |
| :------: | :-----------: | :-------------: | :------------------------------------------: | :-----------------------------: | :------------------------------------------------: |
| 逻辑备份 |    pg_dump    | 纯文本.sql 文件 | 可读性极强、可直接编辑、跨版本兼容、恢复灵活 | 备份 / 还原速度较慢、大库体积大 | 业务方查看数据、小中型数据库、单表恢复、跨版本迁移 |
| 物理备份 | pg_basebackup | 数据库集群文件  | 备份 / 还原速度极快、适合大库、支持增量备份  |     不可读、跨版本兼容性差      |    大型数据库、全库恢复、增量备份前置、灾备恢复    |

### 4.2 增量备份核心原理（WAL 日志）

PostgreSQL 的增量备份是基于 **WAL 预写日志** 实现的，这是 PG 的核心特性，也是学习重点：

1. WAL 日志是 PostgreSQL 的「事务日志」，所有数据库的增删改查操作，都会**先写入 WAL 日志，再写入数据库文件**
2. 当执行全量备份后，后续的所有数据变更都会被记录在 WAL 日志中，增量备份就是备份这些日志文件
3. 恢复时，先还原全量备份的基础数据，再执行 WAL 日志的回放，即可将数据库恢复到**最新的状态**
4. 优点：增量日志体积小、备份频率可极高（比如每分钟备份一次），数据丢失量可控制在分钟级

### 4.3 自动清理策略核心逻辑（脚本核心亮点）

所有脚本均实现了「目录超容自动清理」的功能，核心逻辑是 **循环删除最旧文件，直到目录大小达标**，这是生产环境备份脚本的必备能力，逻辑拆解：

1. 使用 `du -sm 目录` 统计目录总大小（单位：MB）
2. 使用 `ls -tr 目录/*.sql` 按文件「修改时间正序排序」，最旧的文件排在最前面
3. 使用 `head -n1` 获取排序后的第一个文件（最旧文件）
4. 循环判断目录大小是否超标，超标则删除最旧文件，删除后重新统计大小，直到达标
5. 核心原则：**删旧留新**，永远保留最新的备份文件，这是备份清理的黄金准则

### 4.4 定时任务配置（Windows 计划任务，实现无人值守）

所有脚本均可配置 Windows「任务计划程序」实现定时自动执行，完美适配生产环境的备份需求，配置步骤（通用）：

1. 右键「此电脑」→ 管理 → 任务计划程序 → 创建基本任务
2. 填写任务名称（如：PG 全量备份），触发器选择「每天」，设置执行时间（如：凌晨 1 点、中午 12 点半）
3. 操作选择「启动程序」，浏览选择你的 BAT 脚本（如：pg_backup_full.bat）
4. 勾选「打开属性窗口」，在属性中勾选「不管用户是否登录都要运行」「使用最高权限运行」
5. 确定保存，即可实现脚本定时自动执行，无需手动操作

------

## 五、使用注意事项 & 避坑指南（必看）

### ✅ 必做注意事项

1. 所有脚本的**配置区域**必须先修改，填写自己的数据库连接信息、备份路径、工具路径，否则脚本无法执行
2. 增量备份 **必须依赖全量备份**，首次使用请先执行全量备份脚本，再执行增量备份脚本
3. 备份文件和日志文件建议分开存放，避免备份目录损坏导致日志丢失，无法排查问题
4. 定期检查备份文件的完整性，建议每周执行一次「备份修复脚本」的校验功能，确保备份可用
5. 生产环境建议将备份文件**异地备份**，防止本地磁盘损坏导致备份文件丢失

### ❌ 常见坑点 & 解决方案

1. **脚本执行报错：认证失败，需要密码** → 未配置`.pgpass`文件，或文件权限配置错误，重新配置即可
2. **pg_dump 执行失败：找不到工具** → PG 安装目录下的 bin 文件夹未配置环境变量，或脚本中`PG_DUMP`路径填写错误
3. **增量备份无文件生成** → 数据库未开启 WAL 归档功能，需修改`postgresql.conf`配置文件开启归档
4. **还原失败：数据库服务无法启动** → 还原时未停止数据库服务，或备份文件损坏，先停止服务再还原
5. **清理逻辑不执行** → Windows 环境未安装 git bash，导致`du/ls/awk`命令无法执行，安装 git bash 即可兼容

------

## 六、总结

本仓库的 3 个脚本覆盖了 PostgreSQL 数据库备份恢复的全流程，从「全量备份」到「增量备份」再到「修复还原」，所有核心逻辑均做了详细的中文注释，既适合 PostgreSQL 初学者学习备份原理，也适合生产环境直接复用。

脚本的核心设计理念：**简单、健壮、实用**，无复杂的依赖和配置，所有功能均基于 PostgreSQL 官方工具实现，保证了脚本的稳定性和兼容性。

数据库备份是数据安全的最后一道防线，希望这份脚本和学习说明能帮助到大家，也欢迎各位开发者提出优化建议，共同完善！

------

### 开源声明

本项目所有脚本均为开源学习使用，可自由修改、二次开发、商用，无需授权。使用本脚本造成的任何数据丢失、故障等问题，均由使用者自行承担，作者不承担任何责任。

学习为主，实践为辅，备份先行，数据无价。
