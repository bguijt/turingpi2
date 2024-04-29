# BGP setup

## TL;DR
I was looking for a way to expose my Kubernetes Ingress resources / LoadBalancers to my local network.
External IPs were not assigned to my (LoadBalancer) services, which led me to try Cilium BGP. This worked,
when I assigned its own VLAN to the TuringPI unit(s).

This document is a description of how I accomplished this.

## Ingredients
My Kubernetes cluster is a 4-node [Talos](https://www.talos.dev/) cluster made of a
[Turing Pi2](https://docs.turingpi.com/docs/turing-pi2-intro) board with 4
[RK1 units](https://docs.turingpi.com/docs/turing-rk1-specs-and-io-ports).
This cluster is running with [Longhorn](https://longhorn.io) for storage, and [Cilium](https://cilium.io) for networking.
Additionally, I use a [Ubiquiti USG 4 Pro](https://tweakers.net/pricewatch/480900/ubiquiti-unifi-usg-pro-gateway-router/specificaties/)
gateway which serves my home with all my networking needs.

## Cilium BGP
To get an external IP, I first tried using `nginx-ingress`, which is used as an example for exposing the
[longhorn-frontend](https://longhorn.io/docs/1.6.1/deploy/accessing-the-ui/longhorn-ingress/).
This did not work, the `EXTERNAL-IP` of the LoadBalancer service associated with Longhorn-frontend
never left the `<pending>` status.

I learned I needed to install a networking component which would assign an external IP
to a Service, and advertise its IP to the router/gateway using the
[Border Gateway Protocol (BGP)](https://en.wikipedia.org/wiki/Border_Gateway_Protocol).
Potential candidates are
[MetalLB](https://metallb.universe.tf/usage/),
[Cilium](https://docs.cilium.io/en/latest/network/bgp-control-plane/) and
[Calico](https://docs.tigera.io/calico/latest/networking/configuring/advertise-service-ips).
Since I already had Cilium deployed, I opted for that.

I re-installed Cilium with the following configuration values:
```bash
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
     --set ingressController.loadbalancerMode=dedicated \
     --set bgpControlPlane.enabled=true \
     --set hubble.relay.enabled=true \
     --set hubble.ui.enabled=true
```
> **NOTE:** Specific config items of note are: `ingressController.*`, `bgpControlPlane.enabled` and `loadBalancer.acceleration`.

The Longhorn-frontend is exposed with the following yaml:
```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: longhorn-frontend-ingress
  namespace: longhorn-system
spec:
  ingressClassName: cilium
  rules:
  - http:
      paths:
      - backend:
          service:
            name: longhorn-frontend
            port:
              number: 80
        path: /
        pathType: Prefix
```

At this point, the external-IP is pending:
```console
$ kubectl get svc -n longhorn-system
NAME                                       TYPE           CLUSTER-IP       EXTERNAL-IP   PORT(S)                      AGE
cilium-ingress-longhorn-frontend-ingress   LoadBalancer   10.109.24.148    <pending>     80:30531/TCP,443:32561/TCP   8s
longhorn-admission-webhook                 ClusterIP      10.105.35.231    <none>        9502/TCP                     125m
longhorn-backend                           ClusterIP      10.96.199.205    <none>        9500/TCP                     125m
longhorn-conversion-webhook                ClusterIP      10.97.5.2        <none>        9501/TCP                     125m
longhorn-engine-manager                    ClusterIP      None             <none>        <none>                       125m
longhorn-frontend                          ClusterIP      10.100.214.6     <none>        80/TCP                       125m
longhorn-recovery-backend                  ClusterIP      10.96.141.196    <none>        9503/TCP                     125m
longhorn-replica-manager                   ClusterIP      None             <none>        <none>                       125m
```

> **NOTE:** I use the following IP addresses:
> 
> | IP address        | Represents                                        |
> |-------------------|---------------------------------------------------|
> | 192.168.1.1       | Ubiquiti USG Gateway IP                           |
> | 192.168.50.1      | VLAN 50 Gateway IP                                |
> | 192.168.50.11     | `talos-tp1-n1`, Worker node 1 (also Controlplane) |
> | 192.168.50.12     | `talos-tp1-n2`, Worker node 2 (also Controlplane) |
> | 192.168.50.13     | `talos-tp1-n3`, Worker node 3 (also Controlplane) |
> | 192.168.50.14     | `talos-tp1-n4`, Worker node 4                     |
> | 192.168.50.128/25 | Unassigned CIDR out of reach for DHCP             |

I applied this [IPPool resource](https://docs.cilium.io/en/latest/network/lb-ipam/) to my cluster:
```yaml
apiVersion: "cilium.io/v2alpha1"
kind: CiliumLoadBalancerIPPool
metadata:
  name: "pool"
spec:
  blocks:
  - cidr: 192.168.50.128/25
```

After this, Cilium provided an external-IP:
```console
$ kubectl get svc -n longhorn-system
NAME                                       TYPE           CLUSTER-IP       EXTERNAL-IP      PORT(S)                      AGE
cilium-ingress-longhorn-frontend-ingress   LoadBalancer   10.109.24.148    192.168.50.129   80:30531/TCP,443:32561/TCP   88s
longhorn-admission-webhook                 ClusterIP      10.105.35.231    <none>           9502/TCP                     126m
longhorn-backend                           ClusterIP      10.96.199.205    <none>           9500/TCP                     126m
longhorn-conversion-webhook                ClusterIP      10.97.5.2        <none>           9501/TCP                     126m
longhorn-engine-manager                    ClusterIP      None             <none>           <none>                       126m
longhorn-frontend                          ClusterIP      10.100.214.6     <none>           80/TCP                       126m
longhorn-recovery-backend                  ClusterIP      10.96.141.196    <none>           9503/TCP                     126m
longhorn-replica-manager                   ClusterIP      None             <none>           <none>                       126m
```

However, the service was unreachable:
```console
$ curl -s -v http://192.168.50.129/
*   Trying 192.168.50.129:80...
* connect to 192.168.50.129 port 80 failed: Operation timed out
* Failed to connect to 192.168.50.129 port 80 after 75002 ms: Couldn't connect to server
* Closing connection
```

BGP configuration is missing at this point.
For BGP to do its job, it needs the IP request to go through the gateway.
One way to force this is to use a dedicated VLAN just for the TuringPi2 board - this exposes
a Virtual Gateway which we will configure as a BGP 'neighbor' enabling all our IP needs.

I applied the following [CiliumBGPPeeringPolicy](https://docs.cilium.io/en/latest/network/bgp-control-plane/) resource:
```yaml
apiVersion: "cilium.io/v2alpha1"
kind: CiliumBGPPeeringPolicy
metadata:
  name: bgp-peering-policy
spec:
  nodeSelector:
    matchLabels:
      bgp-policy: lb
  virtualRouters:
  - localASN: 64512
    exportPodCIDR: true
    serviceSelector:
      matchExpressions:
      - {key: somekey, operator: NotIn, values: ['never-used-value']} # ALL services
    neighbors:
    - peerAddress: '192.168.50.1/32'
      peerASN: 64512
```

Next, I applied the label `bgp-policy=lb` to all my (worker) nodes to activate the `CiliumBGPPeeringPolicy`:
```console
$ kubectl label node/talos-tp1-n1 bgp-policy=lb
node/talos-tp1-n1 labeled

$ kubectl label node/talos-tp1-n2 bgp-policy=lb
node/talos-tp1-n2 labeled

$ kubectl label node/talos-tp1-n3 bgp-policy=lb
node/talos-tp1-n3 labeled

$ kubectl label node/talos-tp1-n4 bgp-policy=lb
node/talos-tp1-n4 labeled
```

Additionally, I needed to update my Ubiquiti USG Gateway configuration with a matching BGP config (note the AS number `64512`
which must match the [AS number](https://en.wikipedia.org/wiki/Autonomous_system_(Internet)#ASN_table)
from the `CiliumBGPPeeringPolicy`):
```console
$ ssh admin@192.168.1.1
# Login with SSH password from https://192.168.1.8/network/default/settings/system - 'Advanced' - 'Device SSH Authentication'

$ show ip bgp
No BGP process is configured

$ configure
[edit]

$ set protocols bgp 64512 parameters router-id 192.168.50.1
[edit]

$ set protocols bgp 64512 neighbor 192.168.50.11 remote-as 64512
[edit]

$ set protocols bgp 64512 neighbor 192.168.50.12 remote-as 64512
[edit]

$ set protocols bgp 64512 neighbor 192.168.50.13 remote-as 64512
[edit]

$ set protocols bgp 64512 neighbor 192.168.50.14 remote-as 64512
[edit]

$ commit
[edit]

$ save
Saving configuration to '/config/config.boot'...
Done
[edit]

$ show protocols
 bgp 64512 {
     neighbor 192.168.50.11 {
         remote-as 64512
     }
     neighbor 192.168.50.12 {
         remote-as 64512
     }
     neighbor 192.168.50.13 {
         remote-as 64512
     }
     neighbor 192.168.50.14 {
         remote-as 64512
     }
     parameters {
         router-id 192.168.50.1
     }
 }
 static {
     interface-route 0.0.0.0/0 {
         next-hop-interface pppoe2 {
             distance 1
         }
     }
 }
[edit]

$ exit
exit
```

Now let's see what the BGP configuration is (still in the SSH session):
```console
$ show ip bgp
BGP table version is 0, local router ID is 192.168.50.1
Status codes: s suppressed, d damped, h history, * valid, > best, i - internal,
              r RIB-failure, S Stale, R Removed
Origin codes: i - IGP, e - EGP, ? - incomplete

   Network          Next Hop            Metric LocPrf Weight Path
*>i10.244.1.0/24    192.168.50.12                 100      0 i
*>i192.168.50.128/32
                    192.168.50.12                 100      0 i
*>i192.168.50.129/32
                    192.168.50.12                 100      0 i

Total number of prefixes 3
```

Let's test the Kubernetes Ingress from my laptop (after exiting the SSH session):
```console
$ curl -s -v http://192.168.50.129/
*   Trying 192.168.50.129:80...
* Connected to 192.168.50.129 (192.168.50.129) port 80
> GET / HTTP/1.1
> Host: 192.168.50.129
> User-Agent: curl/8.4.0
> Accept: */*
>
< HTTP/1.1 200 OK
< server: envoy
< date: Thu, 25 Apr 2024 21:24:09 GMT
< content-type: text/html
< content-length: 1025
< last-modified: Thu, 28 Mar 2024 23:56:58 GMT
< vary: Accept-Encoding
< etag: "660603ca-401"
< cache-control: max-age=0
< accept-ranges: bytes
< x-envoy-upstream-service-time: 4
<
<!DOCTYPE html>
<html lang="en">
...etc.
```

Yay, it works!

```console
$ cilium bgp peers
Node           Local AS   Peer AS   Peer Address   Session State   Uptime      Family         Received   Advertised
talos-tp1-n1   64512      64512     192.168.50.1   established     13h37m19s   ipv4/unicast   0          3
                                                                               ipv6/unicast   0          0
talos-tp1-n2   64512      64512     192.168.50.1   established     13h38m10s   ipv4/unicast   0          3
                                                                               ipv6/unicast   0          0
talos-tp1-n3   64512      64512     192.168.50.1   established     13h37m41s   ipv4/unicast   0          3
                                                                               ipv6/unicast   0          0
talos-tp1-n4   64512      64512     192.168.50.1   established     13h37m14s   ipv4/unicast   0          3
                                                                               ipv6/unicast   0          0
```

## Script
The configuration consists of four parts:
1. a `CiliumLoadBalancerIPPool`
2. a `CiliumBGPPeeringPolicy`
3. assigned Kubernetes Node labels
4. Ubiquiti USG BGP configuration

To setup these BGP parts automatically, I created a shell script: [bgp-setup.sh](bgp-setup.sh).

You only need to change the configuration variables at the top, and you are good to go.
Before running, make sure you have the SSH password ready to the Ubiquiti USG Gateway,
because the script will prompt for that (as `admin@${GATEWAY_IP}'s password:`)

Sources:
- [Cilium BGP Control Plane (Beta)](https://docs.cilium.io/en/stable/network/bgp-control-plane/)
- [Kubernetes LoadBalance service using Cilium BGP control plane](https://medium.com/@valentin.hristev/kubernetes-loadbalance-service-using-cilium-bgp-control-plane-8a5ad416546a)
- [Using MetalLB as Kubernetes load balancer with Ubiquiti EdgeRouter](https://medium.com/@ipuustin/using-metallb-as-kubernetes-load-balancer-with-ubiquiti-edgerouter-7ff680e9dca3)
- [Setup basic L4 Load Balancing with Cilium CNI and Ubuiqiti Edge Router](https://www.viktorious.nl/2024/01/05/setup-basic-l4-load-balancing-with-cilium-cni-and-ubuiqiti-edge-router/)
- [BGP Peering Between Edgerouter and K8s Nodes via MetalLB](https://www.reddit.com/r/kubernetes/comments/cqwnnf/bgp_peering_between_edgerouter_and_k8s_nodes_via/)
- [Kubernetes LoadBalancer Service using a Cilium BGP Control Plane](https://rx-m.com/kubernetes-loadbalance-service-using-cilium-bgp-control-plane/)
- [BGP instructions for USG (K8s/MetalLB)](https://community.ui.com/questions/BGP-instructions-for-USG-K8s-MetalLB/b61e2f67-34f2-4571-9140-8d6b9cde2d72)
- [VyOS Command Scripting](https://docs.vyos.io/en/equuleus/automation/command-scripting.html)
