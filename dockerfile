ARG GO_IMAGE=golang:1.24.2-bookworm
ARG RUNTIME_IMAGE=debian:bookworm-slim
ARG KUBECTL_VERSION=v1.35.1
ARG KUBELOGIN_VERSION=v0.2.15

FROM ${GO_IMAGE} AS builder

ARG TARGETARCH

WORKDIR /src
COPY go.mod go.sum ./
RUN go mod download
COPY cmd ./cmd
COPY internal ./internal
COPY Private ./Private
COPY checks ./checks
RUN CGO_ENABLED=0 GOOS=linux GOARCH=${TARGETARCH} go build -o /out/kubebuddy ./cmd/kubebuddy

FROM ${RUNTIME_IMAGE}

ARG TARGETARCH
ARG KUBECTL_VERSION
ARG KUBELOGIN_VERSION

RUN apt-get update && \
    apt-get install -y --no-install-recommends ca-certificates curl unzip && \
    rm -rf /var/lib/apt/lists/*

RUN curl -fsSL "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/${TARGETARCH}/kubectl" -o /usr/local/bin/kubectl && \
    chmod 0755 /usr/local/bin/kubectl && \
    curl -fsSL "https://github.com/Azure/kubelogin/releases/download/${KUBELOGIN_VERSION}/kubelogin-linux-${TARGETARCH}.zip" -o /tmp/kubelogin.zip && \
    unzip /tmp/kubelogin.zip -d /tmp/kubelogin && \
    install -m 0755 "/tmp/kubelogin/bin/linux_${TARGETARCH}/kubelogin" /usr/local/bin/kubelogin && \
    rm -rf /tmp/kubelogin /tmp/kubelogin.zip

WORKDIR /app
RUN groupadd --gid 10001 kubeuser && \
    useradd --uid 10001 --gid kubeuser --shell /usr/sbin/nologin kubeuser && \
    mkdir -p /app/Reports /home/kubeuser/.kube && \
    chown -R kubeuser:kubeuser /app /home/kubeuser

ENV KUBECONFIG=/home/kubeuser/.kube/config
ENV TERM=xterm

COPY --from=builder /out/kubebuddy /usr/local/bin/kubebuddy

USER kubeuser

CMD ["/usr/local/bin/kubebuddy", "run-env"]
