#!/usr/bin/env bash
__NAME__="WBACKUP"

#if [ x"$SHELL" = "x/bin/bash" ];then
#    set -o posix &> /dev/null
#fi

fn_exists() {
    echo $(LC_ALL=C;LANG=C;type ${1} 2>&1 | head -n1 | grep "is a function" > /dev/null;echo $?)
}

print_name() {
    echo -e "[${__NAME__}]"
}

log() {
    echo -e "${RED}$(print_name) ${@}${NORMAL}" 1>&2
}

cyan_log() {
    echo -e "${CYAN}${@}${NORMAL}" 1>&2
}

die_() {
    ret="${1}"
    shift
    cyan_log "ABRUPT PROGRAM TERMINATION: ${@}"
    exit ${ret}
}

die() {
    die_ 1 "${@}"
}

die_in_error_() {
    ret="${1}"
    shift
    msg="${@:-"${ERROR_MSG}"}"
    if [ x"${ret}" != "x0" ];then
        die_ "${ret}" "${msg}"
    fi
}

die_in_error() {
    die_in_error_ "$?" "${@}"
}

yellow_log(){
    echo -e "${YELLOW}$(print_name) ${@}${NORMAL}" 1>&2
}

readable_date() {
    date +"%Y-%m-%d %H:%M:%S"
}

debug() {
    if [ x"${WB_DEBUG}" != "x" ];then
        yellow_log "DEBUG $(readable_date): $@"
    fi
}

usage() {
    cyan_log "- Backup databases or files"
    yellow_log "  $0"
    yellow_log "     /path/to/config"
    yellow_log "        alias to --backup"
    yellow_log "     -b|--backup /path/to/config:"
    yellow_log "        backup databases"
}

runas() {
    echo "${RUNAS:-"$(whoami)"}"
}

quote_all() {
    cmd=""
    for i in "${@}";do
        cmd="${cmd} \"$(echo "${i}"|sed "s/\"/\"\'\"/g")\""
    done
    echo "${cmd}"
}

runcmd_as() {
    cd "${RUNAS_DIR:-/}"
    bin="${1}"
    shift
    args=$(quote_all "${@}")
    if [ x"$(runas)" = "x" ] || [ x"$(runas)" = "x$(whoami)" ];then
        ${bin} "${@}"
    else
        su ${RUNAS} -c "${bin} ${args}"
    fi
}

get_compressed_name() {
    if [ x"${COMP}" = "xxz" ];then
        echo "${1}.xz";
    elif [ x"${COMP}" = "xgz" ] || [ x"${COMP}" = "xgzip" ];then
        echo "${1}.gz";
    elif [ x"${COMP}" = "xbzip2" ] || [ x"${COMP}" = "xbz2" ];then
        echo "${1}.bz2";
    elif [ x"${COMP}" = "xtar" ];then
        echo "${1}.tar";
    else
        echo "${1}";
    fi
}

set_compressor() {
    for comp in ${COMP} ${COMPS};do
        c=""
        if [ x"${COMP}" = "xxz" ];then
            XZ="${XZ:-xz}"
            c="${XZ}"
        elif [ x"${COMP}" = "xgz" ] || [ x"${COMP}" = "xgzip" ];then
            GZIP="${GZIP:-gzip}"
            c="${GZIP}"
        elif [ x"${COMP}" = "xbzip2" ] || [ x"${COMP}" = "xbz2" ];then
            BZIP2="${BZIP2:-bzip2}"
            c="${BZIP2}"
        elif [ x"${COMP}" = "xtar" ];then
            TAR="${TAR:-tar}"
            c="${TAR}"
        else
            c="nocomp"
        fi
        # test that the binary is present
        if [ x"$c" != "xnocomp" ] && [ -e "$(which "$c")" ];then
            break
        else
            COMP="nocomp"
        fi
    done
}

get_xfname() {
  if [[ -d "${1}" ]]; then
      pfn="`echo ${1} | sed -e '0,/\// s///' -e 's/\//_/g'`"
  else
      pfn="`echo ${1} | sed -e '0,/\// s///' -e 's/\//_/g' -e 's/\./_/g'`"
  fi
  echo "${pfn}"
}

cleanup_uncompressed_dump_if_ok() {
    if [ x"$?" = x"0" ];then
        rm -f "$name"
    fi
}

