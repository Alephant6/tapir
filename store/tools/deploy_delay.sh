#!/usr/bin/env bash
###############################################################################
# CONFIG – tweak here only ----------------------------------------------------
declare -A NODE_IP=(            # node name → private-LAN IP
  [node0]=10.10.1.1
  [node1]=10.10.1.2
  [node2]=10.10.1.3
  [node3]=10.10.1.4
)

DEFAULT_RTT=10                  # ms for every pair unless overridden

# List *each* special RTT once – script mirrors the other direction
declare -A RTT=(
  [node0,node2]=1               # 1 ms RTT ⇒ 0.5 ms one-way
)

SSH_USER="Alephant"             # CloudLab login user
###############################################################################

###############################################################################
# helpers                                                                    #
###############################################################################
# 1) to_ms <int|float>  → prints "Xms" or "Yus" as netem likes
to_ms () {
  # parameter is a Bash float such as 2.5 or 0.5
  printf "%sms" "$1" | sed 's/\.0\+ms$/ms/'          # tidy “2.0ms” → “2ms”
}

# 2) half_delay <RTT_ms>  → prints one-way delay with unit (string)
half_delay () {
  local rtt=$1
  # if rtt is even → integer ms; if odd → X.5ms
  if (( rtt % 2 == 0 )); then
    echo "$(to_ms $((rtt/2)))"
  else
    echo "$(to_ms "$(awk "BEGIN{print $rtt/2}")")"
  fi
}

###############################################################################
# remote side function (runs via ssh)                                        #
###############################################################################
remote_apply() {  # $1=iface  $2=def_delay  $3=fast_delay  $4... fast_ip list
  IF="$1"; DEF="$2"; FAST="$3"; shift 3; FAST_PEERS=("$@")

  sudo tc qdisc del dev "$IF" root 2>/dev/null || true

  sudo tc qdisc add dev "$IF" root handle 1: htb default 20
  sudo tc class add dev "$IF" parent 1: classid 1:1 htb rate 1gbit
  sudo tc class add dev "$IF" parent 1:1 classid 1:20 htb rate 1gbit
  sudo tc qdisc add dev "$IF" parent 1:20 handle 20: netem delay "$DEF"

  if [ ${#FAST_PEERS[@]} -gt 0 ] && [ "$FAST" != "$DEF" ]; then
    sudo tc class add dev "$IF" parent 1:1 classid 1:10 htb rate 1gbit
    sudo tc qdisc add dev "$IF" parent 1:10 handle 10: netem delay "$FAST"
    for ip in "${FAST_PEERS[@]}"; do
      sudo tc filter add dev "$IF" protocol ip parent 1: prio 1 u32 \
           match ip dst "$ip"/32 flowid 1:10
    done
  fi
}

###############################################################################
# driver running on node0                                                    #
###############################################################################
for SRC in "${!NODE_IP[@]}"; do
  SRC_IP=${NODE_IP[$SRC]}

  DEF_DELAY=$(half_delay "$DEFAULT_RTT")
  FAST_DELAY=$DEF_DELAY
  FAST_PEERS=()

  for DST in "${!NODE_IP[@]}"; do
    [[ $SRC == $DST ]] && continue
    key="$SRC,$DST"; rev="$DST,$SRC"
    rtt=${RTT[$key]:-${RTT[$rev]:-$DEFAULT_RTT}}

    if (( rtt < DEFAULT_RTT )); then
      FAST_DELAY=$(half_delay "$rtt")
      FAST_PEERS+=("${NODE_IP[$DST]}")
    fi
  done

  IFACE=$(ssh -oStrictHostKeyChecking=no ${SSH_USER}@${SRC_IP} \
          "ip -br addr | awk '/10\\.10\\.1/{print \$1; exit}'")

  ssh ${SSH_USER}@${SRC_IP} \
      "$(typeset -f to_ms half_delay remote_apply); \
        remote_apply '$IFACE' '$DEF_DELAY' '$FAST_DELAY' ${FAST_PEERS[*]}"

  echo "✓  $SRC configured (iface $IFACE)"
done
echo "All nodes done."
