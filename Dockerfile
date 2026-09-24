# syntax=docker/dockerfile:1
# The matching non-dev 22.11.0 tag is currently unavailable. Use the same
# verified, multi-platform base for compilation and runtime to preserve ABI.
ARG ASTERISK_BASE=ghcr.io/andrius/asterisk:22.11.0_debian-trixie-dev@sha256:c275365e7db0ed4db6fe1c262c3c289e6ae97624ce0c0cb1c9dc7bbeb5a61606
FROM ${ASTERISK_BASE} AS builder
ARG ASTERISK_VERSION=22.11.0
ARG QUECTEL_REF=005f74f11a8bac5102e17a6d092136f20336f4db
USER root
RUN apt-get update && apt-get install -y --no-install-recommends \
    git ca-certificates autoconf automake libtool pkg-config build-essential \
    libasound2-dev libsqlite3-dev \
    && rm -rf /var/lib/apt/lists/*
WORKDIR /usr/src/chan-quectel
RUN git init . \
    && git remote add origin https://github.com/biaide/asterisk-chan-quectel.git \
    && git fetch --depth 1 origin "${QUECTEL_REF}" \
    && git checkout --detach FETCH_HEAD \
    && test "$(git rev-parse HEAD)" = "${QUECTEL_REF}"
RUN test "$(asterisk -V)" = "Asterisk ${ASTERISK_VERSION}" \
    && mkdir -p /out \
    && ./bootstrap \
    && ./configure --with-astversion="${ASTERISK_VERSION}" \
        --with-asterisk=/usr/include DESTDIR=/out \
    && make -j"$(nproc)" \
    && make install \
    && test -s /out/chan_quectel.so

FROM ${ASTERISK_BASE} AS runtime
USER root
RUN apt-get update && apt-get install -y --no-install-recommends \
    alsa-utils libasound2t64 libsqlite3-0 \
    && rm -rf /var/lib/apt/lists/*
COPY --from=builder /out/chan_quectel.so /usr/lib/asterisk/modules/chan_quectel.so
RUN asterisk -V \
    && ldd /usr/lib/asterisk/modules/chan_quectel.so > /tmp/quectel-ldd.txt \
    && cat /tmp/quectel-ldd.txt \
    && ! grep -q 'not found' /tmp/quectel-ldd.txt \
    && rm /tmp/quectel-ldd.txt
LABEL org.opencontainers.image.title="Asterisk EC20" \
    org.opencontainers.image.description="Asterisk 22.11.0 with pinned chan_quectel and ALSA UAC support" \
    org.opencontainers.image.source="https://github.com/lhkuan/asterisk-ec20"
# Explicit startup avoids inherited user switching that loses host device groups.
# Compose supplies the actual serial/audio GIDs and runs as the asterisk UID.
ENTRYPOINT ["/usr/sbin/asterisk"]
CMD ["-f", "-vvv", "-n"]
