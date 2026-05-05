FROM alpine:3.23.4

ARG POWERSHELL_VERSION=7.6.1
ARG TARGETARCH

RUN apk add --no-cache \
    ca-certificates \
    less \
    ncurses-terminfo-base \
    krb5-libs \
    libgcc \
    libintl \
    libssl3 \
    libstdc++ \
    tzdata \
    userspace-rcu \
    zlib \
    icu-libs \
    curl \
    lttng-ust && \
    # arm64 has no musl build; use glibc build + gcompat shim
    if [ "$TARGETARCH" = "arm64" ]; then apk add --no-cache gcompat; fi && \
    ARCH=$([ "$TARGETARCH" = "arm64" ] && echo "arm64" || echo "musl-x64") && \
    curl -sSL "https://github.com/PowerShell/PowerShell/releases/download/v${POWERSHELL_VERSION}/powershell-${POWERSHELL_VERSION}-linux-${ARCH}.tar.gz" \
        -o /tmp/powershell.tar.gz && \
    mkdir -p /opt/microsoft/powershell/7 && \
    tar -zxf /tmp/powershell.tar.gz -C /opt/microsoft/powershell/7 && \
    chmod +x /opt/microsoft/powershell/7/pwsh && \
    ln -s /opt/microsoft/powershell/7/pwsh /usr/bin/pwsh && \
    rm /tmp/powershell.tar.gz
