#!/usr/bin/env bash
__NAME__="RUN_WBACKUPS"

if [ -f /opt/wbackup/.ignore ];then
    exit 0
fi

LOG="${LOG:-/var/log/run_wbackup.log}"
QUIET="${QUIET:-}"
RET=0
for i in ${@};do
    if [ "x${i}" = "x--no-colors" ];then
        export NO_COLORS="1"
    fi
    if [ "x${i}" = "x--quiet" ];then
        QUIET="1"
    fi
    if [ "x${i}" = "x--help" ] || \
       [ "x${i}" = "x--h" ]  \
        ;then
        HELP="1"
    fi
done

if [ "x${HELP}" != "x" ];then
    echo "${0} [--quiet] [--no-colors]"
    echo "Run all found wbackup configurations"
    exit 1
fi
if [ x"${DEBUG}" != "x" ];then
    set -x
fi

is_container() {
    echo  "$(cat -e /proc/1/environ |grep container=|wc -l|sed -e "s/ //g")"
}

filter_host_pids() {
    pids=""
    if [ "x$(is_container)" != "x0" ];then
        pids="${pids} $(echo "${@}")"
    else
        for pid in ${@};do
            if [ "x$(grep -q /lxc/ /proc/${pid}/cgroup 2>/dev/null;echo "${?}")" != "x0" ];then
                pids="${pids} $(echo "${pid}")"
            fi
         done
    fi
    echo "${pids}" | sed -e "s/\(^ \+\)\|\( \+$\)//g"
}

go_run_wbackup() {
    conf="${1}"
    if [ "x${QUIET}" != "x" ];then
        ./wbackup.sh "${conf}" 2>&1 1>> "${LOG}"
        if [ "x${?}" != "x0" ];then
            RET=1
        fi
    else
        ./wbackup.sh "${conf}"
        if [ "x${?}" != "x0" ];then
            RET=1
        fi
    fi
}

# Location where config files exist
WBACKUPS_CONFS="${WBACKUPS_CONFS:-"/opt/wbackup"}"

# try to run postgresql backup to any postgresql version
if [ "x${PG_CONFS}" = "x" ];then
    # /etc/postgresql matches debian, /var/lib/pgsql matches redhat
    PG_CONFS=$(find /etc/postgresql /var/lib/pgsql -name postgresql.conf 2>/dev/null)
fi
if [ "x${PG_CONFS}" = "x" ];then
    PG_CONFS=/etc/postgresql.conf
fi
PORTS=$(egrep -h "^port\s=\s" ${PG_CONFS} 2>/dev/null|awk -F= '{print $2}'|awk '{print $1}'|sort -u)
if [ "x${PORTS}" = "x" ];then
    PORTS=5432
fi
CONF="${WBACKUPS_CONFS}/postgresql.conf"
for port in ${PORTS};do
    socket_path="/var/run/postgresql/.s.PGSQL.$port"
    if [ -e "${socket_path}" ];then
        # search back from which config the port comes from
        for i in  /etc/postgresql/*/*/post*.conf;do
            iport="$(egrep -h "^port\s=\s" "$i"|awk -F= '{print $2}'|awk '{print $1}')"
            if [ x"${port}" = x"${iport}" ];then
                export PGVER="$(basename $(dirname $(dirname ${i})))"
                export PGVER="${PGVER:-9.3}"
                break
            fi
        done
        if [ -e "${CONF}" ];then
            export PGHOST="/var/run/postgresql"
            export HOST="${PGHOST}"
            export PGPORT="$port"
            export PORT="${PGPORT}"
            export PATH="/usr/lib/postgresql/${PGVER}/bin:${PATH}"
            if [ "x${QUIET}" = "x" ];then
                echo "$__NAME__: Running backup for postgresql ${socket_path}: ${VER} (${CONF} $(which psql))"
            fi
            go_run_wbackup "${CONF}"
            unset PGHOST HOST PGPORT PORT
        fi
    fi
done

# try to run mysql backups if the config file is present
CONF="${WBACKUPS_CONFS}/mysql.conf"
if [ "x$(which mysql 2>/dev/null)" != "x" ] && [ x"$(filter_host_pids $(ps aux|grep mysqld|grep -v grep)|wc -w)" != "x0" ] &&  [ -e "${CONF}" ];then
    if [ "x${QUIET}" = "x" ];then
        echo "$__NAME__: Running backup for mysql: $(mysql --version) (${CONF} $(which mysql))"
    fi
    go_run_wbackup "${CONF}"
fi

# try to run redis backups if the config file is present
CONF="${WBACKUPS_CONFS}/redis.conf"
if [ "x$(which redis-server)" != "x" ] && [ x"$(filter_host_pids $(ps aux|grep redis-server|grep -v grep)|wc -w)" != "x0" ] &&  [ -e "${CONF}" ];then
    if [ "x${QUIET}" = "x" ];then
        echo "$__NAME__: Running backup for redis: $(redis-server --version|head -n1) (${CONF} $(which redis-server))"
    fi
    go_run_wbackup "${CONF}"
fi

# try to run mongodb backups if the config file is present
CONF="${WBACKUPS_CONFS}/mongod.conf"
if [ "x$(which mongod 2>/dev/null )" != "x" ] && [ x"$(filter_host_pids $(ps aux|grep mongod|grep -v grep)|wc -w)" != "x0" ] &&  [ -e "${CONF}" ];then
    if [ "x${QUIET}" = "x" ];then
        echo "$__NAME__: Running backup for mongod: $(mongod --version|head -n1) (${CONF} $(which mongod))"
    fi
    go_run_wbackup "${CONF}"
fi

# try to run file backups if the config file is present
CONF="${WBACKUPS_CONFS}/file.conf"
if [ x"$(filter_host_pids $(ps aux|grep file|grep -v grep|awk '{print $2}')|wc -w)" != "x0" ] &&  [ -e "${CONF}" ];then
    if [ "x${QUIET}" = "x" ];then
        echo "$__NAME__: Running backup for file"
    fi
    go_run_wbackup "${CONF}"
fi

if [ "x${QUIET}" != "x" ] && [ "x${RET}" != "x0" ];then
    cat "${LOG}"
fi
exit $RET
