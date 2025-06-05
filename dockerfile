# Build stage
FROM --platform=$BUILDPLATFORM mcr.microsoft.com/powershell:7.5-debian-12 AS builder

# Install required utilities for file operations and dependency installation
RUN apt-get update && \
    apt-get install -y curl ca-certificates unzip && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# Create app directory
WORKDIR /app

# Install kubectl and kubelogin
RUN curl -LO "https://dl.k8s.io/release/$(curl -Ls https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl" && \
    install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl && \
    # Install kubelogin
    curl -LO "https://github.com/Azure/kubelogin/releases/download/v0.2.7/kubelogin-linux-amd64.zip" && \
    unzip kubelogin-linux-amd64.zip && \
    install -o root -g root -m 0755 bin/linux_amd64/kubelogin /usr/local/bin/kubelogin && \
    # Clean up
    rm -f kubectl kubelogin-linux-amd64.zip && \
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
Install-Module -Name powershell-yaml,PSAI -Scope AllUsers -Force

# Copy KubeBuddy module files
COPY --chown=10001:10001 KubeBuddy.psm1 /usr/local/share/powershell/Modules/KubeBuddy/KubeBuddy.psm1
COPY --chown=10001:10001 KubeBuddy.psd1 /usr/local/share/powershell/Modules/KubeBuddy/KubeBuddy.psd1
COPY --chown=10001:10001 Private /usr/local/share/powershell/Modules/KubeBuddy/Private
COPY --chown=10001:10001 Public /usr/local/share/powershell/Modules/KubeBuddy/Public

# Copy run script
COPY --chown=10001:10001 run.ps1 /app/run.ps1

# Final image
FROM --platform=$BUILDPLATFORM mcr.microsoft.com/powershell:7.5-debian-12

RUN apt-get update && \
    apt-get install -y ca-certificates && \
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