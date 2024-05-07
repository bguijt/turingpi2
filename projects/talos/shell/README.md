# Setup Talos with Cilium, Longhorn and WasmEdge

## Preparations
1. Make sure you have the following tools installed:
   - [tpi]( https://github.com/turing-machines/tpi)
   - [talosctl](https://github.com/siderolabs/homebrew-tap)
   - [kubectl](https://kubernetes.io/docs/tasks/tools/install-kubectl-macos/)
   - [helm](https://helm.sh/docs/intro/install/)
   - [yq](https://github.com/mikefarah/yq/#install)
   - If you want to assemble a Talos image yourself: [docker](https://www.docker.com/products/docker-desktop/)
     > **NOTE:** *Docker* can be Docker Desktop or any alternative that works with a `docker` cmd line interface, e.g.
       [Colima](https://github.com/abiosoft/colima) (my personal preference),
       [OrbStack](https://orbstack.dev) etc.
2. Make sure you have [Nico Berlee's Talos image](https://github.com/nberlee/talos/releases) downloaded (and extracted). **Important: make sure your `talosctl`
   commandline tool is of the same version as this image!** One way to deal with separate `talosctl` versions is by
   using [asdf](https://asdf-vm.com) and the [asdf-talosctl](https://github.com/bjw-s/asdf-talosctl) plugin, which I did.
3. Make sure you have a TuringPi 2 board, BMC updated to at least 2.0.5, 4 RK1 units installed and 4 M.2 NVMe SSD units attached.
4. Make sure your RK1 units each have a fixed IP address (preferably, for [Cilium BGP](bgp/README.md), in their own VLAN).

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
| [rk3588](https://github.com/nberlee/extensions/tree/release-1.7.1/sbcs/rk3588)            | https://github.com/nberlee/extensions/pkgs/container/rk3588/194190019?tag=v1.7.1              | RK1 unit kernel modules                                   |
| [WasmEdge](https://github.com/siderolabs/extensions/tree/main/container-runtime/wasmedge) | https://github.com/siderolabs/extensions/pkgs/container/wasmedge/210789564?tag=v0.3.0         | RuntimeClass for WASM workloads                           |
| [iscsi-tools](https://github.com/siderolabs/extensions/tree/main/storage/iscsi-tools)     | https://github.com/siderolabs/extensions/pkgs/container/iscsi-tools/210789165?tag=v0.1.4      | Provides iscsi-tools for (Longhorn) storage provider      |
| [util-linux-tools](https://github.com/siderolabs/extensions/tree/main/tools/util-linux)   | https://github.com/siderolabs/extensions/pkgs/container/util-linux-tools/144076791?tag=2.39.3 | Provides Util Linux tools for (Longhorn) storage provider |

I created the image with the following commands (NOTE: I automated this with a [Shell script](create-installer-image.sh)):

```sh
$ EXTENSIONS_IMAGE=ghcr.io/bguijt/installer:v1.7.1-1

$ docker run --rm -t \
         -v $PWD/_out:/out \
         ghcr.io/nberlee/imager:v1.7.1 installer \
         --arch arm64 \
         --board turing_rk1 \
         --platform metal \
         --base-installer-image ghcr.io/nberlee/installer:v1.7.1-rk3588 \
         --system-extension-image ghcr.io/nberlee/rk3588:v1.7.1@sha256:239ef59bb67c48436e242fd9e39c3ef6b041e7becc1e59351d3e01495bb4e290 \
         --system-extension-image ghcr.io/siderolabs/wasmedge:v0.3.0@sha256:fcc7b087d1f08cb65a715c23bedda113233574882b89026075028599b0cb0c37 \
         --system-extension-image ghcr.io/siderolabs/iscsi-tools:v0.1.4@sha256:32d67987046ef28dcb9c54a6b34d6055eb6d78ac4ff78fa18dc6181cf31668be \
         --system-extension-image ghcr.io/siderolabs/util-linux-tools:2.39.3@sha256:1cdfab848cc2a6c2515f33ea732ac8ca34fe1a79a8bd99db6287f937b948b8f2

Unable to find image 'ghcr.io/nberlee/imager:v1.7.1' locally
85e44a3b7a20: Download complete
7904c8fdb6fa: Download complete
86c9848ca5d5: Download complete
3fa8b14eefc7: Download complete
1b8e78ef434b: Download complete
skipped pulling overlay (no overlay)
profile ready:
arch: arm64
platform: metal
board: turing_rk1
secureboot: false
version: v1.7.1
input:
  kernel:
    path: /usr/install/arm64/vmlinuz
  initramfs:
    path: /usr/install/arm64/initramfs.xz
  baseInstaller:
    imageRef: ghcr.io/nberlee/installer:v1.7.1-rk3588
  systemExtensions:
    - imageRef: ghcr.io/nberlee/rk3588:v1.7.1@sha256:239ef59bb67c48436e242fd9e39c3ef6b041e7becc1e59351d3e01495bb4e290
    - imageRef: ghcr.io/siderolabs/wasmedge:v0.3.0@sha256:fcc7b087d1f08cb65a715c23bedda113233574882b89026075028599b0cb0c37
    - imageRef: ghcr.io/siderolabs/iscsi-tools:v0.1.4@sha256:32d67987046ef28dcb9c54a6b34d6055eb6d78ac4ff78fa18dc6181cf31668be
    - imageRef: ghcr.io/siderolabs/util-linux-tools:2.39.3@sha256:1cdfab848cc2a6c2515f33ea732ac8ca34fe1a79a8bd99db6287f937b948b8f2
output:
  kind: installer
  outFormat: raw
initramfs ready
kernel command line: talos.platform=metal console=ttyAMA0 console=tty0 init_on_alloc=1 slab_nomerge pti=on consoleblank=0 nvme_core.io_timeout=4294967295 printk.devkmsg=on ima_template=ima-ng ima_appraise=fix ima_hash=sha512
installer container image ready
output asset path: /out/installer-arm64.tar

$ crane push _out/installer-arm64.tar $EXTENSIONS_IMAGE
2024/05/06 14:26:27 pushed blob: sha256:dd3436db023853039ca989968fe31a532566c38e78c6b70d34aea5964f3f9bdf
2024/05/06 14:26:28 pushed blob: sha256:1073a8b225959d90cbb9c741ef422467ac35c56b68f223bcaa475837b9df6424
2024/05/06 14:26:39 pushed blob: sha256:1b8e78ef434bb1c7b894f69f3e9d6633b3639d67399a1e2b8c8b74ab40ddf202
2024/05/06 14:26:42 pushed blob: sha256:e8077886d35266c85011b988b839d20fca66d2054b56224e1ba7a806467a3e00
2024/05/06 14:27:09 pushed blob: sha256:ff680e53dae055157dc62c94480ef2eb79566e894b28e096a4709420d2fe34ed
2024/05/06 14:27:10 ghcr.io/bguijt/installer:v1.7.1-1: digest: sha256:bd1a32e1705438c76cdc7942f199ca9229b691ba15401adb8ede8f4b2d0fad2e size: 923
ghcr.io/bguijt/installer@sha256:bd1a32e1705438c76cdc7942f199ca9229b691ba15401adb8ede8f4b2d0fad2e
```

I can use the newly created image to install the extensions to a Talos RK1 board:
```sh
$ talosctl upgrade -i $EXTENSIONS_IMAGE -n 192.168.50.11 --force
watching nodes: [192.168.50.11]
    * 192.168.50.11: post check passed

$ talosctl get extensions -n 192.168.50.11
NODE            NAMESPACE   TYPE              ID            VERSION   NAME               VERSION
192.168.50.11   runtime     ExtensionStatus   0             1         rk3588-drivers     v1.7.1
192.168.50.11   runtime     ExtensionStatus   1             1         wasmedge           v0.3.0
192.168.50.11   runtime     ExtensionStatus   2             1         iscsi-tools        v0.1.4
192.168.50.11   runtime     ExtensionStatus   3             1         util-linux-tools   2.39.3
192.168.50.11   runtime     ExtensionStatus   modules.dep   1         modules.dep        6.6.29-talos
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
IMAGE=metal-turing_rk1-arm64_v1.7.1.raw

LONGHORN_NS=longhorn-system
LONGHORN_MOUNT=/var/mnt/longhorn

INSTALLER=ghcr.io/bguijt/installer:v1.7.1-1
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
until nc -zw 3 192.168.50.11 50000; do sleep 3; printf '.'; done
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
docker run --rm -t \
       -v $PWD/_out:/out \
       -v /dev:/dev \
       --privileged \
       ghcr.io/nberlee/imager:v1.7.1 metal \
       --arch arm64 \
       --platform metal \
       --base-installer-image ghcr.io/nberlee/installer:v1.7.1-rk3588 \
       --system-extension-image ghcr.io/nberlee/rk3588:v1.7.1@sha256:239ef59bb67c48436e242fd9e39c3ef6b041e7becc1e59351d3e01495bb4e290 \
       --system-extension-image ghcr.io/siderolabs/wasmedge:v0.3.0@sha256:fcc7b087d1f08cb65a715c23bedda113233574882b89026075028599b0cb0c37 \
       --system-extension-image ghcr.io/siderolabs/iscsi-tools:v0.1.4@sha256:32d67987046ef28dcb9c54a6b34d6055eb6d78ac4ff78fa18dc6181cf31668be \
       --system-extension-image ghcr.io/siderolabs/util-linux-tools:2.39.3@sha256:1cdfab848cc2a6c2515f33ea732ac8ca34fe1a79a8bd99db6287f937b948b8f2 \
       --extra-kernel-arg sysctl.kernel.kexec_load_disabled=1 \
       --extra-kernel-arg cma=128MB \
       --extra-kernel-arg irqchip.gicv3_pseudo_nmi=0
```
Unfortunately, installing the resulting image resulted in unresponsive RK1 units.

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
- [Running WASM workloads](wasm/README.md)
- [BGP setup for advertising LoadBalancer IP's](bgp/README.md)
