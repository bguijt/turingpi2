# Running a WASM / WebAssembly workload
You can run a WASM image as follows (I use `wasmedge/example-wasi:latest` as an example). Create a file
named `wasm-test.yaml`:
```yaml
kind: Pod
apiVersion: v1
metadata:
  name: wasmedge-test
spec:
  restartPolicy: Never
  runtimeClassName: wasm
  containers:
  - name: wasmedge-test
    image: wasmedge/example-wasi:latest
```

Deploy that yaml file with:
```sh
$ kubectl apply -f wasm-test.yaml
Warning: would violate PodSecurity "restricted:latest": allowPrivilegeEscalation != false (container "wasmedge-test" must set securityContext.allowPrivilegeEscalation=false), unrestricted capabilities (container "wasmedge-test" must set securityContext.capabilities.drop=["ALL"]), runAsNonRoot != true (pod or container "wasmedge-test" must set securityContext.runAsNonRoot=true), seccompProfile (pod or container "wasmedge-test" must set securityContext.seccompProfile.type to "RuntimeDefault" or "Localhost")
pod/wasmedge-test created
```
> **NOTE:** Don't worry about the warnings, the pod is still deployed.
> If you want to get rid of those, use the following yaml which added a `securityContext`:
> ```yaml
> kind: Pod
> apiVersion: v1
> metadata:
>   name: wasmedge-test
> spec:
>   restartPolicy: Never
>   runtimeClassName: wasm
>   containers:
>   - name: wasmedge-test
>     image: wasmedge/example-wasi:latest
>     securityContext:
>       allowPrivilegeEscalation: false
>       capabilities:
>         drop:
>         - ALL
>       runAsNonRoot: true
>       runAsUser: 1000
>       seccompProfile:
>         type: RuntimeDefault
> ```

You can see the details of the pod as follows:
```sh
$ kubectl describe pod wasmedge-test
Name:                wasmedge-test
Namespace:           default
Priority:            0
Runtime Class Name:  wasm
Service Account:     default
Node:                talos-tp1-n1/192.168.50.11
Start Time:          Mon, 06 May 2024 16:00:22 +0200
Labels:              <none>
Annotations:         <none>
Status:              Succeeded
IP:
IPs:                 <none>
Containers:
  wasmedge-test:
    Container ID:    containerd://77bb53560aca3871171527bfd02fbeda15d6fcda945c2da0b8556ff78055e247
    Image:           wasmedge/example-wasi:latest
    Image ID:        docker.io/wasmedge/example-wasi@sha256:93e459b5a06630acdc486600549c2722be11a985ffd48a349ee811053c60ac13
    Port:            <none>
    Host Port:       <none>
    SeccompProfile:  RuntimeDefault
    State:           Terminated
      Reason:        Completed
      Exit Code:     0
      Started:       Mon, 06 May 2024 16:00:28 +0200
      Finished:      Mon, 06 May 2024 16:00:28 +0200
    Ready:           False
    Restart Count:   0
    Environment:     <none>
    Mounts:
      /var/run/secrets/kubernetes.io/serviceaccount from kube-api-access-nt2qj (ro)
Conditions:
  Type                        Status
  PodReadyToStartContainers   False
  Initialized                 True
  Ready                       False
  ContainersReady             False
  PodScheduled                True
Volumes:
  kube-api-access-nt2qj:
    Type:                    Projected (a volume that contains injected data from multiple sources)
    TokenExpirationSeconds:  3607
    ConfigMapName:           kube-root-ca.crt
    ConfigMapOptional:       <nil>
    DownwardAPI:             true
QoS Class:                   BestEffort
Node-Selectors:              <none>
Tolerations:                 node.kubernetes.io/not-ready:NoExecute op=Exists for 300s
                             node.kubernetes.io/unreachable:NoExecute op=Exists for 300s
Events:
  Type    Reason     Age   From               Message
  ----    ------     ----  ----               -------
  Normal  Scheduled  8s    default-scheduler  Successfully assigned default/wasmedge-test to talos-tp1-n1
  Normal  Pulling    5s    kubelet            Pulling image "wasmedge/example-wasi:latest"
  Normal  Pulled     3s    kubelet            Successfully pulled image "wasmedge/example-wasi:latest" in 2.673s (2.673s including waiting). Image size: 524009 bytes.
  Normal  Created    3s    kubelet            Created container wasmedge-test
  Normal  Started    2s    kubelet            Started container wasmedge-test
```
Yay, it works!

View its console output with this:
```sh
$ kubectl logs wasmedge-test
Random number: 2103935506
Random bytes: [153, 48, 197, 182, 147, 245, 246, 194, 117, 191, 103, 44, 127, 242, 32, 80, 47, 173, 120, 234, 121, 50, 128, 213, 8, 27, 250, 127, 201, 67, 108, 10, 231, 74, 159, 23, 230, 32, 81, 26, 255, 112, 6, 1, 191, 95, 155, 228, 143, 30, 66, 209, 196, 247, 105, 121, 112, 91, 67, 98, 255, 241, 196, 14, 175, 120, 51, 152, 57, 238, 73, 177, 53, 119, 41, 98, 119, 10, 224, 60, 245, 11, 109, 42, 86, 108, 197, 179, 74, 18, 101, 168, 225, 227, 28, 233, 232, 62, 221, 12, 70, 116, 62, 53, 232, 99, 30, 172, 171, 135, 46, 218, 182, 88, 7, 3, 4, 76, 99, 45, 79, 209, 84, 24, 101, 73, 67, 14]
Printed from wasi: This is from a main function
This is from a main function
The env vars are as follows.
KUBERNETES_SERVICE_PORT_HTTPS: 443
KUBERNETES_PORT_443_TCP: tcp://10.96.0.1:443
KUBERNETES_PORT: tcp://10.96.0.1:443
HOSTNAME: wasmedge-test
KUBERNETES_PORT_443_TCP_PROTO: tcp
KUBERNETES_PORT_443_TCP_PORT: 443
KUBERNETES_SERVICE_HOST: 10.96.0.1
KUBERNETES_PORT_443_TCP_ADDR: 10.96.0.1
KUBERNETES_SERVICE_PORT: 443
PATH: /usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
The args are as follows.
/wasi_example_main.wasm
File content is This is in a file
```

Since the Pod is 'Completed', we can safely delete it:
```sh
$ kubectl delete pod wasmedge-test
pod "wasmedge-test" deleted
```
