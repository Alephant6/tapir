#!/bin/bash

for host in breakout pitfall qbert
do
  echo "Deleting ~/tapir on $host..."
  ssh "$host" "rm -rf ~/tapir"
  echo "Copying new tapir folder to $host..."
  scp -rq /home/vscode/tapir "$host":~
done

echo "All done."