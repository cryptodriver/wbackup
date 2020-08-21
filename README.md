# WBackup
This is a simple backup scripte that supports almost major platform.  
You can easily copy it to use in your operation.  

# Purpose
There are many ways to backup databases or files which can be used in specific  
platform or specific target(postgres, redis, mysql, and so on).  
But I want make a common and simple way to backup all the type of database or file   
and can run on all the os. This is the script.

# Support DB  
Postgresql  
Mysql  
Mongodb  
Redis  
Any file or directory  

More DB would be supported in the future...

# Support OS  
CentOS
Unix
Solaris

# Usage
INSTALL PATH: /opt/wbackup　　
USER RUAN AS: root　　
RUN  EXAMPLE: /opt/wbackup/wbackup.sh /opt/wbackup/conf/postgresql.conf  

# Setting help
One of backup type: postgresql mysql mongodb redis file  
#BACKUP_TYPE=postgresql  

User to run dump command as, defaults to logged in user  
#RUNAS=postgres  

DB user to connect to the database with, defaults to \$RUNASă  
#DBUSER=postgres

# Backup settings

Work directory location.  
#TOP_BACKUPDIR="/opt/wbackup/work"  

Global backup flag (use by postgresql to save roles/groups)  
#DO_GLOBAL_BACKUP="0"  

Directories permission  
#DPERM="750"  

Directory permission  
#FPERM="640"  

Owner/Group  
#OWNER=root  
#GROUP=root  

# Database connection settings

Host defaults to localhost and without port  
#HOST=""
#PORT=""

Defaults to postgres on postgresql backup as ident is used by default on many installs  
#PASSWORD=""  

List of DBNAMES for backup e.g. "DB1 DB2 DB3"  
if BACKUP_TYPE is file, set directory or single filename here e.g. "/home/user1/ /home/user1/test2/"  
#DBNAMES="all"

Compression type, defaults to xz, optionals gzip or bzip2 or xz and nocomp(no compression)  
set nocomp to avoid double compressions if BACKUP_TYPE is file and directory is selected  
COMP=tar

Postgresql  
# Binaries path  
#PSQL=""  
#PG_DUMP=""  
#PG_DUMPALL=""  


MYSQL  
#MYSQL_SOCK_PATHS=""  
#MYSQL=""  
#MYSQLDUMP=""  
# Disable mysqldump --single-transaction0  
#MYSQLDUMP_NO_SINGLE_TRANSACTION=""  
# Disable to enable autocommit  
#MYSQLDUMP_AUTOCOMMIT="1"  
# Set to enable complete inserts (true by default, disabling enable extended inserts)  
#MYSQLDUMP_COMPLETEINSERTS="1"  
# Disable mysqldump --lock-tables=false  
#MYSQLDUMP_LOCKTABLES=""  
# Set to add extra dumps info  
#MYSQLDUMP_DEBUG=""  
# Set to disable dump routines  
#MYSQLDUMP_NOROUTINES=""  
# Use ssl to connect  
#MYSQL_USE_SSL=""  

Mongodb
# MONGODB_PATH="\${MONGODB_PATH:-"/var/lib/mongodb"}"  
# MONGODB_USER="\${MONGODB_USER:-""}"  
# MONGODB_PASSWORD="\${MONGODB_PASSWORD:-"\${PASSWORD}"}"  
# MONGODB_ARGS="\${MONGODB_ARGS:-""}"  

Redis  
# REDIS_PATH="\${REDIS_PATH:-"/var/lib/redis"}"  

Remote server settings(remote transfer will be skipped if no setting)  
#TRANSHOST=192.168.0.1  

Remote transfer command, defaults to scp. optionals ftp  
#TRANSCMD=scp  

User would be used to login remote server  
#TRNASUSER=wbackup  
Remote server ftp password  
#TRNASPSWD=root  

Remote server access ssh key  
#TRNASKEY=/root/.ssh/id_dsa  
Remote transfer directory  
#TRANSPATH=/backup/<host name>  
