#!/usr/bin/env bash
###############################################################################
# CONFIG – change here only ---------------------------------------------------
declare -A NODE_IP=(            # node name → private-LAN IP
  [node0]=10.10.1.1
  [node1]=10.10.1.2
  [node2]=10.10.1.3
  [node3]=10.10.1.4
)

DEFAULT_RTT=10                  # ms for every pair unless overridden

# List *each* special RTT ONCE.  The script mirrors it automatically.
declare -A RTT=(
  [node0,node2]=1
)

SSH_USER="Alephant"             # CloudLab login user
###############################################################################

half() { awk "BEGIN{print int(($1+1)/2)}"; }   # ceil(RTT/2) → one-way delay

# --- RUNS ON THE REMOTE NODE -------------------------------------------------
remote_apply() {  # $1=iface  $2=def_ms  $3=fast_ms  $4... fast_ip
  IF="$1"; shift
  DEF="$1"; shift
  FAST="$1"; shift
  FAST_PEERS=("$@")

  sudo tc qdisc del dev "$IF" root 2>/dev/null || true

  sudo tc qdisc add dev "$IF" root handle 1: htb default 20
  sudo tc class add dev "$IF" parent 1: classid 1:1 htb rate 1gbit
  sudo tc class add dev "$IF" parent 1:1 classid 1:20 htb rate 1gbit
  sudo tc qdisc add dev "$IF" parent 1:20 handle 20: netem delay "${DEF}ms"

  if [ ${#FAST_PEERS[@]} -gt 0 ] && [ "$FAST" -lt "$DEF" ]; then
    sudo tc class add dev "$IF" parent 1:1 classid 1:10 htb rate 1gbit
    sudo tc qdisc add dev "$IF" parent 1:10 handle 10: netem delay "${FAST}ms"
    for ip in "${FAST_PEERS[@]}"; do
      sudo tc filter add dev "$IF" protocol ip parent 1: prio 1 u32 \
           match ip dst "$ip"/32 flowid 1:10
    done
  fi
}
# ---------------------------------------------------------------------------

# --------------------------- driver on node0 --------------------------------
for SRC in "${!NODE_IP[@]}"; do
  SRC_IP=${NODE_IP[$SRC]}

  DEF_DLY=$(half "$DEFAULT_RTT")
  FAST_DLY=$DEF_DLY
  FAST_PEERS=()

  for DST in "${!NODE_IP[@]}"; do
    [[ $SRC == $DST ]] && continue
    key="$SRC,$DST"
    rev="$DST,$SRC"

    # auto-mirror: try forward key, else reverse, else default
    rtt=${RTT[$key]:-${RTT[$rev]:-$DEFAULT_RTT}}
    dly=$(half "$rtt")

    if (( dly < DEF_DLY )); then
      FAST_DLY=$dly
      FAST_PEERS+=("${NODE_IP[$DST]}")
    fi
  done

  # detect the interface holding 10.10.1.x
  IFACE=$(ssh -oStrictHostKeyChecking=no ${SSH_USER}@${SRC_IP} \
          "ip -br addr | awk '/10\\.10\\.1/{print \$1; exit}'")

  # ship the function & run it remotely
  ssh ${SSH_USER}@${SRC_IP} \
      "$(typeset -f half remote_apply); \
        remote_apply '$IFACE' $DEF_DLY $FAST_DLY ${FAST_PEERS[*]}"

  echo "✓  $SRC configured (iface $IFACE)"
done
echo "All nodes done."
