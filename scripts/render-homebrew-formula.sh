#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TAG="${1:-}"
OUT_FILE="${2:-}"

if [[ -z "${TAG}" || -z "${OUT_FILE}" ]]; then
  echo "usage: $0 <version-tag> <output-file>" >&2
  exit 1
fi

VERSION="${TAG#v}"

sha_for() {
  local target="$1"
  local file="${ROOT_DIR}/dist/kubebuddy_${VERSION}_${target}.tar.gz"
  shasum -a 256 "$file" | awk '{print $1}'
}

DARWIN_AMD64_SHA="$(sha_for darwin_amd64)"
DARWIN_ARM64_SHA="$(sha_for darwin_arm64)"
LINUX_AMD64_SHA="$(sha_for linux_amd64)"
LINUX_ARM64_SHA="$(sha_for linux_arm64)"

cat > "${OUT_FILE}" <<EOF
class Kubebuddy < Formula
  desc "Native Kubernetes and AKS scanner for reports, audits, and CI"
  homepage "https://kubebuddy.kubedeck.io"
  license "MIT"

  on_macos do
    if Hardware::CPU.arm?
      url "https://github.com/KubeDeckio/KubeBuddy/releases/download/${TAG}/kubebuddy_${VERSION}_darwin_arm64.tar.gz"
      sha256 "${DARWIN_ARM64_SHA}"
    else
      url "https://github.com/KubeDeckio/KubeBuddy/releases/download/${TAG}/kubebuddy_${VERSION}_darwin_amd64.tar.gz"
      sha256 "${DARWIN_AMD64_SHA}"
    end
  end

  on_linux do
    if Hardware::CPU.arm?
      url "https://github.com/KubeDeckio/KubeBuddy/releases/download/${TAG}/kubebuddy_${VERSION}_linux_arm64.tar.gz"
      sha256 "${LINUX_ARM64_SHA}"
    else
      url "https://github.com/KubeDeckio/KubeBuddy/releases/download/${TAG}/kubebuddy_${VERSION}_linux_amd64.tar.gz"
      sha256 "${LINUX_AMD64_SHA}"
    end
  end

  def install
    bin.install "kubebuddy"
    pkgshare.install "README.md", "LICENSE"
  end

  test do
    assert_match version.to_s, shell_output("#{bin}/kubebuddy version")
  end
end
EOF

