# syntax=docker/dockerfile:1
FROM debian:trixie-slim AS builder
ARG ASTERISK_VERSION=22.11.0
ARG ASTERISK_SHA256=3bd5ee040509a3d3cd9b1ba9520c18e6ec0a7e7981ca68c457dcd36ba3c54d94
ARG QUECTEL_REF=005f74f11a8bac5102e17a6d092136f20336f4db
RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential autoconf automake libtool pkg-config git curl ca-certificates \
    bzip2 patch python3 libedit-dev libjansson-dev libsqlite3-dev libssl-dev \
    libxml2-dev uuid-dev libncurses-dev libasound2-dev libcurl4-openssl-dev \
    libspeex-dev libspeexdsp-dev libopus-dev \
    && rm -rf /var/lib/apt/lists/*
WORKDIR /usr/src/asterisk
RUN curl -fsSL --retry 3 "https://downloads.asterisk.org/pub/telephony/asterisk/releases/asterisk-${ASTERISK_VERSION}.tar.gz" -o /tmp/asterisk.tar.gz \
    && echo "${ASTERISK_SHA256}  /tmp/asterisk.tar.gz" | sha256sum -c - \
    && tar -xzf /tmp/asterisk.tar.gz --strip-components=1 \
    && rm /tmp/asterisk.tar.gz
RUN ./configure --prefix=/usr --libdir=/usr/lib --sysconfdir=/etc \
        --localstatedir=/var --with-pjproject-bundled \
    && make menuselect.makeopts \
    && menuselect/menuselect --disable BUILD_NATIVE --disable-category MENUSELECT_CORE_SOUNDS \
        --disable-category MENUSELECT_MOH --disable-category MENUSELECT_EXTRA_SOUNDS menuselect.makeopts \
    && make -j"$(nproc)" \
    && make install \
    && make samples \
    && asterisk -V
WORKDIR /usr/src/chan-quectel
RUN git init . \
    && git remote add origin https://github.com/biaide/asterisk-chan-quectel.git \
    && git fetch --depth 1 origin "${QUECTEL_REF}" \
    && git checkout --detach FETCH_HEAD \
    && test "$(git rev-parse HEAD)" = "${QUECTEL_REF}" \
    && ./bootstrap \
    && ./configure --with-astversion="${ASTERISK_VERSION}" --with-asterisk=/usr/src/asterisk/include DESTDIR=/usr/lib/asterisk/modules \
    && make -j"$(nproc)" && make install

FROM debian:trixie-slim AS runtime
RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates tzdata alsa-utils libasound2t64 libedit2 libjansson4 \
    libsqlite3-0 libssl3t64 libxml2 libuuid1 libncurses6 libcurl4t64 \
    libspeex1 libspeexdsp1 libopus0 \
    && rm -rf /var/lib/apt/lists/* \
    && groupadd -g 1000 asterisk \
    && useradd -u 1000 -g asterisk -m -d /home/asterisk asterisk
COPY --from=builder /usr/sbin/asterisk /usr/sbin/asterisk
COPY --from=builder /usr/lib/asterisk /usr/lib/asterisk
COPY --from=builder /usr/lib/libasterisk* /usr/lib/
COPY --from=builder /etc/asterisk /etc/asterisk
COPY --from=builder /var/lib/asterisk /var/lib/asterisk
RUN ldconfig \
    && mkdir -p /var/run/asterisk /var/log/asterisk /var/spool/asterisk \
    && chown -R asterisk:asterisk /etc/asterisk /var/lib/asterisk /var/run/asterisk /var/log/asterisk /var/spool/asterisk \
    && asterisk -V \
    && ldd /usr/lib/asterisk/modules/chan_quectel.so > /tmp/ldd.txt \
    && cat /tmp/ldd.txt && ! grep -q 'not found' /tmp/ldd.txt && rm /tmp/ldd.txt
LABEL org.opencontainers.image.title="Asterisk EC20" \
    org.opencontainers.image.version="22.11.0" \
    org.opencontainers.image.source="https://github.com/lhkuan/asterisk-ec20"
USER asterisk
WORKDIR /home/asterisk
HEALTHCHECK --interval=30s --timeout=10s --start-period=30s --retries=3 CMD asterisk -rx 'core show uptime' || exit 1
ENTRYPOINT ["/usr/sbin/asterisk"]
CMD ["-f", "-vvv", "-n"]
