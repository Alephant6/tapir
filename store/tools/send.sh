#!/bin/bash

for host in node1 node2 node3
do
  echo "Deleting /local/tapir on $host..."
  ssh "$host" "sudo rm -rf /local/tapir"
  echo "Copying new tapir folder to $host..."
  scp -rq /local/tapir "$host":/local
done

echo "All done."