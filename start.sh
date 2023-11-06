#!/bin/sh

set -eux
   commit=""
   rmlist=""
   if [ "${QEMU_PATCHES_ALL#*alpine-patches}" != "${QEMU_PATCHES_ALL}" ]; then
    ver="$(cat qemu/VERSION)"
    for l in $(cat patches/aports.config); do
      pver=$(echo $l | cut -d, -f1)
      if [ "${ver%.*}" = "7.2.6" ]; then
        commit=$(echo $l | cut -d, -f2)
        rmlist=$(echo $l | cut -d, -f3)
        break
      fi
    done
    mkdir -p aports && cd aports && git init
    https_proxy=http://10.130.0.20:7890 git fetch --depth 1 https://github.com/alpinelinux/aports.git "ed7a3122a32f53094f51e55abe68d416910e01ad"
    git checkout FETCH_HEAD
    mkdir -p ../patches/alpine-patches
    for f in $(echo $rmlist | tr ";" "\n"); do
      rm community/qemu/*${f}*.patch || true
    done
    cp -a community/qemu/*.patch ../patches/alpine-patches/
    cd - && rm -rf aports
  fi

