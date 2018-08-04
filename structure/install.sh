#!/sbin/sh

# Variables
ARCH=$(grep ro.product.cpu.abi= /system/build.prop | cut -d "=" -f 2);

if [ $ARCH == armeabi-v7a ]; then
 	cp -af /tmp/binary-arm/dnscrypt-proxy /system/xbin
elif [ $ARCH == arm64-v8a ]; then
 	cp -af /tmp/binary-arm64/dnscrypt-proxy /system/xbin
fi

