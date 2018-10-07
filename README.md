## Features
- arm, arm64, x86 and x86_64 are supported.
- ipv4 and ipv6?(not tested) are supported.
- All binary files are downloaded from [https://github.com/jedisct1/dnscrypt-proxy/releases](https://github.com/jedisct1/dnscrypt-proxy/releases)

-f | --force  reboot during startup if something went wrong

-s | --no-lists disables the check for list of public DNS resolvers

<sup>When used only static server sources</sup>

-r | --resolv_path  path to new public DNS resolvers (public-resolvers.md.minisig)<br>

To forced update the list of resolvers needed to remove the timestamp from the minisign private key (*.md.minisig).

<sup>Lists older than 4 days are not accepted.</sup>

```
/system/etc/init.d/99dnscrypt.sh start -f --resolv_path /sdcard/dnscrypt-proxy/
```

## Configuration
- Configuration located on `/system/etc/dnscrypt-proxy/dnscrypt-proxy.toml`
- For more detailed configuration please refer to [official documentation](https://github.com/jedisct1/dnscrypt-proxy/wiki/Basic-dnscrypt-proxy.toml-editing)
- Iptable rules located on `/system/etc/dnscrypt-proxy/iptables-rules`

## AFWall+ (Android Firewall+)
Custom startup script
--------
```
. /system/etc/init.d/99dnscrypt.sh start &
```
Custom shutdown script
--------
```
. /system/etc/init.d/99dnscrypt.sh stop &
```
