#!/bin/bash

trap '{
  echo "\nKilling all clients.. Please wait..";
  for host in ${clients[@]}
  do
    ssh $host "killall -9 $client";
    ssh $host "killall -9 $client";
  done

  echo "\nKilling all replics.. Please wait..";
  for host in ${servers[@]}
  do
    ssh $host "killall -9 server";
  done
}' INT

# Paths to source code and logfiles.
srcdir="/users/Alephant/tapir"
logdir="/users/Alephant/logs"
# PGURL for PostgreSQL database
pg_url="postgresql://experiments_owner:npg_vqrPymEFW2u5@ep-lingering-glade-a87phiuy-pooler.eastus2.azure.neon.tech/experiments?sslmode=require"

# Machines on which replicas are running.
# replicas=("breakout")
replicas=("node1" "node2" "node3")

# Machines on which clients are running.
clients=("node0")

client="benchClient"    # Which client (benchClient, retwisClient, etc)
# store="strongstore"      # Which store (strongstore, weakstore, tapirstore)
# mode="occ"            # Mode for storage system.
store="tapirstore"      # Which store (strongstore, weakstore, tapirstore)
mode="txn-l"            # Mode for storage system.

nshard=1     # number of shards
nclient=1    # number of clients to run (per machine)
nkeys=100000 # number of keys to use
rtime=1     # duration to run

tlen=1       # transaction length
wper=0       # writes percentage
err=0        # error
skew=0       # skew
zalpha=-1    # zipf alpha (-1 to disable zipf and enable uniform)

git_version=$(git -C "$srcdir" rev-parse --short HEAD 2>/dev/null || echo "unknown")
nthread=1 

# Print out configuration being used.
echo "Configuration:"
echo "Git Commit:         $git_version"
echo "Replicas:           ${replicas[*]}  (total: ${#replicas[@]})"
echo "Clients:            ${clients[*]}   (total: ${#clients[@]})"
echo "Shards: $nshard"
echo "Clients per host: $nclient"
echo "Threads per client: $nthread"
echo "Keys: $nkeys"
echo "Transaction Length: $tlen"
echo "Write Percentage: $wper"
echo "Error: $err"
echo "Skew: $skew"
echo "Zipf alpha: $zalpha"
echo "Skew: $skew"
echo "Client: $client"
echo "Store: $store"
echo "Mode: $mode"


# Generate keys to be used in the experiment.
echo "Generating random keys.."
python2 key_generator.py $nkeys > keys


# Start all replicas and timestamp servers
echo "Starting TimeStampServer replicas.."
$srcdir/store/tools/start_replica.sh tss $srcdir/store/tools/shard.tss.config \
  "$srcdir/timeserver/timeserver" $logdir

for ((i=0; i<$nshard; i++))
do
  echo "Starting shard$i replicas.."
  $srcdir/store/tools/start_replica.sh shard$i $srcdir/store/tools/shard$i.config \
    "$srcdir/store/$store/server -m $mode -f $srcdir/store/tools/keys -k $nkeys -e $err -s $skew" $logdir
done


# Wait a bit for all replicas to start up
sleep 2


# Run the clients
echo "Running the client(s)"
count=0
for host in ${clients[@]}
do
  ssh $host "$srcdir/store/tools/start_client.sh \"$srcdir/store/benchmark/$client \
  -c $srcdir/store/tools/shard -N $nshard -f $srcdir/store/tools/keys \
  -d $rtime -l $tlen -w $wper -k $nkeys -m $mode -e $err -s $skew -z $zalpha\" \
  $count $nclient $logdir"

  let count=$count+$nclient
done


# Wait for all clients to exit
echo "Waiting for client(s) to exit"
for host in ${clients[@]}
do
  ssh $host "$srcdir/store/tools/wait_client.sh $client"
done


# Kill all replicas
echo "Cleaning up"
$srcdir/store/tools/stop_replica.sh $srcdir/store/tools/shard.tss.config > /dev/null 2>&1
for ((i=0; i<$nshard; i++))
do
  $srcdir/store/tools/stop_replica.sh $srcdir/store/tools/shard$i.config > /dev/null 2>&1
