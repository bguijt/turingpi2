#!/bin/sh

# This is the IP address of the Ubiquiti USG router, which we need to SSH into:
GATEWAY_IP=192.168.1.1
# This is the Gateway IP of the VLAN dedicated to the TuringPI2 board:
VLAN_GATEWAY_IP=192.168.50.1
# This CIDR is the address block reserved for Cilium LoadBalancer IPs:
LB_CIDR=192.168.50.128/25
# This is the Autonomous System number to align BGP peers with. Must be 64512..65534:
AS=64512

# Use this KEY=VALUE for labeling the Nodes where we want the BGP policy running:
NODE_LABEL_KEY="bgp-policy"
NODE_LABEL_VALUE="lb"

# Collect the names and IPs of Nodes at which we can schedule workloads:
NODE_IPS=$(kubectl get nodes --field-selector spec.unschedulable=false --output jsonpath='{.items[*].status.addresses[?(@.type=="InternalIP")].address}')
NODE_NAMES=$(kubectl get nodes --field-selector spec.unschedulable=false --output custom-columns=NAME:.metadata.name --no-headers)

echo "Configure CiliumLoadBalancerIPPool..."
kubectl apply -f - << EOF
apiVersion: "cilium.io/v2alpha1"
kind: CiliumLoadBalancerIPPool
metadata:
  name: "pool"
spec:
  blocks:
  - cidr: $LB_CIDR
EOF

echo "Configure CiliumBGPPeeringPolicy..."
kubectl apply -f - << EOF
apiVersion: "cilium.io/v2alpha1"
kind: CiliumBGPPeeringPolicy
metadata:
  name: bgp-peering-policy
spec:
  nodeSelector:
    matchLabels:
      $NODE_LABEL_KEY: $NODE_LABEL_VALUE
  virtualRouters:
  - localASN: $AS
    exportPodCIDR: true
    serviceSelector:
      matchExpressions:
      - {key: somekey, operator: NotIn, values: ['never-used-value']} # ALL services
    neighbors:
    - peerAddress: '${VLAN_GATEWAY_IP}/32'
      peerASN: $AS
EOF

echo "Label nodes ${NODE_LABEL_KEY}=${NODE_LABEL_VALUE}..."
LABELED_NODES=$(kubectl get nodes --selector "${NODE_LABEL_KEY}=${NODE_LABEL_VALUE}" --output custom-columns=NAME:.metadata.name --no-headers)
for node in $NODE_NAMES; do
  if [[ $LABELED_NODES =~ (^|[[:space:]])"$node"($|[[:space:]]) ]]; then
    # Just want to prevent confusing "node/$node not labeled" messages here:
    echo "Node $node already labeled - ignoring"
  else
    kubectl label node/$node ${NODE_LABEL_KEY}=${NODE_LABEL_VALUE}
  fi
done

echo "Configure USG Gateway..."
# Inspired by https://docs.vyos.io/en/equuleus/automation/command-scripting.html
ssh admin@${GATEWAY_IP} 'vbash -s' << EOF
source /opt/vyatta/etc/functions/script-template
configure
set protocols bgp $AS parameters router-id $VLAN_GATEWAY_IP
$(for ip in $NODE_IPS; do echo "set protocols bgp $AS neighbor $ip remote-as $AS"; done)
commit
save
show protocols
exit
EOF

echo "Testing result:"
cilium bgp peers
