ARG GO_VERSION=1.21
ARG ALPINE_VERSION=3.18
ARG XX_VERSION=1.3.0

ARG QEMU_VERSION=HEAD
ARG QEMU_REPO=https://github.com/Loongson-Cloud-Community/binfmt/releases/download/deploy%2Fv8.0.4-33/qemu-7.2.6-anolis.tar.gz

# xx is a helper for cross-compilation
FROM lcr.loongnix.cn/library/tonistiigi/xx:latest AS xx

FROM lcr.loongnix.cn/library/debian:sid AS src
RUN apt update && apt install -y git patch

WORKDIR /src
ARG QEMU_VERSION
ARG QEMU_REPO
#RUN git clone $QEMU_REPO && cd qemu && git checkout $QEMU_VERSION
COPY patches patches
# QEMU_PATCHES defines additional patches to apply before compilation
COPY qemu qemu
#RUN wget $QEMU_REPO && tar -zxvf qemu-7.2.6-anolis.tar.gz && mv qemu-7.2.6 qemu
ARG QEMU_PATCHES=cpu-max-arm
# QEMU_PATCHES_ALL defines all patches to apply before compilation
ARG QEMU_PATCHES_ALL=${QEMU_PATCHES},alpine-patches,anolis
ARG QEMU_PRESERVE_ARGV0
COPY start.sh .
RUN chmod +x start.sh
RUN ./start.sh && QEMU_PATCHES_ALL="${QEMU_PATCHES_ALL},preserve-argv0" \
      && rm start.sh && cd qemu
COPY next.sh .
#RUN chmod +x next.sh &&./next.sh && rm next.sh && cd qemu 
RUN chmod +x next.sh &&./next.sh && rm next.sh && cd qemu && scripts/git-submodule.sh update ui/keycodemapdb tests/fp/berkeley-testfloat-3 tests/fp/berkeley-softfloat-3 dtc slirp 
#    mkdir -p /usr/include/standard-headers && \
#    cp -r ./include/standard-headers/* /usr/include/standard-headers && \
#    mkdir -p /usr/include/linux-headers && \
 #   cp -r ./linux-headers/* /usr/include/linux-headers


#FROM lcr.loongnix.cn/library/debian:sid AS base
#RUN apk add --no-cache git clang python3 llvm make ninja pkgconfig  pkgconf glib-dev gcc musl-dev perl bash
RUN apt update && apt install -y git clang python3 llvm make ninja-build pkg-config pkgconf libglib2.0-dev gcc libc6-dev perl bash
COPY --from=xx / /
ENV PATH=/src/qemu/install-scripts:$PATH
#ENV PATH=/qemu/install-scripts:$PATH
WORKDIR /qemu
WORKDIR /src/qemu

ARG TARGETPLATFORM
#RUN apk add --no-cache binutils musl-dev gcc glib-dev glib-static linux-headers zlib-static
RUN apt update && apt install -y clang lld-16 binutils gcc libglib2.0-dev linux-headers-6.5.0-3-common zlib1g-dev && ln -s /usr/bin/lld-16 /usr/bin/lld
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
RUN chmod +x configure_qemu.sh && apt update && apt install -y clang gcc 
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

FROM lcr.loongnix.cn/library/golang:1.21-alpine AS binfmt
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

FROM lcr.loongnix.cn/library/tonistiigi/bats-assert:latest AS assert

FROM  lcr.loongnix.cn/library/alpine:v3.18-base AS alpine-crossarch

RUN apk add --no-cache bash

# Runs on the build platform without emulation, but we need to get hold of the cross arch busybox binary
COPY busybox.static /bin/
COPY crossarch.sh .
RUN chmod +x crossarch.sh && bash crossarch.sh

# buildkit-test runs test suite for buildkit embedded QEMU
FROM lcr.loongnix.cn/library/golang:1.21-alpine AS buildkit-test
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
VOLUME /tmp

