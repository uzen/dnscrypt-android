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

WAITFORDAEMON=30

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

get_prop () { getpropf $LOCKFILE "$@"; }
set_prop () { setpropf $LOCKFILE "$1" "$2"; }

check_health () {           
   test -s "$LOCKFILE" || return 1
   
	if [ "$(get_prop 'dnscrypt-resolvers')" = "none" ]; then
		confdir=`dirname "$CONFIG_FILE"`
		intdir="/sdcard/$NAME"
		
		resolvers="public-resolvers.md"
		minisig="$resolvers.minisig"
		
		if check_resolvers $confdir/$resolvers; then
			log_debug_msg "copy $confdir/$resolvers to $PIDDIR..."
			cp $confdir/{$resolvers,$minisig} $PIDDIR/
		elif check_resolvers $intdir/$resolvers; then
			log_debug_msg "copy $intdir/$resolvers to $PIDDIR..."
			cp $intdir/{$resolvers,$minisig} $PIDDIR/
		else
			log_debug_msg "$resolvers(.minisig): file not found"
		fi
   fi
            
   if [ "$(get_prop 'ipv4-enabled')" = "false" ]; then
      log_debug_msg "ipv4_addr_unlock: enable IPv4"
      ipv4_addr_unlock
   fi
   
   log_debug_msg "$LOCKFILE file has been removed"     
   rm -f "$LOCKFILE"
}

_wfd_call () {
	[ -e $PIDDIR/*.md ] || return 1 
}

do_start () {
    if test ! -s "$CONFIG_FILE"; then
        log_debug_msg "missing config file $CONFIG_FILE"
        exit 0
    fi
     
    mkdir -p -m 01755 "$PIDDIR" 2>/dev/null || \
        { log_debug_msg "cannot access $PIDDIR directory, are you root?"; exit 1; }

    nohup $DAEMON -config $CONFIG_FILE \
         -pidfile=$PIDFILE > /dev/null 2>&1 &
    RETVAL=$! && printf "$RETVAL\n" > $PIDFILE
    
    status="0"
    status_of_proc "$DAEMON" "$PIDFILE" || status="$?"
    
    case "$status" in
       0) # ok
       		wait_for_daemon _wfd_call || status="$?"
            log_debug_msg "enabling iptables firewall rules"
            do_iptables_rules 0
            if [ "$status" = 1 ]; then
                log_error_msg "the resolvers file couldn't be uploaded?"
                set_prop "dnscrypt-resolvers" "none"
                return 10
            fi
            ;;
       *) # offline	
            log_error_msg "ipv4_addr_lock: disable IPv4 (#$status)"
            ipv4_addr_lock && $(set_prop "ipv4-enabled" "false")
            return 1
            ;;
    esac
}

do_stop () {    
    if killproc "$DAEMON" "$PIDFILE"; then
        log_debug_msg "disabling iptables firewall rules"
        do_iptables_rules 1
    else
        log_debug_msg "$DAEMON died: process not running or permission denied"
        exit 1
    fi
    
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
  
        if ! do_start; then
            check_health
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