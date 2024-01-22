ARG GO_VERSION=1.21
ARG ALPINE_VERSION=3.18
ARG XX_VERSION=1.3.0

ARG QEMU_VERSION=tcg-old
ARG QEMU_REPO=https://github.com/loongson/qemu

# xx is a helper for cross-compilation
FROM cr.loongnix.cn/tonistiigi/xx:1.3.0 AS xx

FROM cr.loongnix.cn/library/debian:buster AS src
RUN apt update && apt install -y git patch

WORKDIR /src
ARG QEMU_VERSION
ARG QEMU_REPO
COPY patches patches
# QEMU_PATCHES defines additional patches to apply before compilation
#COPY qemu qemu
RUN git clone -b $QEMU_VERSION --depth 1 $QEMU_REPO
ARG QEMU_PATCHES=cpu-max-arm
# QEMU_PATCHES_ALL defines all patches to apply before compilation
RUN  cd qemu
COPY next.sh .
RUN chmod +x next.sh &&./next.sh && rm next.sh 
RUN https_proxy=http://10.130.0.20:7890 cd qemu && scripts/git-submodule.sh update ui/keycodemapdb tests/fp/berkeley-testfloat-3 tests/fp/berkeley-softfloat-3 dtc slirp 


#FROM lcr.loongnix.cn/library/debian:sid AS base
#RUN apk add --no-cache git clang python3 llvm make ninja pkgconfig  pkgconf glib-dev gcc musl-dev perl bash
RUN apt update && apt install -y git clang python3 llvm make ninja-build pkgconf libglib2.0-dev gcc libc6-dev perl bash
RUN apt install -y pkg-config
COPY --from=xx / /
ENV PATH=/src/qemu/install-scripts:$PATH
#ENV PATH=/qemu/install-scripts:$PATH
WORKDIR /qemu
WORKDIR /src/qemu

ARG TARGETPLATFORM
#RUN apk add --no-cache binutils musl-dev gcc glib-dev glib-static linux-headers zlib-static
RUN apt update && apt install -y clang lld binutils gcc libglib2.0-dev zlib1g-dev
RUN set -e; \
  [ "$(xx-info arch)" = "ppc64le" ] && XX_CC_PREFER_LINKER=ld xx-clang --setup-target-triple; \
  [ "$(xx-info arch)" = "386" ] && XX_CC_PREFER_LINKER=ld xx-clang --setup-target-triple; \
  true

#FROM base AS build
ARG TARGETPLATFORM
# QEMU_TARGETS sets architectures that emulators are built for (default all)
ARG QEMU_VERSION QEMU_TARGETS
ENV AR=llvm-ar STRIP=llvm-strip
RUN cp -r /src/qemu/include/standard-headers /usr/include/  && \
    cp -r /src/qemu/linux-headers /usr/include/
ADD scripts/configure_qemu.sh.bak configure_qemu.sh
RUN chmod +x configure_qemu.sh && apt update && apt install -y clang gcc bison flex 
#RUN --mount=target=.,from=src,src=/src/qemu,rw --mount=target=./install-scripts,src=scripts \
#TARGETPLATFORM=${TARGETPLATFORM} ./configure && \
RUN TARGETPLATFORM=${TARGETPLATFORM} ./configure_qemu.sh && \
    make -j "$(getconf _NPROCESSORS_ONLN)" && \
    make install && \
    cd /usr/bin  
RUN rm -rf /usr/bin/qemu-loongarch64
#cd /usr/bin && for f in $(ls qemu-*); do xx-verify --static $f; done

ARG BINARY_PREFIX
RUN cd /usr/bin; [ -z "$BINARY_PREFIX" ] || for f in $(ls qemu-*); do ln -s $f $BINARY_PREFIX$f; done

FROM cr.loongnix.cn/library/golang:1.20-alpine AS binfmt
COPY --from=xx / /
ENV CGO_ENABLED=0
ARG TARGETPLATFORM
ARG QEMU_VERSION
WORKDIR /src
RUN apk add --no-cache git
RUN --mount=target=. \
  TARGETPLATFORM=$TARGETPLATFORM go build \
    -ldflags "-X main.revision=$(git rev-parse --short HEAD) -X main.qemuVersion=${QEMU_VERSION}" \
    -o /go/bin/binfmt ./cmd/binfmt 

FROM src AS build-archive
#FROM build AS build-archive
COPY --from=binfmt /go/bin/binfmt /usr/bin/binfmt
RUN cd /usr/bin && mkdir -p /archive && \
  tar czvfh "/archive/${BINARY_PREFIX}qemu_${QEMU_VERSION}_$(echo $TARGETPLATFORM | sed 's/\//-/g').tar.gz" ${BINARY_PREFIX}qemu* && \
  tar czvfh "/archive/binfmt_$(echo $TARGETPLATFORM | sed 's/\//-/g').tar.gz" binfmt

# binaries contains only the compiled QEMU binaries
FROM scratch AS binaries
# BINARY_PREFIX sets prefix string to all QEMU binaries
ARG BINARY_PREFIX
#COPY --from=build usr/bin/${BINARY_PREFIX}qemu-* /
COPY --from=src usr/bin/${BINARY_PREFIX}qemu-* /
# archive returns the tarball of binaries
FROM scratch AS archive
COPY --from=build-archive /archive/* /

FROM cr.loongnix.cn/tonistiigi/bats-assert:latest AS assert

FROM  cr.loongnix.cn/library/alpine:3.11 AS alpine-crossarch

RUN apk add --no-cache bash

# Runs on the build platform without emulation, but we need to get hold of the cross arch busybox binary
COPY busybox.static /bin/
COPY crossarch.sh .
RUN chmod +x crossarch.sh && bash crossarch.sh

# buildkit-test runs test suite for buildkit embedded QEMU
FROM cr.loongnix.cn/library/golang:1.20-alpine AS buildkit-test
RUN apk add --no-cache bash bats
WORKDIR /work
COPY --from=assert . .
COPY test .
COPY --from=binaries / /usr/bin
COPY --from=alpine-crossarch /crossarch /crossarch/
RUN ./run.sh

# image builds binfmt installation image 
FROM scratch AS image
COPY --from=binaries / /usr/bin/
COPY --from=binfmt /go/bin/binfmt /usr/bin/binfmt
# QEMU_PRESERVE_ARGV0 defines if argv0 is used to set the binary name
ARG QEMU_PRESERVE_ARGV0
ENV QEMU_PRESERVE_ARGV0=${QEMU_PRESERVE_ARGV0}
#CMD [ "/bin/bash" ]
ENTRYPOINT [ "/usr/bin/binfmt" ]
#VOLUME /tmp

