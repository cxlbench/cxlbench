#!/usr/bin/bash

if command -v yum &> /dev/null; then
    if ! yum list installed numactl-devel; then
        echo "Detected Fedora. Installing numa.h with yum."
        sudo yum install -y numactl-devel
    fi
elif command -v dpkg &>/dev/null; then
    if ! dpkg -l | grep -q "libnuma-dev"; then
        echo "Detected Debian-based system. Installing numa.h with apt."
        sudo apt-get update
        sudo apt-get install -y libnuma-dev
    fi
else
    echo "Only Debian-based and Fedora systems are supported at the moment"
    exit 1
fi

if ! type pip &> /dev/null; then
    echo "Installing pip, due to it not being found."
    sudo yum install -y python3-pip
fi

make stream_c.exe

numa_nodes=("0" "1" "2" "0,2" "1,2")

cd scripts

for nn in "${numa_nodes[@]}"
do
    python3 stream_generate_results.py -b ../stream_c.exe -n $nn
done
