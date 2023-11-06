#!/bin/sh

set -euo pipefall

mkdir -p /crossarch/bin /crossarch/usr/bin
mv /bin/busybox.static /crossarch/bin/
for i in $(echo /bin/*; echo /usr/bin/*); do
    if [[ $(readlink -f "$i") != *busybox* ]]; then
       continue
    fi
    ln -s /crossarch/bin/busybox.static /crossarch$i
done
