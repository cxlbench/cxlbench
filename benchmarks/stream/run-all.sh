#!/usr/bin/env bash

if [ -z "$1" ] || [ -e "$2" ]; then
    echo "Usage: ./run-all.sh <output-directory> <file-prefix>"
    exit 1
fi

# Installing packages on Debian-based and Fedora systems
# if said packages do not exist
if command -v yum &> /dev/null; then
    if ! yum list installed numactl-devel; then
        echo "Detected Fedora. Installing numa.h with yum."
        sudo yum install -y numactl-devel
    fi
    if ! type pip &> /dev/null; then
        echo "Pip not found, installing."
        sudo yum install -y python3-pip
    fi
elif command -v dpkg &>/dev/null; then
    if ! dpkg -l | grep -q "libnuma-dev"; then
        echo "Detected Debian-based system. Installing numa.h with apt."
        sudo apt-get update
        sudo apt-get install -y libnuma-dev
    fi
    if ! type pip &> /dev/null; then
        echo "Pip not found, installing."
        sudo apt install -y python3-pip
    fi
else
    echo "Only Debian-based and Fedora systems are supported at the moment"
    exit 1
fi

# Installing all the Python dependencies
pip3 install -r requirements.txt

if ! [ -f stream_c.exe ]; then
    make stream_c.exe
fi

# Clearing file caches
sudo sh -c "echo 3 > /proc/sys/vm/drop_caches"

# Near DRAM, Far DRAM, Near CXL, Near DRAM Far DRAM,
# Near DRAM Far CXL, Near DRAM Near CXL
numa_nodes=("0" "1" "2" "0,1" "0,2" "1,2")

cd scripts

for nn in "${numa_nodes[@]}"
do
    ./stream_generate_results.py -o $1/data -p $2 -b ../stream_c.exe -n $nn
    numa=$(echo "$nn" | tr -d ',')
    stem="$2_$numa"

    mkdir -p $1/$stem/best_of/
    ./best_of.py -c $1/data/$stem.xlsx > $1/$stem/best_of/$stem.txt

    ./graph_scripts/rate_by_operation.py \
        -c $1/data/$stem.xlsx \
        -o $1/$stem/rate_by_operation/

    ./graph_scripts/rate_by_operation_and_arraysize.py \
        -c $1/data/$stem.xlsx \
        -o $1/$stem/rate_by_operation_and_arraysize/
done
