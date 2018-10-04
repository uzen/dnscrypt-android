#!/sbin/sh 

# Add files to folder with the name of architecture
# vendor/ armeabi armeabi-v7a arm64-v8a x86 x86_64 ...

ARCH=$(grep ro.product.cpu.abi= /system/build.prop | cut -d "=" -f 2);

# /system/xbin/dnscrypt-proxy
BINARY_PATH=vendor/$ARCH/xbin/dnscrypt-proxy
if [ -f /tmp/$BINARY_PATH ]; then
    cp -af /tmp/$BINARY_PATH /system/xbin
fi