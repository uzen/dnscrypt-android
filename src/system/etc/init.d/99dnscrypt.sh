#!/system/bin/sh

# /etc/init.d/99dnscrypt: start and stop the dnscrypt daemon

set -e

NAME=dnscrypt-proxy
DAEMON=/system/xbin/$NAME
PIDDIR=/data/local/tmp/dnscrypt
PIDFILE=$PIDDIR/dnscrypt-proxy.pid
LOCKFILE=$PIDDIR/dnscrypt-proxy.lock
CONFIG_FILE=/etc/dnscrypt-proxy/dnscrypt-proxy.toml
DESC="dns client proxy"

. /etc/dnscrypt-proxy/iptables-rules
. /etc/dnscrypt-proxy/init-functions

# Exit if the package is not installed
test -x $DAEMON || exit 0

log_debug_msg () {
	if [ -n "${1:-}" ]; then
		echo "[D] $NAME: $@" || true
		log -p d -t $NAME "$@"
	fi
}

log_error_msg () {
	if [ -n "${1:-}" ]; then
		echo "[E] $NAME: $@" || true
		log -p e -t $NAME "$@"
	fi
}

get_prop () { getpropf "$LOCKFILE" "$@"; }
set_prop () { setpropf "$LOCKFILE" "$1" "$2"; }

check_health () {
    if [ -s "$LOCKFILE" ]; then
        while IFS== read -r KEY VALUE || [[ -n $KEY ]]; do
            [[ "$KEY" = [#!]* ]] && continue;
            export "$KEY=$VALUE"
        done < $LOCKFILE
    
        if [ -z "${DNSCRYPT_RESOLV_PATH:-}" ]; then
            confdir=${DNSCRYPT_RESOLV_PATH:-`dirname "$CONFIG_FILE"`}

            resolvers=$(ls $confdir/*.md 2>/dev/null)
            for file in "$resolvers"; do
            	if check_resolvers $file; then
            		log_debug_msg "copy $file to $PIDDIR..."
            		cp $file $file.minisig $PIDDIR
            	else
            		log_debug_msg "$file(.minisig): file not found"
            	fi
            done
        fi
        
        if [ -z "${DNSCRYPT_ADDR_LOCK:-}" ]; then
            log_debug_msg "ipv4_addr_unlock: enable IPv4"
            ipv4_addr_unlock
        fi
        	   
        log_debug_msg "$LOCKFILE file has been removed"     
        rm -f "$LOCKFILE"
    fi
}

do_start () {
    if test ! -s "$CONFIG_FILE"; then
        log_debug_msg "missing config file $CONFIG_FILE"
        exit 1
    fi
     
    mkdir -p -m 01755 "$PIDDIR" 2>/dev/null || \
        { log_debug_msg "cannot access $PIDDIR directory, are you root?"; exit 1; }
        
    if ! $DAEMON -check -config "$CONFIG_FILE" > /dev/null; then
		log_error_msg "$NAME configuration is invalid"
		set_prop "DNSCRYPT_RESOLV_PATH" ""
		return 10
    fi

    nohup $DAEMON -config "$CONFIG_FILE" \
         -pidfile="$PIDFILE" > /dev/null 2>&1 &
    PIDVAL=$! && echo "$PIDVAL" > "$PIDFILE"
    
    status="0"
    status_of_proc "$DAEMON" "$PIDFILE" || status="$?"

    case "$status" in
       0)
            log_debug_msg "enabling iptables firewall rules"
            iptrules_on
            ;;
       *) # offline
            log_error_msg "ipv4_addr_lock: disable IPv4 (#$status)"
            ipv4_addr_lock
            
            set_prop "DNSCRYPT_ADDR_LOCK" "1"
            return 1
            ;;
    esac
    return 0
}

do_stop () {    
    if ! killproc "$DAEMON" "$PIDFILE"; then
        killall $NAME >/dev/null 2>&1 &
    fi
    
    log_debug_msg "disabling iptables firewall rules"
    iptrules_off
    
    check_health
    
    if [ -f "$PIDFILE" ]; then
        status_of_proc "$DAEMON" "$PIDFILE" || rm -f "$PIDFILE"
    fi
}

do_restart () {
    do_stop
    sleep 1
    do_start
}

case "$1" in
  start)
        log_debug_msg "starting $DESC"
        prev=""
        for arg in "$@"; do
            if [[ $arg == $1 ]]; then
                continue
            elif [[ $arg == -f || $arg == --force ]]; then
                DNSCRYPT_FORCE=1
            elif [[ $arg == -r || $arg == --resolv_path ]]; then
                :
            elif [[ $prev == -r || $prev == --resolv_path ]]; then
                set_prop "DNSCRYPT_RESOLV_PATH" "$arg" # use with --force flag
            else
                echo Unrecognized argument $arg
            fi
            prev=$arg
        done
        
        status="0"
        do_start || status="$?"     
        if [[ "$status" -ne 0 || "$DNSCRYPT_FORCE" = 1 ]]; then
            log_debug_msg "restore $DESC (#$status)"
            do_restart
        fi
        ;;
  stop)
        log_debug_msg "stopping $DESC"
        do_stop
        ;;
  restart)
        log_debug_msg "restart $DESC"
        do_restart 
        ;;
  status)
        status="0"
        status_of_proc "$DAEMON" "$PIDFILE" || status="$?"
        
        case "$status" in
          0) log_debug_msg "$NAME is running" ;;
          1) log_error_msg "program is dead and pid file exists" ;; 
          3) log_error_msg "could not access PID file" ;;    
          *) log_error_msg "$NAME is NOT running (#$status)" ;;
        esac
        
        $DAEMON -check -config "$CONFIG_FILE" >&2
	
        exit $status
        ;;
  *)
        echo "Usage: /etc/init.d/99dnscrypt {start|stop|restart|status}" >&2
        exit 1
        ;;
esac

exit 0