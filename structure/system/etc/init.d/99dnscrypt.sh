#!/system/bin/sh

# /etc/init.d/99dnscrypt: start and stop the dnscrypt daemon

set -e

NAME=dnscrypt-proxy
DAEMON=/system/xbin/$NAME
PIDDIR=/data/local/tmp/dnscrypt
PIDFILE=$PIDDIR/dnscrypt-proxy.pid
LOCKFILE=$PIDDIR/dnscrypt-proxy.lock
CONFIG_FILE=/system/etc/dnscrypt-proxy/dnscrypt-proxy.toml
WAITFORDAEMON=30
DESC="dns client proxy"


. /system/etc/dnscrypt-proxy/iptables-rules

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

get_prop () {
	sed -n 's/^'$1'=\(.*\)$/\1/p' $LOCKFILE 2>/dev/null
}

set_prop () {
	if [ -n "${2:-}" ]; then
		[ -s $LOCKFILE ] || printf "#$NAME: lock file\n" > $LOCKFILE
		sed -i -e '/^\('$1'=\).*/{s//\1'$2'/;:a;n;ba;q}' \
   		 -e '$a'$1'='$2'' $LOCKFILE 2>/dev/null
	fi
}

check_health () {           
   if test -s "$LOCKFILE"; then
		if [ "$(get_prop 'dnscrypt-resolvers')" = "none" ]; then
			configdir=`dirname "$CONFIG_FILE"`
			resolvers="public-resolvers.md"
			minisig="$resolvers.minisig"
	                
			timestamp=$(date +%s)
			timegen=$(sed -n 's/.*timestamp:*\([0-9]\{1,\}\).*/\1/p' $configdir/$minisig )
	   	
			let "_time=(timestamp-timegen)/3600"
	   	
	   	log_debug_msg "configuration of server sources:"
	   	if [ $_time -lt 72 ]; then # updated every 3 days
	   		log_debug_msg "copy $resolvers to $PIDDIR..."
	      	cp $configdir/{$resolvers,$minisig} $PIDDIR/
	      else
	      	intdir=/sdcard/$NAME
	      	if [ -e "$intdir/$resolvers" -o -e "$intdir/$minisig" ]; then
	      		log_debug_msg "copy $intdir/$resolvers to $PIDDIR..."
	      		cp $intdir/{$resolvers,$minisig} $PIDDIR/
	      	else
	      		log_debug_msg "$intdir/$resolvers(.minisig): file not found"
	      	fi
	      fi
	   fi
	            
	   if [ "$(get_prop 'ipv4-enabled')" = "false" ]; then
	      log_debug_msg "ipv4_addr_unlock: enable IPv4"
	      ipv4_addr_unlock
	   fi
	            
	   rm -f $LOCKFILE
   fi
}

status_of_proc () {
	_daemon="$1"
	_pidfile="$2"
	
	[ -n "${_pidfile:-}" ] || _pidfile=$PIDFILE
	
	if [ -e "$_pidfile" ] && [ -r "$_pidfile" ]; then
		read pid < "$_pidfile"
		if [ -n "${pid:-}" ]; then
			if $(kill -0 "${pid:-}" 2> /dev/null); then
             echo "$pid" || true
             return 0
         elif ps "${pid:-}" >/dev/null 2>&1; then
             echo "$pid" || true
             return 0 # program is running, but not owned by this user
         else
             return 2 # program is dead and pid file exists
         fi
      fi
   else
      if ps | grep "$_daemon" >/dev/null 2>&1; then
   		return 0
   	fi
   	return 1
   fi
	return 3 # Unable to determine status
}

wait_for_daemon () {   
   status_of_proc "$NAME" || return $?
   
	_timeout=0
	while :; do
		let _timeout=$_timeout+1
		
		[ $_timeout -gt $WAITFORDAEMON ] && return 10
		[ -e $PIDDIR/*.md ] && break
		
		let "_progress=(_timeout*100/WAITFORDAEMON*100)/100"
		let "_done=(_progress*4)/10"
		let _left=40-$_done
		
		fill=$(printf "%${_done}s")
		empty=$(printf "%${_left}s")
		printf "\r[${fill// /\#}${empty// /-}] ${_progress}%%"
		
		sleep 1
	done
}

case "$1" in
  start) log_debug_msg "starting $DESC $NAME"
  
        if test ! -s "$CONFIG_FILE"; then
            log_debug_msg "missing config file $CONFIG_FILE"
            exit 0
        fi
        
        mkdir -p -m 01755 "$PIDDIR" 2>/dev/null || \
            { log_debug_msg "cannot access $PIDDIR directory, are you root?"; exit 1 ; }
            
        check_health
	
        if status_of_proc "$NAME" 
        then
            log_debug_msg "$DESC already started"
            exit 0
        fi
	
        nohup $DAEMON -config $CONFIG_FILE \
            -pidfile=$PIDFILE > /dev/null 2>&1 &
        pid=$! && printf "$pid\n" > $PIDFILE
        
        status="0"
        wait_for_daemon || status="$?"
                
        case "$status" in
          0|10) # ok
                log_debug_msg "enabling iptables firewall rules"
                do_iptables_rules 0
                if [ "$status" = 10 ]; then
                    log_error_msg "the resolvers file couldn't be uploaded?"
                    set_prop 'dnscrypt-resolvers' 'none'
                    exit 10
                fi
                ;;
          *) # offline	
                log_error_msg "ipv4_addr_lock: disable IPv4"
                ipv4_addr_lock && $(set_prop 'ipv4-enabled' 'false')
                exit 1
                ;;
        esac
        ;;
  stop) log_debug_msg "stopping $DESC $NAME"
        
        status="0"
        status_of_proc "$NAME" || status="$?"
	
        if [ "$status" = 0 ]; then
            pid=`cat $PIDFILE 2>/dev/null` || true
		
            if kill $pid 2>/dev/null; then
                log_debug_msg "disabling iptables firewall rules"
                do_iptables_rules 1
            else 
                log_debug_msg "Is $pid not $NAME? Is $DAEMON a different binary now?"
            fi
            
            log_debug_msg "Removing stale PID file $PIDFILE"
            rm -f $PIDFILE
        elif [ "$status" = 3 ]; then
            log_debug_msg "not running - there is no $PIDFILE"
            killall $NAME >/dev/null 2>&1
		
            exit 1
        fi
        ;;
  status)
        status="0"
        status_of_proc "$NAME" || status="$?"
        
        case "$status" in
          0) log_debug_msg "$NAME is running" ;;
          1) log_debug_msg "$NAME is NOT running" ;;
          2) log_error_msg "program is dead and pid file exists" ;;
          *) log_error_msg "could not access PID file $PIDFILE for $NAME" ;;
        esac
	
        exit $status
        ;;
  *)
        echo "Usage: /etc/init.d/99dnscrypt {start|stop|status}" >&2
        exit 1
  ;;
esac

exit 0
