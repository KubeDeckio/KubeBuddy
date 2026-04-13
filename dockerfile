ARG GO_IMAGE=golang:1.24.2-bookworm
ARG TOOL_IMAGE=debian:bookworm-slim
ARG RUNTIME_IMAGE=gcr.io/distroless/base-debian12:nonroot
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

FROM ${TOOL_IMAGE} AS tools

ARG TARGETARCH
ARG KUBECTL_VERSION
ARG KUBELOGIN_VERSION

RUN apt-get update && \
    apt-get install -y --no-install-recommends ca-certificates curl unzip && \
    rm -rf /var/lib/apt/lists/*

RUN mkdir -p /out

RUN curl -fsSL "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/${TARGETARCH}/kubectl" -o /out/kubectl && \
    chmod 0755 /out/kubectl && \
    curl -fsSL "https://github.com/Azure/kubelogin/releases/download/${KUBELOGIN_VERSION}/kubelogin-linux-${TARGETARCH}.zip" -o /tmp/kubelogin.zip && \
    unzip /tmp/kubelogin.zip -d /tmp/kubelogin && \
    install -m 0755 "/tmp/kubelogin/bin/linux_${TARGETARCH}/kubelogin" /out/kubelogin && \
    rm -rf /tmp/kubelogin /tmp/kubelogin.zip

FROM ${RUNTIME_IMAGE}

WORKDIR /app

ENV KUBECONFIG=/app/.kube/config
ENV HOME=/app
ENV TERM=xterm

COPY --from=builder /out/kubebuddy /usr/local/bin/kubebuddy
COPY --from=tools /out/kubectl /usr/local/bin/kubectl
COPY --from=tools /out/kubelogin /usr/local/bin/kubelogin
COPY --chown=nonroot:nonroot checks /app/checks
COPY --chown=nonroot:nonroot Private /app/Private
COPY --from=tools /etc/ssl/certs /etc/ssl/certs

CMD ["/usr/local/bin/kubebuddy", "run-env"]