do_compression() {
    COMPRESSED_NAME=""
    name="${1}"
    zname="${2:-$(get_compressed_name ${1})}"
    if [ x"${COMP}" = "xxz" ];then
        "${XZ}" --stdout -f -k "${name}" > "${zname}"
        cleanup_uncompressed_dump_if_ok
    elif [ x"${COMP}" = "xgz" ] || [ x"${COMP}" = "xgzip" ];then
        "${GZIP}" -f -c "${name}" > "${zname}"
        cleanup_uncompressed_dump_if_ok
    elif [ x"${COMP}" = "xbzip2" ] || [ x"${COMP}" = "xbz2" ];then
        "${BZIP2}" -f -k -c "${name}" > "${zname}"
        cleanup_uncompressed_dump_if_ok
    elif [ x"${COMP}" = "xtar" ];then
        c="${PWD}"
        cd "$(dirname ${name})" && tar cf "${zname}" "$(basename ${name})" && cd "${c}"
        cleanup_uncompressed_dump_if_ok
    else
        /bin/true # noop
    fi
    if [ -e "${zname}" ] && [ x"${zname}" != "x${name}" ];then
        COMPRESSED_NAME="${zname}"
    else
        if [ -e "${name}" ];then
            log "No compressor found, no compression done"
            COMPRESSED_NAME="${name}"
        else
            log "Compression error"
        fi
    fi
    if [ x"${COMPRESSED_NAME}" != "x" ];then
        fix_perm "${fic}"
    fi
}

get_logsdir() {
    dir="${TOP_BACKUPDIR}/logs"
    echo "$dir"
}

get_logfile() {
    filen="$(get_logsdir)/${__NAME__}_${FDATE}.log"
    echo ${filen}
}

get_backupdir() {
    dir="${TOP_BACKUPDIR}/${BACKUP_TYPE:-}"
    if [  x"${BACKUP_TYPE}" = "xpostgresql" ];then
        host="${HOST}"
        if [ x"${HOST}" = "x" ] || [ x"${PGHOST}" = "x" ];then
            host="localhost"
        fi
        if [ -e $host ];then
            host="localhost"
        fi
        dir="$dir/$host"
    fi
    echo "$dir"
}

create_db_directories() {
    db="${1}"
    dbdir="$(get_backupdir)/${db}"
    created="0"
    for d in\
        "$dbdir"\
        "$dbdir/dumps"\
        ;do
        if [ ! -e "$d" ];then
            mkdir -p "$d"
            created="1"
        fi
    done
    if [ x"${created}" = "x1" ];then
        fix_perms
    fi
}

do_db_backup_() {
    LAST_BACKUP_STATUS=""
    db="${1}"
    fun_="${2}"
    if [ x"${BACKUP_TYPE}" == "xfile" ];then
        db="$(get_xfname "${1}")"
    fi
    create_db_directories "${db}"
    real_filename="$(get_backupdir)/${db}/dumps/${db}@${FDATE}.$(backup_ext "${1}")"
    zreal_filename="$(get_compressed_name "${real_filename}")"
    adb="${YELLOW}${db}${NORMAL} "
    if [ x"${db}" = x"${GLOBAL_SUBDIR}" ];then
        adb=""
    fi
    log "Dumping target ${adb}${RED}to maybe uncompressed dump: ${YELLOW}${real_filename}${NORMAL}"
    $fun_ "${1}" "${real_filename}"
    if [ x"$?" != "x0" ];then
        LAST_BACKUP_STATUS="failure"
        log "${CYAN}    Backup of ${db} failed !!!${NORMAL}"
    else
        do_compression "${real_filename}" "${zreal_filename}"
    fi
}

do_db_backup() {
    db="`echo ${1} | sed 's/%/ /g'`"
    fun_="${BACKUP_TYPE}_dump"
    do_db_backup_ "${db}" "$fun_"
}

do_global_backup() {
    db="$GLOBAL_SUBDIR"
    fun_="${BACKUP_TYPE}_dumpall"
    log_rule
    log "GLOBAL BACKUP"
    log_rule
    do_db_backup_ "${db}" "$fun_"
}

activate_IO_redirection() {
    if [ x"${WB_ACTITED_RIO}" = x"" ];then
        WB_ACTITED_RIO="1"
        logdir="$(dirname $(get_logfile))"
        if [ ! -e "${logdir}" ];then
            mkdir -p "${logdir}"
        fi
        touch "$(get_logfile)"
        exec 1> >(tee -a "$(get_logfile)") 2>&1
    fi
}


deactivate_IO_redirection() {
    if [ x"${WB_ACTITED_RIO}" != x"" ];then
        WB_ACTITED_RIO=""
        exec 1>&1  # Restore stdout and close file descriptor #6.
        exec 2>&2  # Restore stdout and close file descriptor #7.
    fi
}

