# Setup Talos with Cilium, Longhorn and WasmEdge

## Preparations
1. Make sure you have the following tools installed:
   - [tpi]( https://github.com/turing-machines/tpi)
   - [talosctl](https://github.com/siderolabs/homebrew-tap)
   - [kubectl](https://kubernetes.io/docs/tasks/tools/install-kubectl-macos/)
   - [helm](https://helm.sh/docs/intro/install/)
   - [yq](https://github.com/mikefarah/yq/#install)
2. Make sure you have [Nico Berlee's Talos image](https://github.com/nberlee/talos/releases) downloaded (and extracted). **Important: make sure your `talosctl`
   commandline tool is of the same version as this image!** One way to deal with separate `talosctl` versions is by
   using [asdf](https://asdf-vm.com) and the [asdf-talosctl](https://github.com/bjw-s/asdf-talosctl) plugin, which I did.
3. Make sure you have a TuringPi 2 board, BMC updated to at least 2.0.5, 4 RK1 units installed and 4 M.2 NVMe SSD units attached.
4. Make sure your RK1 units each have a fixed IP address.

Let's go!

## Creating the Extensions image
> **NOTE:** This is only documented for the sake of creating an Installer image yourself.
> You are free to use the same image I created.

I created an image which contains Nico's installer with a bunch of Talos extensions added, needed for Longhorn
storage and for running WASM workloads. I followed instructions largely from Talos'
[Boot Assets](https://www.talos.dev/v1.6/talos-guides/install/boot-assets/#example-bare-metal-with-imager)
documentation page.

The extensions I need are the following:

| Name/Homepage                                                                             | Package sourced from                                                                          | Purpose                                                   |
|-------------------------------------------------------------------------------------------|-----------------------------------------------------------------------------------------------|-----------------------------------------------------------|
| [rk3588](https://github.com/nberlee/extensions/tree/release-1.6.7/sbcs/rk3588)            | https://github.com/nberlee/extensions/pkgs/container/rk3588/194190019?tag=v1.6.7              | RK1 unit kernel modules                                   |
| [WasmEdge](https://github.com/siderolabs/extensions/tree/main/container-runtime/wasmedge) | https://github.com/siderolabs/extensions/pkgs/container/wasmedge/210789564?tag=v0.3.0         | RuntimeClass for WASM workloads                           |
| [iscsi-tools](https://github.com/siderolabs/extensions/tree/main/storage/iscsi-tools)     | https://github.com/siderolabs/extensions/pkgs/container/iscsi-tools/210789165?tag=v0.1.4      | Provides iscsi-tools for (Longhorn) storage provider      |
| [util-linux-tools](https://github.com/siderolabs/extensions/tree/main/tools/util-linux)   | https://github.com/siderolabs/extensions/pkgs/container/util-linux-tools/144076791?tag=v1.6.7 | Provides Util Linux tools for (Longhorn) storage provider |

I created the image with the following commands:

```sh
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
```sh
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

Let's break the script down!

### Configuring the script
The script is setup with some values you will need to adjust for your setup:

#### Constants
```sh
CLUSTERNAME=turingpi1
IPS=(      "192.168.50.11" "192.168.50.12" "192.168.50.13" "192.168.50.14")
HOSTNAMES=("talos-tp1-n1"  "talos-tp1-n2"  "talos-tp1-n3"  "talos-tp1-n4")
ROLES=(    "controlplane"  "controlplane"  "controlplane"  "worker")
ENDPOINT_IP="192.168.50.2"
IMAGE=metal-turing_rk1-arm64_v1.6.7.raw

LONGHORN_NS=longhorn-system
LONGHORN_MOUNT=/var/mnt/longhorn

INSTALLER=ghcr.io/bguijt/installer:v1.6.7-4
```

1. `CLUSTERNAME` is an arbitrary name, used as a label in your local client configuration
   and as kubernetes context name. It should be unique in the configuration on your local
   workstation.
2. `IPS` is an array of IP addresses where the install script expects your RK1 nodes to be at.
3. `HOSTNAMES` is an array of hostnames to be applied for each RK1 node.
4. `ROLES` is an array of either `"controlplane"` or `"worker"` values determining the role for each RK1 node.
   As far as I know, you can have only two variants of this array (when creating a 4-node cluster):
   `("controlplane" "controlplane" "controlplane" "worker")` or `("controlplane" "worker" "worker" "worker")`,
   either 3 or 1 ControlPlane nodes. Read [Why should a Kubernetes control plane be three nodes?](https://www.siderolabs.com/blog/why-should-a-kubernetes-control-plane-be-three-nodes/)
   for my choice of using three ControlPlane nodes.
5. `ENDPOINT_IP` is a reserved IP address which is not used yet but out of reach for your router's DHCP service.
6. `IMAGE` is the [Talos image you downloaded](https://github.com/nberlee/talos/releases).

The rest of the variables can be left as-is:
7. `LONGHORN_NS` is the Kubernetes namespace to use for Longhorn.
8. `LONGHORN_MOUNT` is the mount point for Longhorn storage on each RK1 node.
   I tried to work with `/var/lib/longhorn` at first, but got into some configuration issue.
9. `INSTALLER` is the name of the Talos Installer image, the one mentioned above as `$EXTENSIONS_IMAGE`.

#### Helm chart values for Cilium
[Cilium](https://docs.cilium.io/en/stable/overview/intro/) is setup using their Helm chart, as follows:
```sh
helm repo add cilium https://helm.cilium.io/
helm repo update cilium
CILIUM_LATEST=$(helm search repo cilium --versions --output yaml | yq '.[0].version')
helm install cilium cilium/cilium \
     --version ${CILIUM_LATEST} \
     --namespace kube-system \
     --set ipam.mode=kubernetes \
     --set securityContext.capabilities.ciliumAgent="{CHOWN,KILL,NET_ADMIN,NET_RAW,IPC_LOCK,SYS_ADMIN,SYS_RESOURCE,DAC_OVERRIDE,FOWNER,SETGID,SETUID}" \
     --set securityContext.capabilities.cleanCiliumState="{NET_ADMIN,SYS_ADMIN,SYS_RESOURCE}" \
     --set cgroup.autoMount.enabled=false \
     --set cgroup.hostRoot=/sys/fs/cgroup \
     --set l2announcements.enabled=true \
     --set kubeProxyReplacement=true \
     --set loadBalancer.acceleration=native \
     --set k8sServiceHost=127.0.0.1 \
     --set k8sServicePort=7445 \
     --set bpf.masquerade=true \
     --set ingressController.enabled=true \
     --set ingressController.default=true \
     --set ingressController.loadbalancerMode=dedicated
```
This configuration is copied from https://github.com/nberlee/talos/issues/1#issue-2110062342, and I added
the last three options to [integrate/enable Cilium as Ingress controller](https://docs.cilium.io/en/stable/network/servicemesh/ingress/#gs-ingress).

> **NOTE:** You might want to install the `cilium` cmd-line tool: [via homebrew](https://formulae.brew.sh/formula/cilium-cli)
> or [from their website](https://docs.cilium.io/en/stable/gettingstarted/k8s-install-default/#install-the-cilium-cli).

#### Helm chart values for Longhorn
[Longhorn](https://longhorn.io) is providing the StorageClass to use in the Kubernetes cluster.
Longhorn is installed as follows:
```sh
helm repo add longhorn https://charts.longhorn.io
helm repo update longhorn
LONGHORN_LATEST=$(helm search repo longhorn --versions --output yaml | yq '.[0].version')
helm install longhorn longhorn/longhorn \
     --namespace ${LONGHORN_NS} \
     --create-namespace \
     --version ${LONGHORN_LATEST} \
     --set defaultSettings.defaultReplicaCount=2 \
     --set defaultSettings.defaultDataLocality="best-effort" \
     --set defaultSettings.defaultDataPath=${LONGHORN_MOUNT} \
     --set namespaceOverride=${LONGHORN_NS}
```

I took most of the configuration from the [Talos Linux Support](https://longhorn.io/docs/1.6.1/advanced-resources/os-distro-specific/talos-linux-support/)
page from Longhorn. To prevent a manual UI step, to actually let Longhorn manage the NVMe disks,
I added some configuration to do this automatically (see [Helm values](https://longhorn.io/docs/1.6.1/advanced-resources/deploy/customizing-default-settings/#using-helm)),
specifically a value for [defaultDataPath](https://longhorn.io/docs/1.6.1/references/settings/#default-data-path).

### Some observations about the script
#### Waiting for nodes to be 'ready'
Throughout the script the process waits for the next step until a node is ready to accept a (talosctl)
instruction. I tried several approaches (like using `tpi uart get -n <node>` and wait for a certain string)
but waiting for port 50000 to be opened seemed the most reliable one:
```sh
until nc -zw 3 192.168.1.111 50000; do sleep 3; printf '.'; done
```

#### Bash vs ZSH
Especially when working with Arrays I had some trouble getting the script to work properly because Bash
and ZSH have different indices for the first element (`0` and `1`). By using `${IPS[@]:0:1}` I could
consistently solve this.

#### yq
The `yq` tool is very useful to query and edit yaml files. The script uses it to remove 'old' Kubernetes
and Talos configurations (from `~/.kube/config` and `~/.talos/config`), to 'fix' talosctl shortcomings and
to query `helm` output.

### Terminal video of an actual install
Here is a Terminal video of the install (takes 35 minutes, but check the markers):
[![asciicast](https://asciinema.org/a/653699.svg)](https://asciinema.org/a/653699)

### Some observations about the install process
#### Flashing the RK1 nodes - or talosctl reset?
Regarding the Talos Image setup, I have a somewhat blunt approach here: The RK1 units are flashed
no matter whether a Talos version is already running. A tried with a `talosctl reset` command instead, but
got inconsistent results - so I left it like this.

#### Why do I have to use BOTH an ISO image and an Installer?
I have not figured out (yet) how to create an ISO image with the same extensions I need for this setup.

I tried with:
```sh
docker run --rm -t -v $PWD/_out:/out ghcr.io/nberlee/imager:v1.6.7 iso \
       --arch arm64 \
       --board turing_rk1 \
       --platform metal \
       --base-installer-image ghcr.io/nberlee/installer:v1.6.7-rk3588 \
       --system-extension-image ghcr.io/nberlee/rk3588:v1.6.7@sha256:a2aff0ad1e74772b520aaf29818022a78a78817732f9c4b776ce7662ed4d5966 \
       --system-extension-image ghcr.io/siderolabs/wasmedge:v0.3.0@sha256:7994c95dc83ad778cc093c524cc65c93893a6d388c57c23d6819bc249dba322c \
       --system-extension-image ghcr.io/siderolabs/iscsi-tools:v0.1.4@sha256:5b2aff11da74fe77e0fd0242bdc22c94db7dd395c3d79519186bd3028ae605a8 \
       --system-extension-image ghcr.io/siderolabs/util-linux-tools:v1.6.7@sha256:d7499e2be241eacdb9f390839578448732facedd4ef766bf20377e49b335bb3e \
       --extra-kernel-arg sysctl.kernel.kexec_load_disabled=1 \
       --extra-kernel-arg cma=128MB \
       --extra-kernel-arg irqchip.gicv3_pseudo_nmi=0
```
but the resulting image is just 150MB old, compared to the 1.2GB size of @nberlee's image.

### Accessing the Longhorn Dashboard
The quickest way to access the [Longhorn Dashboard](https://longhorn.io/docs/1.6.1/nodes-and-volumes/nodes/node-space-usage/)
is by opening a local port to the longhorn-frontend service:
```sh
$ kubectl port-forward -n longhorn-system svc/longhorn-frontend 8080:80
Forwarding from 127.0.0.1:8080 -> 8000
Forwarding from [::1]:8080 -> 8000
```
Now you can open the [Longhorn Dashboard](http://localhost:8080/)!

## Next Steps
- [Running WASM workloads](../wasm/README.md)
- [BGP setup for advertising LoadBalancer IP's](../bgp/README.md)
