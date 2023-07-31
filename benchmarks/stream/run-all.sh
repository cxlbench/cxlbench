#!/bin/bash

if command -v yum &> /dev/null; then
    echo "Detected Fedora. Installing numa.h with yum."
    sudo yum install -y numactl-devel
elif command -v apt-get &> /dev/null; then
    echo "Detected Debian-based system. Installing numa.h with apt."
    sudo apt-get update
    sudo apt-get install -y libnuma-dev
else
    echo "Only apt and yum package managers are supported at the moment."
    exit 1
fi

make stream_c.exe

numa_nodes=("0" "1" "2" "0,2" "1,2")

cd scripts

for nn in "${numa_nodes[@]}"
do
    python3 stream_generate_results.py -b ../stream_c.exe -n $nn
done
