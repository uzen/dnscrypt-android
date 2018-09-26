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


. /system/etc/dnscrypt-proxy/init-functions

# Exit if the package is not installed
test -x $DAEMON || exit 0

log_debug_msg () {
	if [ -n "${1:-}" ]; then
		echo "[D] $NAME: $@" || true
		log -p d -t $NAME "$@" || true
	fi
}

log_error_msg () {
	if [ -n "${1:-}" ]; then
		echo "[E] $NAME: $@" || true
		log -p e -t $NAME "$@" || true
	fi
}

get_prop () { getpropf "$LOCKFILE" "$@"; }
set_prop () { setpropf "$LOCKFILE" "$1" "$2"; }

check_health () {
    if [ -s "$LOCKFILE" ]; then
        if [ "$(get_prop 'dnscrypt-resolvers')" = "none" ]; then         
            resolvers="public-resolvers.md"
            minisig="$resolvers.minisig"
				
            confdir=${DNSCRYPT_RESOLV_PATH:-`dirname "$CONFIG_FILE"`}
            
         	if check_resolvers $confdir/$resolvers; then
					log_debug_msg "copy $confdir/$resolvers to $PIDDIR..."
					cp $confdir/{$resolvers,$minisig} $PIDDIR/
				else
					log_debug_msg "$confdir/$resolvers(.minisig): file not found"
            fi
        fi
        
        if [ "$(get_prop 'ipv4-enabled')" = "false" ]; then
            log_debug_msg "ipv4_addr_unlock: enable IPv4"
            ipv4_addr_unlock
        fi
        	   
        log_debug_msg "$LOCKFILE file has been removed"     
        rm -f "$LOCKFILE"
    fi
}

_wfd_call () {
	if ! ls "$PIDDIR"/*.md 2>/dev/null; the
		return 1
	fi
}

do_start () {
    if test ! -s "$CONFIG_FILE"; then
        log_debug_msg "missing config file $CONFIG_FILE"
        exit 1
    fi
     
    mkdir -p -m 01755 "$PIDDIR" 2>/dev/null || \
        { log_debug_msg "cannot access $PIDDIR directory, are you root?"; exit 1; }

    nohup $DAEMON -config "$CONFIG_FILE" \
         -pidfile="$PIDFILE" > /dev/null 2>&1 &
    PIDVAL=$! && echo "$PIDVAL" > "$PIDFILE"
    
    status="0"
    status_of_proc "$DAEMON" "$PIDFILE" || status="$?"

    case "$status" in
       0)
            if ! wait_for_daemon _wfd_call; then
                log_error_msg "the resolvers file couldn't be uploaded?"
                set_prop "dnscrypt-resolvers" "none"
                return 10
            fi
            log_debug_msg "enabling iptables firewall rules"
            iptrules_on
            ;;
       *) # offline
            log_error_msg "ipv4_addr_lock: disable IPv4 (#$status)"
            ipv4_addr_lock && $(set_prop "ipv4-enabled" "false")
            return 1
            ;;
    esac
    return 0
}

do_stop () {    
    if ! killproc "$DAEMON" "$PIDFILE"; then
        log_debug_msg "$DAEMON died: process not running or permission denied"
        killall $NAME >/dev/null 2>&1
    fi
    
    log_debug_msg "disabling iptables firewall rules"
    iptrules_off
    
    check_health
    
    if [ -f "$PIDFILE" ]; then
        status_of_proc "$DAEMON" "$PIDFILE" || rm -f "$PIDFILE"
    fi
}

do_restart () {
    status_of_proc "$DAEMON" "$PIDFILE" && do_stop
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
                DNSCRYPT_RESOLV_PATH=$arg
            else
                echo Unrecognized argument $arg
                exit 2
            fi
            prev=$arg
        done
        
        status="0"
        do_start || status="$?"
        
        if [[ "$status" -ne 0 && "$DNSCRYPT_FORCE" = 1 ]]; then
            log_debug_msg "restart $DESC"
            do_restart
        fi
        ;;
  stop)
        log_debug_msg "stopping $DESC"
        do_stop
        ;;
  restart) do_restart ;;
  status)
        status="0"
        status_of_proc "$DAEMON" "$PIDFILE" || status="$?"
        
        case "$status" in
          0) log_debug_msg "$NAME is running" ;;
          1) log_error_msg "program is dead and pid file exists" ;; 
          3) log_error_msg "could not access PID file" ;;    
          *) log_error_msg "$NAME is NOT running (#$status)" ;;
        esac
	
        exit $status
        ;;
  *)
        echo "Usage: /etc/init.d/99dnscrypt {start|stop|restart|status}" >&2
        exit 1
        ;;
esac

exit 0