#!/usr/bin/env bash

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
pip_packages=("humanize" "pandas" "matplotlib")
for package in "${pip_packages[@]}"
do
    if ! pip show "$package" > /dev/null 2>&1; then
        pip install $package
    fi
done

if ! [ -f stream_c.exe ]; then
    make stream_c.exe
fi

numa_nodes=("0" "1" "2" "0,2" "1,2")

cd scripts

for nn in "${numa_nodes[@]}"
do
    ./stream_generate_results.py -o stream_output_$nn -b ../stream_c.exe -n $nn
done
