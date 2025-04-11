# Build stage: Use Ubuntu 24.04 for setup
FROM mcr.microsoft.com/powershell:7.5-ubuntu-24.04 AS builder

# Install required utilities for file operations and dependency installation
RUN apt-get update && \
    apt-get install -y adduser coreutils && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# Create app directory
WORKDIR /app

# Install dependencies: curl (for kubectl and kubelogin), unzip (for kubelogin), Azure CLI, and ca-certificates
RUN apt-get update && \
    apt-get install -y curl ca-certificates unzip && \
    # Install kubectl (stable release)
    curl -LO "https://dl.k8s.io/release/$(curl -Ls https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl" && \
    install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl && \
    # Install kubelogin (latest release as of April 2025, or specify a version like v0.1.0)
    curl -LO "https://github.com/Azure/kubelogin/releases/download/v0.2.7/kubelogin-linux-amd64.zip" && \
    unzip kubelogin-linux-amd64.zip && \
    install -o root -g root -m 0755 bin/linux_amd64/kubelogin /usr/local/bin/kubelogin && \
    # Install Azure CLI
    curl -sL https://aka.ms/InstallAzureCLIDeb | bash && \
    # Clean up
    rm -f kubectl kubelogin-linux-amd64.zip && \
    rm -rf bin && \
    apt-get remove -y curl unzip && \
    apt-get autoremove -y && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# Install powershell-yaml module for ConvertFrom-Yaml
RUN pwsh -Command "Install-Module -Name powershell-yaml -Force -Scope AllUsers -AcceptLicense -SkipPublisherCheck"

# Create Reports directory and set permissions for UID/GID 10001
RUN mkdir -p /app/Reports && \
    chown -R 10001:10001 /app/Reports && \
    chmod -R 775 /app/Reports

# Create the module directory and set permissions for UID/GID 10001
RUN mkdir -p /usr/local/share/powershell/Modules/KubeBuddy && \
    chown -R 10001:10001 /usr/local/share/powershell/Modules/KubeBuddy

# Copy the KubeBuddy module files from the Git repo root to the module directory
COPY --chown=10001:10001 KubeBuddy.psm1 /usr/local/share/powershell/Modules/KubeBuddy/
COPY --chown=10001:10001 KubeBuddy.psd1 /usr/local/share/powershell/Modules/KubeBuddy/
COPY --chown=10001:10001 Private /usr/local/share/powershell/Modules/KubeBuddy/Private
COPY --chown=10001:10001 Public /usr/local/share/powershell/Modules/KubeBuddy/Public

# Copy the run script
COPY --chown=10001:10001 run.ps1 /app/run.ps1

# Runtime stage: Use Ubuntu 24.04 for the final image
FROM mcr.microsoft.com/powershell:7.5-ubuntu-24.04

# Install runtime dependencies: ca-certificates (for HTTPS requests)
RUN apt-get update && \
    apt-get install -y ca-certificates && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# Create app directory and non-root user
WORKDIR /app
RUN groupadd --gid 10001 kubeuser && \
    useradd --uid 10001 --gid kubeuser --shell /bin/false kubeuser && \
    # Create home directory for kubeuser
    mkdir -p /home/kubeuser/.kube && \
    chown -R kubeuser:kubeuser /home/kubeuser

# Copy artifacts from the build stage
COPY --from=builder /usr/local/bin/kubectl /usr/local/bin/kubectl
COPY --from=builder /usr/local/bin/kubelogin /usr/local/bin/kubelogin
COPY --from=builder /usr/bin/az /usr/bin/az
COPY --from=builder /opt/az /opt/az
COPY --from=builder /usr/local/share/powershell/Modules/powershell-yaml /usr/local/share/powershell/Modules/powershell-yaml
COPY --from=builder /usr/local/share/powershell/Modules/KubeBuddy /usr/local/share/powershell/Modules/KubeBuddy
COPY --from=builder /app/run.ps1 /app/run.ps1
COPY --from=builder /app/Reports /app/Reports

# Ensure the Reports directory has the correct permissions
RUN chown -R kubeuser:kubeuser /app/Reports && \
    chmod -R 775 /app/Reports

# Switch to non-root user
USER kubeuser

# Run default script
CMD ["pwsh", "/app/run.ps1"]