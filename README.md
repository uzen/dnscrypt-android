## AFWall+ (Android Firewall+)
Custom startup script
--------
```
﻿. /system/etc/init.d/99dnscrypt.sh start &
```
Custom shutdown script
--------
```
. /system/etc/init.d/99dnscrypt.sh stop &
```

-f | --force  
-r | --resolv_path  path to new public DNS resolvers (public-resolvers.md.minisig)

To forced update the list of public DNS resolvers needed to remove the timestamp from the minisign secret key (*.md.minisig).

<sup>Lists older than 4 days are not accepted.</sup>

```
/system/etc/init.d/99dnscrypt.sh start -f --resolv_path /sdcard/dnscrypt-proxy/
```