done


# Process logs
echo "Processing logs"
cat $logdir/client.*.log | sort -g -k 3 > $logdir/client.log
rm -f $logdir/client.*.log

python2 $srcdir/store/tools/process_logs.py $logdir/client.log $rtime \
        > $logdir/client.report

cat $logdir/client.report

throughput=$(grep -i '^Throughput' "$logdir/client.report" | awk '{print $3}' | tr -d '[:space:]')

transactions_all=$(grep -i '^Transactions(All/Success):' "$logdir/client.report" | awk '{print $2}' | tr -d '[:space:]')
transactions_success=$(grep -i '^Transactions(All/Success):' "$logdir/client.report" | awk '{print $3}' | tr -d '[:space:]')
abort_rate=$(grep -i '^Abort Rate:' "$logdir/client.report" | awk '{print $3}' | tr -d '[:space:]')
avg_lat_all=$(grep -i '^Average Latency (all):' "$logdir/client.report" | awk '{print $4}' | tr -d '[:space:]')
med_lat_all=$(grep -i '^Median  Latency (all):' "$logdir/client.report" | awk '{print $4}' | tr -d '[:space:]')
p99_lat_all=$(grep -i '^99%tile Latency (all):' "$logdir/client.report" | awk '{print $4}' | tr -d '[:space:]')
avg_lat_success=$(grep -i '^Average Latency (success):' "$logdir/client.report" | awk '{print $4}' | tr -d '[:space:]')
med_lat_success=$(grep -i '^Median  Latency (success):' "$logdir/client.report" | awk '{print $4}' | tr -d '[:space:]')
p99_lat_success=$(grep -i '^99%tile Latency (success):' "$logdir/client.report" | awk '{print $4}' | tr -d '[:space:]')
extra_all=$(grep -i '^Extra (all):' "$logdir/client.report" | awk '{print $3}' | tr -d '[:space:]')
extra_success=$(grep -i '^Extra (success):' "$logdir/client.report" | awk '{print $3}' | tr -d '[:space:]')

[ -z "$throughput" ]         && throughput=
[ -z "$transactions_all" ]   && transactions_all=
[ -z "$transactions_success" ] && transactions_success=
[ -z "$abort_rate" ]         && abort_rate=
[ -z "$avg_lat_all" ]        && avg_lat_all=
[ -z "$med_lat_all" ]        && med_lat_all=
[ -z "$p99_lat_all" ]        && p99_lat_all=
[ -z "$avg_lat_success" ]    && avg_lat_success=
[ -z "$med_lat_success" ]    && med_lat_success=
[ -z "$p99_lat_success" ]    && p99_lat_success=
[ -z "$extra_all" ]          && extra_all=
[ -z "$extra_success" ]      && extra_success=


psql "$pg_url" <<EOF
INSERT INTO results
(git_commit, replicas, clients,
 nshard, nclient, nthread, nkeys, tlen, wper, err, skew, zalpha,
 store, mode,
 throughput,
 transactions_all, transactions_success, abort_rate,
 avg_lat_all, med_lat_all, p99_lat_all,
 avg_lat_success, med_lat_success, p99_lat_success,
 extra_all, extra_success)
VALUES (
  '$git_version',
  '$(IFS=,; echo "${replicas[*]}")',
  '$(IFS=,; echo "${clients[*]}")',
  $nshard, $nclient, $nthread, $nkeys, $tlen, $wper, $err, $skew, $zalpha,
  '$store', '$mode',
  ${throughput:-NULL},
  ${transactions_all:-NULL}, ${transactions_success:-NULL}, ${abort_rate:-NULL},
  ${avg_lat_all:-NULL}, ${med_lat_all:-NULL}, ${p99_lat_all:-NULL},
  ${avg_lat_success:-NULL}, ${med_lat_success:-NULL}, ${p99_lat_success:-NULL},
  ${extra_all:-NULL}, ${extra_success:-NULL}
);
EOF

echo "Logged run to PostgreSQL via $PGURL"
# ...existing code...