# Setup Talos with Cilium, Longhorn and WasmEdge

## Preparations
1. Make sure you have the following tools installed:
   - [tpi]( https://github.com/turing-machines/tpi)
   - [talosctl](https://github.com/siderolabs/homebrew-tap)
   - [kubectl](https://kubernetes.io/docs/tasks/tools/install-kubectl-macos/)
   - [helm](https://helm.sh/docs/intro/install/)
   - [yq](https://github.com/mikefarah/yq/#install)
2. Make sure you have [Nico Berlee's Talos image](https://github.com/nberlee/talos/releases) downloaded (and extracted)
3. Make sure you have a TuringPi 2 board, BMC updated to at least 2.0.5, 4 RK1 units installed and 4 M.2 NVMe SSD units attached.

Let's go!

## Creating the Extensions image
> **NOTE:** This is only documented for the sake of creating an Installer image yourself.
> You are free to use the same image I created.

I created an image which contains Nico's installer with a bunch of Talos extensions added, needed for Longhorn
storage and for running WASM workloads. I followed instructions largely from Talos'
[Boot Assets](https://www.talos.dev/v1.6/talos-guides/install/boot-assets/#example-bare-metal-with-imager)
documentation page.

I created the image with the following commands:

```bash
$ EXTENSIONS_IMAGE=ghcr.io/bguijt/installer:v1.6.7-4

$ docker run --rm -t -v $PWD/_out:/out ghcr.io/nberlee/imager:v1.6.7 installer \
         --arch arm64 \
         --board turing_rk1 \
         --platform metal \
         --base-installer-image ghcr.io/nberlee/installer:v1.6.7-rk3588 \
         --system-extension-image ghcr.io/nberlee/rk3588:v1.6.7@sha256:a2aff0ad1e74772b520aaf29818022a78a78817732f9c4b776ce7662ed4d5966 \
         --system-extension-image ghcr.io/siderolabs/wasmedge:v0.3.0@sha256:7994c95dc83ad778cc093c524cc65c93893a6d388c57c23d6819bc249dba322c \
         --system-extension-image ghcr.io/siderolabs/iscsi-tools:v0.1.4@sha256:5b2aff11da74fe77e0fd0242bdc22c94db7dd395c3d79519186bd3028ae605a8 \
         --system-extension-image ghcr.io/siderolabs/util-linux-tools:v1.6.7@sha256:d7499e2be241eacdb9f390839578448732facedd4ef766bf20377e49b335bb3e

profile ready:
arch: arm64
platform: metal
board: turing_rk1
secureboot: false
version: v1.6.7
input:
  kernel:
    path: /usr/install/arm64/vmlinuz
  initramfs:
    path: /usr/install/arm64/initramfs.xz
  dtb:
    path: /usr/install/arm64/dtb
  uBoot:
    path: /usr/install/arm64/u-boot
  rpiFirmware:
    path: /usr/install/arm64/raspberrypi-firmware
  baseInstaller:
    imageRef: ghcr.io/nberlee/installer:v1.6.7-rk3588
  systemExtensions:
    - imageRef: ghcr.io/nberlee/rk3588:v1.6.7@sha256:a2aff0ad1e74772b520aaf29818022a78a78817732f9c4b776ce7662ed4d5966
    - imageRef: ghcr.io/siderolabs/wasmedge:v0.3.0@sha256:7994c95dc83ad778cc093c524cc65c93893a6d388c57c23d6819bc249dba322c
    - imageRef: ghcr.io/siderolabs/iscsi-tools:v0.1.4@sha256:5b2aff11da74fe77e0fd0242bdc22c94db7dd395c3d79519186bd3028ae605a8
    - imageRef: ghcr.io/siderolabs/util-linux-tools:v1.6.7@sha256:d7499e2be241eacdb9f390839578448732facedd4ef766bf20377e49b335bb3e
output:
  kind: installer
  outFormat: raw
initramfs ready
kernel command line: talos.platform=metal console=tty0 console=ttyS9,115200 console=ttyS2,115200 talos.board=turing_rk1 sysctl.kernel.kexec_load_disabled=1 talos.dashboard.disabled=1 cma=128MB init_on_alloc=1 slab_nomerge pti=on consoleblank=0 nvme_core.io_timeout=4294967295 printk.devkmsg=on ima_template=ima-ng ima_appraise=fix ima_hash=sha512
installer container image ready
output asset path: /out/installer-arm64.tar

$ crane push _out/installer-arm64.tar $EXTENSIONS_IMAGE
2024/04/05 19:57:33 existing blob: sha256:288172aa1c94703c1e6710edb54723f3e18a23934bb62a78dad7cd2fd90059a9
2024/04/05 19:57:34 pushed blob: sha256:9d21bcaef8ca3c793c05007dcfd4354c279e085fdbbb19d9e42633fe65f40740

2024/04/05 20:02:38 pushed blob: sha256:9cf6300c5b09a03318de83505b1d0d203fc31b9dff14d5ce982e8028e0b3527c
2024/04/05 20:02:38 ghcr.io/bguijt/installer:v1.6.7-4: digest: sha256:ee80b6250d6427a3f94610157c43b4fe768e7324846b94dddc9843aba7f85de0 size: 594
ghcr.io/bguijt/installer@sha256:ee80b6250d6427a3f94610157c43b4fe768e7324846b94dddc9843aba7f85de0
```

I can use the newly created image to install the extensions to a Talos RK1 board:
```bash
$ talosctl upgrade -i $EXTENSIONS_IMAGE -n 192.168.1.111 --force
watching nodes: [192.168.1.111]
    * 192.168.1.111: post check passed

$ talosctl get extensions -n 192.168.1.111
NODE            NAMESPACE   TYPE              ID            VERSION   NAME               VERSION
192.168.1.111   runtime     ExtensionStatus   0             1         rk3588-drivers     v1.6.7
192.168.1.111   runtime     ExtensionStatus   1             1         wasmedge           v0.3.0
192.168.1.111   runtime     ExtensionStatus   2             1         iscsi-tools        v0.1.4
192.168.1.111   runtime     ExtensionStatus   3             1         util-linux-tools   $VERSION
192.168.1.111   runtime     ExtensionStatus   modules.dep   1         modules.dep        6.6.22-talos
```

Yay, it works!

> **NOTE:** I haven't figured out how to create an ISO image with the same extensions, which would save me an
> 'upgrade' step in the script below. Room for improvement here!

## The Script
The script checks most of the prerequisites, **and starts flashing your RK1's immediately**.
Sorry, no 'Are you sure' prompts. I only tested this on macOS Sonoma/14.

Here is an Terminal video of the install (takes 35 minutes, but check the markers):
[![asciicast](https://asciinema.org/a/653699.svg)](https://asciinema.org/a/653699)
