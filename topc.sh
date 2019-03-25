#!/bin/bash

whoami=$(whoami 2>/dev/null)

if [[ x"$whoami" != "xroot" ]]; then
    echo "Usage: you need to be root!"
    exit 1
fi

while (true); do
    perl -e 'open(TOP, "top -b | head -20 |"); while (<TOP>) { my $line = $_; chomp $line; my $pid=$1 if $line=~m/^(?:\s+)?(\d+)\s+/g;; my $host=`sudo /usr/bin/nsenter --net --uts --mount -t $pid -- hostname 2>/dev/null` if $pid; $host=`hostname` if $pid && $host eq ""; chomp $host; $host=substr($host, 0, 19); $line = sprintf "%-20s %s", "HOSTNAME", $line if $line =~ m/^\s+PID/; $line = sprintf "%-20s %s", $host, $line if $pid; print $line, "\n"; }'
    sleep 3
done
