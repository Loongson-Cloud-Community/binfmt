#!/bin/sh

set -eux
  #echo "$PWD"
  cd qemu 
  #echo "$PWD"
  for p in $(echo $QEMU_PATCHES_ALL | tr ',' '\n'); do
    for f in  ../patches/$p/*.patch; do echo "apply $f"; patch -p1 < $f; done
  done
  #ls $PWD/scripts