do_pre_backup() {
    debug "do_pre_backup"
    # IO redirection for logging.
    if [ x"$COMP" = "xnocomp" ];then
        comp_msg="No compression"
    else
        comp_msg="${COMP}"
    fi
    # If backing up all DBs on the server
    log_rule
    log "WELL_BACKUP"
    log "Conf: ${YELLOW}'${WB_CONF_FILE}'"
    log "Log: ${YELLOW}'$(get_logfile)'"
    log "Backup Start Time: ${YELLOW}$(readable_date)${NORMAL}"
    log "Backup of database compression://type@server: ${YELLOW}${comp_msg}://${BACKUP_TYPE}@${HOST}${NORMAL}"
    log_rule
}

do_after_backup() {
    debug "do_after_backup"
    log_rule

    if [ x"$TRANSHOST" != "x" ];then
        log "Transfer backup files to remote server"
        if [ "x${BACKUP_DB_NAMES}" != "x" ];then
            for db in ${BACKUP_DB_NAMES};do
                sf="${db}"
                if [ x"${BACKUP_TYPE}" == "xfile" ];then
                    db="$(get_xfname "${db}")"
                fi
                real_filename="$(get_backupdir)/${db}/dumps/${db}@${FDATE}.$(backup_ext "${sf}")"
                zreal_filename="$(get_compressed_name "${real_filename}")"
                do_transfer "$zreal_filename"
                log "Transfered backup file: ${YELLOW}${TRANSHOST}:${zreal_filename}${NORMAL}"
            done
        fi
    fi

    log "Log: Completed do_after_backup"
    log_rule
}

do_transfer() {
    zreal_filename="${1}"

    if [ x"$TRANSCMD" = "xscp" ];then
        if [ ! -e "${TRNASKEY}" ]; then
            die_in_error "No keyfile found for scp"
        fi
        scp -i "${TRNASKEY}" "${zreal_filename}" "${TRNASUSER}"@"${TRANSHOST}":"${TRANSPATH}"
    fi
    if [ x"$TRANSCMD" = "xftp" ];then
        if [ ! "x$(which ftp)" != "x" ];then
            die_in_error "No ftp command found"
            # yum -y install ftp
        fi
        ftp -n "${TRANSHOST}" <<END_SCRIPT
        quote USER ${TRNASUSER}
        quote PASS ${TRNASPSWD}
        binary
        cd ${TRANSPATH}
        put ${zreal_filename}
        quit
END_SCRIPT
    fi
}

fix_perm() {
    fic="${1}"
    if [ -e "${fic}" ];then
        if [ -d "${fic}" ];then
            perm="${DPERM:-750}"
        elif [ -f "${fic}" ];then
            perm="${FPERM:-640}"
        fi
        chown ${OWNER:-"root"}:${GROUP:-"root"} "${fic}"
        chmod -f $perm "${fic}"
    fi
}

fix_perms() {
    debug "fix_perms"
    find  "${TOP_BACKUPDIR}" -type d -print|\
        while read fic
        do
            fix_perm "${fic}"
        done
    find  "${TOP_BACKUPDIR}" -type f -print|\
        while read fic
        do
            fix_perm "${fic}"
        done
}


wrap_log() {
    echo -e "$("$@"|sed "s/^/$(echo -e "${NORMAL}${RED}")$(print_name)  $(echo -e "${NORMAL}${YELLOW}")/g"|sed "s/  +/   /g")${NORMAL}"
}

