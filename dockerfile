# Use a known-valid PowerShell base tag.
ARG POWERSHELL_IMAGE=mcr.microsoft.com/powershell:7.5-debian-12
ARG KUBECTL_VERSION=v1.35.1
ARG KUBELOGIN_VERSION=v0.2.15

# Build stage
FROM --platform=$TARGETPLATFORM ${POWERSHELL_IMAGE} AS builder

ARG TARGETARCH
ARG KUBECTL_VERSION
ARG KUBELOGIN_VERSION

# Install required utilities for file operations and dependency installation
RUN apt-get update && \
    apt-get upgrade -y && \
    apt-get install -y --no-install-recommends curl ca-certificates unzip && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# Create app directory
WORKDIR /app

# Install kubectl and kubelogin (arch-aware for multi-arch builds)
RUN curl -LO "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/${TARGETARCH}/kubectl" && \
    install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl && \
    # Install kubelogin
    curl -LO "https://github.com/Azure/kubelogin/releases/download/${KUBELOGIN_VERSION}/kubelogin-linux-${TARGETARCH}.zip" && \
    unzip "kubelogin-linux-${TARGETARCH}.zip" && \
    install -o root -g root -m 0755 "bin/linux_${TARGETARCH}/kubelogin" /usr/local/bin/kubelogin && \
    # Clean up
    rm -f "kubectl" "kubelogin-linux-${TARGETARCH}.zip" && \
    rm -rf bin && \
    apt-get remove -y curl unzip && \
    apt-get autoremove -y && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# Create directories and set permissions for UID/GID 10001
RUN mkdir -p /app/Reports && \
    mkdir -p /usr/local/share/powershell/Modules/KubeBuddy && \
    chown -R 10001:10001 /app/Reports /usr/local/share/powershell/Modules/KubeBuddy && \
    chmod -R 775 /app/Reports

# Install powershell-yaml module
RUN pwsh -Command "Set-PSRepository -Name 'PSGallery' -InstallationPolicy Trusted; \
Install-Module -Name powershell-yaml,PSAI -Scope AllUsers -Force"

# Copy KubeBuddy module files
COPY --chown=10001:10001 KubeBuddy.psm1 /usr/local/share/powershell/Modules/KubeBuddy/KubeBuddy.psm1
COPY --chown=10001:10001 KubeBuddy.psd1 /usr/local/share/powershell/Modules/KubeBuddy/KubeBuddy.psd1
COPY --chown=10001:10001 Private /usr/local/share/powershell/Modules/KubeBuddy/Private
COPY --chown=10001:10001 Public /usr/local/share/powershell/Modules/KubeBuddy/Public

# Copy run script
COPY --chown=10001:10001 run.ps1 /app/run.ps1

# Final image
FROM --platform=$TARGETPLATFORM ${POWERSHELL_IMAGE}

RUN apt-get update && \
    apt-get upgrade -y && \
    apt-get install -y --no-install-recommends ca-certificates && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

WORKDIR /app
RUN groupadd --gid 10001 kubeuser && \
    useradd --uid 10001 --gid kubeuser --shell /bin/false kubeuser && \
    mkdir -p /home/kubeuser/.kube && \
    chown -R kubeuser:kubeuser /home/kubeuser && \
    chmod -R 770 /home/kubeuser/.kube

# Set KUBECONFIG to default location
ENV KUBECONFIG=/home/kubeuser/.kube/config

# Copy binaries, modules, and files from builder
COPY --from=builder /usr/local/bin/kubectl /usr/local/bin/kubectl
COPY --from=builder /usr/local/bin/kubelogin /usr/local/bin/kubelogin
COPY --from=builder /usr/local/share/powershell/Modules/powershell-yaml /usr/local/share/powershell/Modules/powershell-yaml
COPY --from=builder /usr/local/share/powershell/Modules/PSAI /usr/local/share/powershell/Modules/PSAI
COPY --from=builder /usr/local/share/powershell/Modules/KubeBuddy /usr/local/share/powershell/Modules/KubeBuddy
COPY --from=builder /app/run.ps1 /app/run.ps1
COPY --from=builder /app/Reports /app/Reports

# Fix permissions
RUN chown -R kubeuser:kubeuser /app/Reports && \
    chmod -R 775 /app/Reports

# Switch to non-root user
USER kubeuser

ENV TERM=xterm

# Entry point
CMD ["pwsh", "/app/run.ps1"]
