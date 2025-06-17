#!/usr/bin/env bash
###############################################################################
# CONFIG – node names → private-LAN IPs
declare -A NODE_IP=(
  [node0]=10.10.1.1
  [node1]=10.10.1.2
  [node2]=10.10.1.3
  [node3]=10.10.1.4
)
PACKETS=5          # how many ICMP probes per test
###############################################################################

nodes=("${!NODE_IP[@]}")
printf "\nPing latency matrix (avg of %d packets)\n\n" "$PACKETS"

# header row
printf "%8s" ""
for dst in "${nodes[@]}"; do printf "%8s" "$dst"; done
printf "\n"

for src in "${nodes[@]}"; do
  printf "%8s" "$src"
  for dst in "${nodes[@]}"; do
    if [[ $src == $dst ]]; then
      printf "%8s" "--"
    else
      rtt=$(ssh -oStrictHostKeyChecking=no "${NODE_IP[$src]}" \
            "ping -c $PACKETS -q ${NODE_IP[$dst]} 2>/dev/null \
             | awk -F'/' '/rtt/ {print \$5}'")
      printf "%8s" "${rtt:-fail}"
    fi
  done
  printf "\n"
done
echo
