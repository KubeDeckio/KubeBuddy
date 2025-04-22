# Build stage
FROM --platform=$BUILDPLATFORM mcr.microsoft.com/powershell:7.5-debian-11-slim AS builder

RUN apt-get update && \
    apt-get install -y curl unzip ca-certificates && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

WORKDIR /app

RUN pwsh -Command "Set-PSRepository -Name PSGallery -InstallationPolicy Trusted -ErrorAction Stop" && \
    pwsh -Command "Install-Module -Name powershell-yaml -Scope AllUsers -Force -ErrorAction Stop"

ARG TARGETARCH
RUN echo "Building for architecture: $TARGETARCH" && \
    curl -LO "https://dl.k8s.io/release/$(curl -Ls https://dl.k8s.io/release/stable.txt)/bin/linux/${TARGETARCH}/kubectl" && \
    install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl && \
    curl -LO "https://github.com/Azure/kubelogin/releases/download/v0.2.7/kubelogin-linux-${TARGETARCH}.zip" && \
    unzip kubelogin-linux-${TARGETARCH}.zip && \
    install -o root -g root -m 0755 bin/linux_${TARGETARCH}/kubelogin /usr/local/bin/kubelogin && \
    rm -f kubectl kubelogin-linux-${TARGETARCH}.zip && \
    rm -rf bin

RUN mkdir -p /app/Reports /usr/local/share/powershell/Modules/KubeBuddy && \
    chown -R 10001:10001 /app/Reports /usr/local/share/powershell/Modules/KubeBuddy && \
    chmod -R 775 /app/Reports

COPY --chown=10001:10001 KubeBuddy.psm1 /usr/local/share/powershell/Modules/KubeBuddy/
COPY --chown=10001:10001 KubeBuddy.psd1 /usr/local/share/powershell/Modules/KubeBuddy/
COPY --chown=10001:10001 Private Public /usr/local/share/powershell/Modules/KubeBuddy/
COPY --chown=10001:10001 run.ps1 /app/

# Final image
FROM --platform=$BUILDPLATFORM mcr.microsoft.com/powershell:7.5-debian-11-slim

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

ENV KUBECONFIG=/home/kubeuser/.kube/config
ENV TERM=xterm

COPY --from=builder /usr/local/bin/kubectl /usr/local/bin/kubectl
COPY --from=builder /usr/local/bin/kubelogin /usr/local/bin/kubelogin
COPY --from=builder /usr/local/share/powershell/Modules /usr/local/share/powershell/Modules
COPY --from=builder /app/run.ps1 /app/run.ps1
COPY --from=builder /app/Reports /app/Reports

RUN chown -R kubeuser:kubeuser /app/Reports && chmod -R 775 /app/Reports

USER kubeuser

CMD ["pwsh", "/app/run.ps1"]
