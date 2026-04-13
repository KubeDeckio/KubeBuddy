#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VERSION="${1:-}"

if [[ -z "${VERSION}" ]]; then
  echo "usage: $0 <version-tag-or-version>" >&2
  exit 1
fi

VERSION="${VERSION#v}"
TAG="v${VERSION}"
OUT_DIR="${ROOT_DIR}/dist"

rm -rf "${OUT_DIR}"
mkdir -p "${OUT_DIR}"

targets=(
  "darwin amd64"
  "darwin arm64"
  "linux amd64"
  "linux arm64"
)

for target in "${targets[@]}"; do
  read -r goos goarch <<<"${target}"
  artifact="kubebuddy_${VERSION}_${goos}_${goarch}"
  stage="${OUT_DIR}/${artifact}"
  mkdir -p "${stage}"

  CGO_ENABLED=0 GOOS="${goos}" GOARCH="${goarch}" \
    go build -trimpath -ldflags="-s -w -X github.com/KubeDeckio/KubeBuddy/internal/version.Version=${TAG}" \
    -o "${stage}/kubebuddy" ./cmd/kubebuddy

  cp README.md "${stage}/README.md"
  cp LICENSE "${stage}/LICENSE"

  tar -C "${OUT_DIR}" -czf "${OUT_DIR}/${artifact}.tar.gz" "${artifact}"
  rm -rf "${stage}"
done

module_stage="${OUT_DIR}/KubeBuddy-psgallery"
mkdir -p "${module_stage}/Public"
cp KubeBuddy.psd1 "${module_stage}/KubeBuddy.psd1"
cp KubeBuddy.psm1 "${module_stage}/KubeBuddy.psm1"
cp Public/kubebuddy.ps1 "${module_stage}/Public/kubebuddy.ps1"
tar -C "${OUT_DIR}" -czf "${OUT_DIR}/kubebuddy-psgallery-${TAG}.tar.gz" "KubeBuddy-psgallery"
rm -rf "${module_stage}"

(
  cd "${OUT_DIR}"
  shasum -a 256 ./*.tar.gz > checksums.txt
)

echo "Release artifacts written to ${OUT_DIR}"
