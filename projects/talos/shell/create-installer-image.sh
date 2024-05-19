#!/bin/sh

# NOTE: ghcr.io/nberlee/rk3588 is added automatically to the extension list below:
EXTENSIONS=(
  # Images for Storage classes (Longhorn):
  "ghcr.io/siderolabs/iscsi-tools:v0.1.4"
  "ghcr.io/siderolabs/util-linux-tools:2.39.3"
  # Image for Tailscale
  "ghcr.io/siderolabs/tailscale:1.62.1"
)

if ! type docker &> /dev/null; then
  echo "*** docker must be installed! Install 'docker': https://www.docker.com/products/docker-desktop/ ***"
  exit 1
fi

if ! type crane &> /dev/null; then
  echo "*** crane must be installed! Install 'crane': https://github.com/google/go-containerregistry/blob/main/cmd/crane/README.md ***"
  exit 1
fi

if ! type talosctl &> /dev/null; then
  echo "*** talosctl must be installed! Install 'talosctl': https://github.com/siderolabs/homebrew-tap ***"
  exit 1
fi

if ! type gh &> /dev/null; then
  echo "*** gh must be installed! Install 'gh': https://cli.github.com ***"
  exit 1
fi

if ! type jq &> /dev/null; then
  echo "*** jq must be installed! Install 'jq': https://jqlang.github.io/jq/download/ ***"
  exit 1
fi

echo "Determining Talos version..."
TALOS_VERSION=$(talosctl version --client | grep "Tag:" | awk '{print $2}')
echo "Talos client version ${TALOS_VERSION} found. We will use that version for the Talos nodes, too."

EXTENSIONS_IMAGE=ghcr.io/$(gh api user | jq -r '.login')/installer:${TALOS_VERSION}-1

echo "Creating Talos image $EXTENSIONS_IMAGE with provided extensions..."
docker run --rm -t \
       -v $PWD/_out:/out \
       ghcr.io/nberlee/imager:v1.7.1 installer \
       --arch arm64 \
       --board turing_rk1 \
       --platform metal \
       --base-installer-image ghcr.io/nberlee/installer:${TALOS_VERSION}-rk3588 \
       --system-extension-image ghcr.io/nberlee/rk3588:${TALOS_VERSION}@$(crane digest ghcr.io/nberlee/rk3588:${TALOS_VERSION} --platform linux/arm64) \
       $(for extension in "${EXTENSIONS[@]}"; do printf " --system-extension-image $extension@$(crane digest $extension --platform linux/arm64) "; done)

if [ ! -f _out/installer-arm64.tar ]; then
  echo "*** Installer expected to be created by the Imager (previous step), but it is not! Exiting. ***"
  exit 1
fi

crane push _out/installer-arm64.tar $EXTENSIONS_IMAGE
