#!/bin/sh

EXTENSIONS=(
  # NOTE: ghcr.io/nberlee/rk3588 is added automatically to this extension list!
  # Image for running WASM workloads:
  "ghcr.io/siderolabs/wasmedge:v0.3.0"
  # Images for Storage classes (Longhorn):
  "ghcr.io/siderolabs/iscsi-tools:v0.1.4"
  "ghcr.io/siderolabs/util-linux-tools:2.40.1"
)

if ! type docker &> /dev/null; then
  echo "*** docker must be installed! Install 'docker': https://www.docker.com/products/docker-desktop/ ***"
  exit 1
fi

if ! docker info > /dev/null 2>&1; then
  echo "Docker is not running!"
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

if ! gh auth status > /dev/null 2>&1; then
    echo "You need to login: 'gh auth login --scopes write:packages'"
    exit 1
fi

if ! type jq &> /dev/null; then
  echo "*** jq must be installed! Install 'jq': https://jqlang.github.io/jq/download/ ***"
  exit 1
fi

echo "Determining Talos version..."
TALOS_VERSION=$(talosctl version --client | grep "Tag:" | awk '{print $2}')
echo "Talos client version ${TALOS_VERSION} found. We will use that version for the Talos nodes, too."

GH_USER=$(gh api user | jq -r '.login | ascii_downcase')
EXTENSIONS_IMAGE=ghcr.io/${GH_USER}/installer:${TALOS_VERSION}-1

echo "Logging Docker into GitHub with user ${GH_USER}..."
echo $(gh auth token) | docker login ghcr.io --username ${GH_USER} --password-stdin

echo "Creating Talos image $EXTENSIONS_IMAGE with provided extensions..."
docker run --rm -t \
       -v $PWD/_out:/out \
       ghcr.io/nberlee/imager:${TALOS_VERSION} installer \
       --arch arm64 \
       --platform metal \
       --overlay-name turingrk1 \
       --overlay-image ghcr.io/nberlee/sbc-turingrk1:${TALOS_VERSION} \
       --base-installer-image ghcr.io/nberlee/installer:${TALOS_VERSION}-rk3588 \
       --system-extension-image ghcr.io/nberlee/rk3588:${TALOS_VERSION}@$(crane digest ghcr.io/nberlee/rk3588:${TALOS_VERSION} --platform linux/arm64) \
       $(for extension in "${EXTENSIONS[@]}"; do printf " --system-extension-image $extension@$(crane digest $extension --platform linux/arm64) "; done)

if [ ! -f _out/installer-arm64.tar ]; then
  echo "*** Installer expected to be created by the Imager (previous step), but it is not! Exiting. ***"
  exit 1
fi

echo "Pushing image $EXTENSIONS_IMAGE..."
if ! crane push _out/installer-arm64.tar $EXTENSIONS_IMAGE; then
  echo "Pushing image failed. This is 'gh auth status':"
  gh auth status
  if gh auth status | grep -qF "'write:packages'"; then
    echo "Your GitHub token has required scope 'write:packages'. No idea what is going on."
  else
    echo "Your GitHub token is not scoped for 'write:packages'. Please execute 'gh auth logout' followed by 'gh auth login --scopes write:packages'"
  fi
fi
