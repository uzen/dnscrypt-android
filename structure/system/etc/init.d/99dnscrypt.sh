#!/system/bin/sh

# /etc/init.d/99dnscrypt: start and stop the dnscrypt daemon

set -e

NAME=dnscrypt-proxy
DAEMON=/system/xbin/$NAME
DCPIDDIR=/data/local/tmp/dnscrypt
PIDFILE=$DCPIDDIR/dnscrypt-proxy.pid
LOCKFILE=$DCPIDDIR/dnscrypt-proxy.lock
CONFIG_FILE=/system/etc/dnscrypt-proxy/dnscrypt-proxy.toml
WAITFORDAEMON=30
DESC="dns client proxy"


. /system/etc/dnscrypt-proxy/iptables-rules

# Exit if the package is not installed
test -x $DAEMON || exit 0

log_info_msg () {
	echo "$NAME: $@" || true
	log -p i -t $NAME "$@" || true
}

log_error_msg () {
	echo "$NAME: $@" || true
	log -p e -t $NAME "$@" || true
}

check_dcpiddir () {
	if test ! -d $DCPIDDIR; then
		mkdir -m 02755 "$DCPIDDIR"
		chown root.root "$DCPIDDIR"
		! [ -x /sbin/restorecon ] || /sbin/restorecon "$DCPIDDIR"
	fi

	if test ! -x $DCPIDDIR; then
		log_info_msg "cannot access $DCPIDDIR directory, are you root?"
		exit 1
	fi
}

pidofproc () {
   if [ -n "${PIDFILE:-}" ] && [ -e "$PIDFILE" ] && [ -r "$PIDFILE" ]; then
   	read pid < "$PIDFILE"
   	if [ -n "${pid:-}" ]; then
			if $(kill -0 "${pid:-}" 2> /dev/null); then
      		return 0
			elif ps "${pid:-}" >/dev/null 2>&1; then
				return 0 # program is running
   		else
   			return 1 # program is dead and pid file exists
  			fi
   	fi
   fi
   
   if ! ps | grep NAME; then
   	return 1 # program is not running
   fi
	
	return 2
}

wait_for_daemon () {
	pid=$1
	sleep 1
	if [ -n "${pid:-}" ]; then
		if $(kill -0 "${pid:-}" 2> /dev/null); then
			cnt=0
			while test ! -e $DCPIDDIR/*.md ; do
				cnt=`expr $cnt + 1`
				if [ $cnt -gt $WAITFORDAEMON ]
				then
					log_info_msg "still not running"
					return 1
				fi
				sleep 1
				[ "`expr $cnt % 3`" != 2 ] || log_info_msg "..."
			done
		fi
	fi
	return 0
}

case "$1" in
  start) log_info_msg "starting $DESC $NAME"
  
        if test ! -s "$CONFIG_FILE"; then
            log_info_msg "missing config file $CONFIG_FILE"
            exit 0
        fi
        
        check_dcpiddir
	
        if test -s "$LOCKFILE"; then
            CONFIG_DIR=$(dirname "$CONFIG_FILE")
        		cp $CONFIG_DIR/{public-resolvers.md,minisign.pub} $DCPIDDIR/
        		
            log_info_msg "ipv4_addr_unlock: enable IPv4"
            ipv4_addr_unlock && rm -f $LOCKFILE
        fi
	
        status="0"
        pidofproc >/dev/null || status="$?"
	
        if [ "$status" = 0 ]; then
            log_info_msg "$DESC already started; not starting."
            exit 0
        fi
	
        setsid $DAEMON -config $CONFIG_FILE \
            -pidfile=$PIDFILE </dev/null > /dev/null 2>&1 &
        pid=$! && echo $pid > $PIDFILE
	
        if wait_for_daemon $pid ; then
            log_info_msg "enabling iptables firewall rules"
            do_iptables_rules 0
        else
            log_error_msg "ipv4_addr_lock: disable IPv4"
            ipv4_addr_lock && echo "ipv4-enabled=false" >> $LOCKFILE
        fi
        ;;	
  stop) log_info_msg "stopping $DESC $NAME"
  
        status="0"
        pidofproc >/dev/null || status="$?"
	
        if [ "$status" = 0 ]; then
            pid="$(cat $PIDFILE 2>/dev/null)" || true
		
            if kill $pid 2>/dev/null; then
                log_info_msg "disabling iptables firewall rules"
                do_iptables_rules 1
            else 
                log_info_msg "Is $pid not $NAME? Is $DAEMON a different binary now?"
            fi
            
            log_info_msg "Removing stale PID file $PIDFILE."
            rm -f $PIDFILE
        elif [ "$status" = 2 ]; then
            log_info_msg "not running - there is no $PIDFILE"
            killall $NAME >/dev/null 2>&1
		
            exit 1
        fi
        ;;
  status)
        status="0"
        pidofproc >/dev/null || status="$?"
        
        if [ "$status" = 0 ]; then
            log_info_msg "$NAME is running"
        elif [ "$status" = 1 ]; then
            log_info_msg "$NAME is NOT running"
        else
            log_error_msg "could not access PID file $(cat $PIDFILE) for $NAME"		
        fi
	
        exit $status
        ;;
  *)
        echo "Usage: /etc/init.d/99dnscrypt {start|stop|status}" >&2
        exit 2
  ;;
esac

exit 0