do_post_backup() {
    log_rule
    debug "do_post_backup"
    if [ -d "$(get_backupdir)" ];then
        log "Disk space used for backup storage.."
        log "  Size   - Location:"
        wrap_log du -sh "$(get_backupdir)"/*
    fi
    log_rule
    log "Backup end time: ${YELLOW}$(readable_date)${NORMAL}"
    log_rule
    deactivate_IO_redirection
    sanitize_log
}

sanitize_log() {
    sed -e "s/\x1B\[[0-9;]*[JKmsu]//g" -e "s/[[;0-9;]*[JKmsu]//g" "$(get_logfile)" > "$(get_logfile).temp" && mv "$(get_logfile).temp" $(get_logfile)
}

get_sorted_files() {
    files="$(ls -1 "${1}" 2>/dev/null)"
    echo -e "${files}"|while read fic;do
        echo "${fic}"
    done | sort -n -r | awk '{print $1}'
}

do_rotate() {
    log_rule
    debug "rotate"
    if [ ! -d "$(get_backupdir)" ];then
        return
    fi
    log "Execute backup rotation policy, keep"
    log "   -  logs           : ${YELLOW}${KEEP_LOGS}${NORMAL}"
    log "   -  dumps          : ${YELLOW}${KEEP_DUMPS}${NORMAL}"
    ls -1d "${TOP_BACKUPDIR}" "$(get_backupdir)"/*|while read nsubdir;do
        suf=""
        if [ x"$nsubdir" = "x${TOP_BACKUPDIR}" ];then
            subdirs="logs"
            suf="/logs"
        else
            subdirs="dumps"
        fi
        log "   -  Operating in: ${YELLOW}'${nsubdir}${suf}'${NORMAL}"
        for chronodir in ${subdirs};do
            subdir="${nsubdir}/${chronodir}"
            if [ -d "${subdir}" ];then
                if [ x"${chronodir}" = "xlogs" ];then
                    to_keep=${KEEP_LOGS:-30}
                elif [ x"${chronodir}" = "xdumps" ];then
                    to_keep=${KEEP_DUMPS:-1}
                else
                    to_keep="65535" # int limit
                fi
                i=0
                get_sorted_files "${subdir}" | while read nfic;do
                    dfic="${subdir}/${nfic}"
                    i="$((${i}+1))"
                    if [ "${i}" -gt "${to_keep}" ] &&\
                        [ -e "${dfic}" ] &&\
                        [ ! -d ${dfic} ];then
                        log "       * Unlinking ${YELLOW}${dfic}${NORMAL}"
                        rm "${dfic}"
                    fi
                done
            fi
        done
    done
}

log_rule() {
    log "======================================================================"
}

do_prune() {
    do_rotate
    fix_perms
    do_post_backup
}

handle_exit() {
    WB_RETURN_CODE="${WB_RETURN_CODE:-$?}"
    if [ x"${WB_BACKUP_STARTED}" != "x" ];then
        debug "handle_exit"
        do_prune
        if [ x"$WB_RETURN_CODE" != "x0" ];then
            log "WARNING, this script did not behaved correctly, check the log: $(get_logfile)"
        fi
        if [ x"${WB_GLOBAL_BACKUP_IN_FAILURE}" != x"" ];then
            cyan_log "Global backup failed, check the log: $(get_logfile)"
            WB_RETURN_CODE="${WB_BACKUP_FAILED}"
        fi
        if [ x"${WB_BACKUP_IN_FAILURE}" != x"" ];then
            cyan_log "One of the databases backup failed, check the log: $(get_logfile)"
            WB_RETURN_CODE="${WB_BACKUP_FAILED}"
        fi
    fi
    exit "${WB_RETURN_CODE}"
}

do_trap() {
    debug "do_trap"
    trap handle_exit      EXIT SIGHUP SIGINT SIGQUIT SIGTERM
}

do_backup() {
    debug "do_backup"
    if [ x"${BACKUP_TYPE}" = "x" ];then
        die "No backup type, choose between mysql,postgresql,redis,mongodb,file"
    fi
    die_in_error "Invalid configuration file: ${WB_CONF_FILE}"
    WB_BACKUP_STARTED="y"
    do_pre_backup
    if [ x"${DO_GLOBAL_BACKUP}" != "x0" ];then
        do_global_backup
        if [ x"${LAST_BACKUP_STATUS}" = "xfailure" ];then
            WB_GLOBAL_BACKUP_IN_FAILURE="y"
        else
            /bin/true
        fi
    fi
    if [ "x${BACKUP_DB_NAMES}" != "x" ];then
        log_rule
        log "START BACKUP"
        log_rule
        for db in ${BACKUP_DB_NAMES};do
            do_db_backup $db
            if [ x"${LAST_BACKUP_STATUS}" = "xfailure" ];then
                WB_BACKUP_IN_FAILURE="y"
            else
                /bin/true
            fi
        done
    fi
    do_after_backup
}

mark_run_rotate() {
    WB_CONF_FILE="${1}"
    DO_PRUNE="1"
}

mark_run_backup() {
    WB_CONF_FILE="${1}"
    DO_BACKUP="1"
}

verify_backup_type() {
    for typ_ in _dump _dumpall;do
        if [ x"$(fn_exists ${BACKUP_TYPE}${typ_})" != "x0" ];then
            die "Please provide a ${BACKUP_TYPE}${typ_} export function"
        fi
    done
}

db_user() {
    echo "${DBUSER:-${RUNAS:-$(whoami)}}"
}

backup_ext() {
  if [ "x${BACKUP_TYPE}" = "xmongodb" ]\
     || [ "x${BACKUP_TYPE}" = "xredis" ]\
     || ( [ "x${BACKUP_TYPE}" = "xfile" ] && [[ -d "${1}" ]] );then
      ext="tar"
  else
      ext="dump"
  fi
  echo "${ext}"
}

set_colors() {
    YELLOW="\e[1;33m"
    RED="\\033[31m"
    CYAN="\\033[36m"
    NORMAL="\\033[0m"
    if [ x"$NO_COLOR" != "x" ] || [ x"$NOCOLOR" != "x" ] || [ x"$NO_COLORS" != "x" ] || [ x"$NOCOLORS" != "x" ];then
        YELLOW=""
        RED=""
        CYAN=""
        NORMAL=""
    fi
}

set_vars() {
    debug "set_vars"
    args=${@}
    set_colors
    PARAM=""
    parsable_args="$(echo "${@}"|sed "s/^--//g")"
    if [ x"${parsable_args}" = "x" ];then
        USAGE="1"
    fi
    if [ -e "${parsable_args}" ];then
        mark_run_backup ${1}
    else
        while true
        do
            sh="1"
            if [ x"${1}" = "x$PARAM" ];then
                break
            fi
            if [ x"${1}" = "x-p" ] || [ x"${1}" = "x--prune" ];then
                mark_run_rotate ${2};sh="2"
            elif [ x"${1}" = "x-b" ] || [ x"${1}" = "x--backup" ];then
                mark_run_backup ${2};sh="2"
            else
                if [ x"${WELL_BACKUP_AS_FUNCS}" = "x" ];then
                    usage
                    die "Invalid invocation"
                fi
            fi
            PARAM="${1}"
            OLD_ARG="${1}"
            i=1
            while [ $i -le $sh ]; do
              if [ x"${1}" = "x${OLD_ARG}" ];then
                  break
              fi
              i=$(expr $i + 1)
            done
            if [ x"${1}" = "x" ];then
                break
            fi
        done
    fi

    ######## Path settings
    EXT_PATH="${EXT_PATH:-/usr/ucb}"
    for ep in ${EXT_PATH};do
        if [ -d "${ep}" ]; then
          PATH="$PATH:${ep}"
        fi
    done

    ######## Backup settings
    NO_COLOR="${NO_COLOR:-}"
    COMP=${COMP:-tar}
    BACKUP_TYPE=${BACKUP_TYPE:-}
    TOP_BACKUPDIR="${TOP_BACKUPDIR:-/var/wbackup}"
    DEFAULT_DO_GLOBAL_BACKUP="0"
    DO_GLOBAL_BACKUP="${DO_GLOBAL_BACKUP:-${DEFAULT_DO_GLOBAL_BACKUP}}"
    KEEP_LOGS="${KEEP_LOGS:-3}"
    KEEP_DUMPS="${KEEP_DUMPS:-0}"
    DPERM="${DPERM:-"750"}"
    FPERM="${FPERM:-"640"}"
    OWNER="${OWNER:-"root"}"
    GROUP="${GROUP:-"root"}"

    ######## Database connection settings
    HOST="${HOST:-localhost}"
    PORT="${PORT:-}"
    RUNAS="" # see runas function
    DBUSER="" # see db_user function
    PASSWORD="${PASSWORD:-}"
    DBNAMES="${DBNAMES:-all}"
    DBEXCLUDE="${DBEXCLUDE:-}"

    ######## Transer settings
    TRANSHOST="${TRANSHOST:-}"
    TRANSUSER="${TRANSUSER:-root}"
    TRNASKEY="${TRNASKEY:-/etc/wbackup/id_rsa.pub}"
    TRANSPATH="${TRANSPATH:-/backup/"${HOST}"}"
    TRANSCMD="${TRANSCMD:-scp}"

    ######### Postgresql
    PSQL="${PSQL:-"$(which psql 2>/dev/null)"}"
    PG_DUMP="${PG_DUMP:-"$(which pg_dump 2>/dev/null)"}"
    PG_DUMPALL="${PG_DUMPALL:-"$(which pg_dumpall 2>/dev/null)"}"
    OPT="${OPT:-"--create -Fc"}"
    OPTALL="${OPTALL:-"--globals-only"}"

    ######### MYSQL
    MYSQL_USE_SSL="${MYSQL_USE_SSL:-}"
    MYSQL_SOCK_PATHS="${MYSQL_SOCK_PATHS:-"/var/run/mysqld/mysqld.sock"}"
    MYSQL="${MYSQL:-$(which mysql 2>/dev/null)}"
    MYSQLDUMP="${MYSQLDUMP:-$(which mysqldump 2>/dev/null)}"
    MYSQLDUMP_NO_SINGLE_TRANSACTION="${MYSQLDUMP_NO_SINGLE_TRANSACTION:-}"
    MYSQLDUMP_AUTOCOMMIT="${MYSQLDUMP_AUTOCOMMIT:-1}"
    MYSQLDUMP_COMPLETEINSERTS="${MYSQLDUMP_COMPLETEINSERTS:-1}"
    MYSQLDUMP_LOCKTABLES="${MYSQLDUMP_LOCKTABLES:-}"
    MYSQLDUMP_DEBUG="${MYSQLDUMP_DEBUG:-}"
    MYSQLDUMP_NOROUTINES="${MYSQLDUMP_NOROUTINES:-}"

    # mongodb
    MONGODB_PATH="${MONGODB_PATH:-"/var/lib/mongodb"}"
    MONGODB_USER="${MONGODB_USER:-"${DBUSER}"}"
    MONGODB_PASSWORD="${MONGODB_PASSWORD:-"${PASSWORD}"}"
    MONGODB_ARGS="${MONGODB_ARGS:-""}"

    ######## Advanced options
    COMPS="tar xz bz2 gzip nocomp"
    GLOBAL_SUBDIR="__GLOBAL__"
    PATH=$PATH:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
    FDATE=`date +%Y%m%d%H%M%S`
    WB_BACKUPFILES="" # thh: added for later mailing
    WB_RETURN_CODE=""
    WB_GLOBAL_BACKUP_FAILED="3"
    WB_BACKUP_FAILED="4"

    # source conf file if any
    if [ -e "${WB_CONF_FILE}" ];then
        . "${WB_CONF_FILE}"
    fi
    activate_IO_redirection
    set_compressor

    if [ x"${BACKUP_TYPE}" != "x" ];then
        verify_backup_type
        if [ x"$(fn_exists "${BACKUP_TYPE}_set_connection_vars")" = "x0" ];then
            "${BACKUP_TYPE}_set_connection_vars"
        fi
        if [ x"$(fn_exists "${BACKUP_TYPE}_check_connectivity")" = "x0" ];then
            "${BACKUP_TYPE}_check_connectivity"
        fi
        if [ x"$(fn_exists "${BACKUP_TYPE}_get_all_databases")" = "x0" ];then
            ALL_DBNAMES="$(${BACKUP_TYPE}_get_all_databases)"
        fi
        if [ x"$(fn_exists "${BACKUP_TYPE}_set_vars")" = "x0" ];then
            "${BACKUP_TYPE}_set_vars"
        fi
    fi

    BACKUP_DB_NAMES="${DBNAMES}"

    # Re source to reoverride any core overriden variable
    if [ -e "${WB_CONF_FILE}" ];then
        . "${WB_CONF_FILE}"
    fi
}

do_main() {
    if [ x"${1#--/}" = "x" ];then
        set_colors
        usage
        exit 0
    else
        do_trap
        set_vars "${@}"
        if [ x"${1#--/}" = "x" ];then
            usage
            exit 0
        elif [ "x${DO_BACKUP}" != "x" ] || [ "x${DO_PRUNE}" != "x" ] ;then
            if [ -e "${WB_CONF_FILE}" ];then
                if [ "x${DO_PRUNE}" != "x" ];then
                    func=do_prune
                else
                    func=do_backup
                fi
                ${func}
                die_in_error "end_of_scripts"
            else
                cyan_log "Missing or invalid configuration file: ${WB_CONF_FILE}"
                exit 1
            fi
        fi
    fi
}

#################### FILE
file_set_connection_vars() {
    /bin/true
}

file_set_vars() {
    /bin/true
}

file_check_connectivity() {
  for db in ${DBNAMES};do
      if [ ! -e "${db}" ];then
          die_in_error "no file in ${db}"
      fi
  done
}

file_dump() {
    BCK_DIR="$(dirname ${2})"
    if [ ! -e "${BCK_DIR}" ];then
        mkdir -p "${BCK_DIR}"
    fi
    c="${PWD}"
    if [[ -d "${1}" ]]; then
        cd "${1}" && tar cf "${2}" . && cd "${c}"
    else
        cp "${1}" "${2}"
    fi
    die_in_error "file $2 dump failed"
}

file_dumpall() {
    /bin/true
}

#################### POSTGRESQL
pg_dumpall_() {
    runcmd_as "${PG_DUMPALL}" "${@}"
}

pg_dump_() {
    runcmd_as "${PG_DUMP}" "${@}"
}

psql_() {
    runcmd_as "${PSQL}" "${@}"
}

# REAL API IS HERE
postgresql_set_connection_vars() {
    export RUNAS="${RUNAS:-postgres}"
    export PGHOST="${HOST}"
    export PGPORT="${PORT}"
    export PGUSER="$(db_user)"
    export PGPASSWORD="${PASSWORD}"
    if [ x"${PGHOST}" = "xlocalhost" ]; then
        PGHOST=
    fi
}

postgresql_set_vars() {
    if [ x"${DBNAMES}" = "xall" ]; then
        DBNAMES=${ALL_DBNAMES}
        if [ " ${DBEXCLUDE#*" template0 "*} " != " $DBEXCLUDE " ];then
            DBEXCLUDE="${DBEXCLUDE} template0"
        fi
        for exclude in ${DBEXCLUDE};do
            DBNAMES=$(echo ${DBNAMES} | sed "s/\b${exclude}\b//g")
        done
    fi
    if [ x"${DBNAMES}" = "xall" ]; then
        die "${BACKUP_TYPE}: could not get all databases"
    fi
    for i in "psql:${PSQL}" "pg_dumpall:${PG_DUMPALL}" "pg_dump:${PG_DUMP}";do
        var="$(echo ${i}|awk -F: '{print $1}')"
        bin="$(echo ${i}|awk -F: '{print $2}')"
        if  [ ! -e "${bin}" ];then
            die "missing ${var}"
        fi
    done
}

postgresql_check_connectivity() {
    who="$(whoami)"
    pgu="$(db_user)"
    psql_ --username="$(db_user)" -c "select * from pg_roles" -d postgres >/dev/null
    die_in_error "Cant connect to postgresql server with ${pgu} as ${who}, did you configured \$RUNAS("$(runas)") in $WB_CONF_FILE"
}

postgresql_get_all_databases() {
    LANG=C LC_ALL=C psql_ --username="$(db_user)"  -l -A -F: | sed -ne "/:/ { /Name:Owner/d; /template0/d; s/:.*$//; }"
}

postgresql_dumpall() {
    pg_dumpall_ --username="$(db_user)" $OPTALL > "${2}"
}

postgresql_dump() {
    pg_dump_ --username="$(db_user)" $OPT "${1}" > "${2}"
}

#################### MYSQL
# REAL API IS HERE
mysql__() {
    runcmd_as "${MYSQL}"    $(mysql_common_args) "${@}"
}

mysqldump__() {
    runcmd_as "${MYSQLDUMP}" $(mysql_common_args) "${@}"
}

mysqldump_() {
    mysqldump__ "-u$(db_user)" "$@"
}

mysql_() {
    mysql__ "-u$(db_user)" "$@"
}

mysql_set_connection_vars() {
    export MYSQL_HOST="${HOST:-localhost}"
    export MYSQL_TCP_PORT="${PORT:-3306}"
    export MYSQL_PWD="${PASSWORD}"
    if [ x"${MYSQL_HOST}" = "xlocalhost" ];then
        while read path;do
            if [ "x${path}" != "x" ]; then
                export MYSQL_HOST="127.0.0.1"
                export MYSQL_UNIX_PORT="${path}"
            fi
        done < <(printf "${MYSQL_SOCK_PATHS}\n\n")
    fi
    if [ -e "${MYSQL_UNIX_PORT}" ];then
        log "Using mysql socket: ${path}"
    else
        MYSQL_UNIX_PORT=
    fi
}

mysql_set_vars() {
    if [ x"${MYSQLDUMP_AUTOCOMMIT}" = x"" ];then
        MYSQLDUMP_OPTS_COMMON="${MYSQLDUMP_OPTS_COMMON} --no-autocommit"
    fi
    if [ x"${MYSQLDUMP_NO_SINGLE_TRANSACTION}" = x"" ];then
        MYSQLDUMP_OPTS_COMMON="${MYSQLDUMP_OPTS_COMMON} --single-transaction"
    fi
    if [ x"${MYSQLDUMP_COMPLETEINSERTS}" != x"" ];then
        MYSQLDUMP_OPTS_COMMON="${MYSQLDUMP_OPTS_COMMON} --complete-insert"
    else
        MYSQLDUMP_OPTS_COMMON="${MYSQLDUMP_OPTS_COMMON} --extended-insert"
    fi
    if [ x"${MYSQLDUMP_LOCKTABLES}" = x"" ];then
        MYSQLDUMP_OPTS_COMMON="${MYSQLDUMP_OPTS_COMMON} --lock-tables=false"
    fi
    if [ x"${MYSQLDUMP_DEBUG}" != x"" ];then
        MYSQLDUMP_OPTS_COMMON="${MYSQLDUMP_OPTS_COMMON} --debug-info"
    fi
    if [ x"${MYSQLDUMP_NOROUTINES}" = x"" ];then
        MYSQLDUMP_OPTS_COMMON="${MYSQLDUMP_OPTS_COMMON} --routines"
    fi
    MYSQLDUMP_OPTS_COMMON="${MYSQLDUMP_OPTS_COMMON} --quote-names --opt"
    MYSQLDUMP_OPTS="${MYSQLDUMP_OPTS:-"${MYSQLDUMP_OPTS_COMMON}"}"
    MYSQLDUMP_ALL_OPTS="${MYSQLDUMP_ALL_OPTS:-"${MYSQLDUMP_OPTS_COMMON} --all-databases --no-data"}"
    if [ x"${DBNAMES}" = "xall" ]; then
        DBNAMES=${ALL_DBNAMES}
        for exclude in ${DBEXCLUDE};do
            DBNAMES=$(echo ${DBNAMES} | sed "s/\b${exclude}\b//g")
        done
    fi
    if [ x"${DBNAMES}" = "xall" ]; then
        die "${BACKUP_TYPE}: could not get all databases"
    fi
    for i in "mysql:${MYSQL}" "mysqldump:${MYSQLDUMP}";do
        var="$(echo ${i}|awk -F: '{print $1}')"
        bin="$(echo ${i}|awk -F: '{print $2}')"
        if  [ ! -e "${bin}" ];then
            die "missing ${var}"
        fi
    done
}

mysql_common_args() {
    args=""
    if [ x"${MYSQL_USE_SSL}" != "x" ];then
        args="${args} --ssl"
    fi
    if [ x"${MYSQL_UNIX_PORT}" = "x" ];then
        args="--host=$MYSQL_HOST --port=$MYSQL_TCP_PORT"
    fi
    echo "${args}"
}

mysql_check_connectivity() {
    who="$(whoami)"
    mysqlu="$(db_user)"
    echo "select 1"|mysql_ information_schema&> /dev/null
    die_in_error "Cant connect to mysql server with ${mysqlu} as ${who}, did you configured \$RUNAS \$PASSWORD \$DBUSER in $WB_CONF_FILE"
}

mysql_get_all_databases() {
    echo "select schema_name from SCHEMATA;"|mysql_ -N information_schema 2>/dev/null \
        | grep -v performance_schema \
        | grep -v information_schema
    die_in_error "Could not get mysql databases"
}

mysql_dumpall() {
    mysqldump_ ${MYSQLDUMP_ALL_OPTS} 2>&1 > "${2}"
}

mysql_dump() {
    mysqldump_ ${MYSQLDUMP_OPTS} -B "${1}" > "${2}"
}


#################### MONGODB
# REAL API IS HERE
mongodb_set_connection_vars() {
    /bin/true
}

mongodb_set_vars() {
    DBNAMES=""
}

mongodb_check_connectivity() {
    test -d "${MONGODB_PATH}/journal"
    die_in_error "no mongodb"
}

mongodb_get_all_databases() {
    /bin/true
}

mongodb_dumpall() {
    DUMPDIR="${2}.dir"
    if [ ! -e ${DUMPDIR} ];then
        mkdir -p "${DUMPDIR}"
    fi
    if [ "x${MONGODB_PASSWORD}"  != "x" ];then
        MONGODB_ARGS="$MONGODB_ARGS -p $MONGODB_PASSWORD"
    fi
    if [ "x${MONGODB_USER}"  != "x" ];then
        MONGODB_ARGS="$MONGODB_ARGS -u $MONGODB_USER"
    fi
    mongodump ${MONGODB_ARGS} --out "${DUMPDIR}"\
        && die_in_error "mongodb dump failed"
    cd "${DUMPDIR}" &&  tar cf "${2}" .
    die_in_error "mongodb tar failed"
    rm -rf "${DUMPDIR}"
}

mongodb_dump() {
    /bin/true
}

#################### redis
# REAL API IS HERE
redis_set_connection_vars() {
    /bin/true
}

redis_set_vars() {
    DBNAMES=""
    export REDIS_PATH="${REDIS_PATH:-"/var/lib/redis"}"
}

redis_check_connectivity() {
    if [ ! -e "${REDIS_PATH}" ];then
        die_in_error "no redis dir"
    fi
    if [ "x${REDIS_PATH}" != "x" ];then
        die_in_error "redis dir is not set"
    fi
    if [ "x$(ls -1 "${REDIS_PATH}"|wc -l|sed -e"s/ //g")" = "x0" ];then
        die_in_error "no redis rdbs in ${REDIS_PATH}"
    fi
}

redis_get_all_databases() {
    /bin/true
}

redis_dumpall() {
    BCK_DIR="$(dirname ${2})"
    if [ ! -e "${BCK_DIR}" ];then
        mkdir -p "${BCK_DIR}"
    fi
    c="${PWD}"
    cd "${REDIS_PATH}" && tar cf "${2}" . && cd "${c}"
    die_in_error "redis $2 dump failed"
}

redis_dump() {
    /bin/true
}

#################### MAIN
if [ x"${WELL_BACKUP_AS_FUNCS}" = "x" ];then
    do_main "${@}"
fi
