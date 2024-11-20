# Overview

## Setup

Use the tools/docker_prep [README](../../../tools/docker_prep/README) to stage the docekr iamge used in this benchmark test.

## Running the test

To run a simple test, simply run ./run.sh

The default test does not do memory or cpu binding, and sets --driver-memory=64g and --executor-memory=64g (which is enough to prevent OOM issues).

Some options can be overidden

```
Usage: ./run.sh [options]
Options:
  -h             : Display this help message.
  -p             : Set in-container numactl mempolicy
  -c  <integer>  : CPU NUMA node to bind to
  -m  <int,...>  : Memory NUMA nodes to allow
  -w  <string>   : Container name. Default: cxlbench-memcached
  -d  <integer>  : Set the data size
  -q  <integer>  : Set the number of threads
  -o  <string>   : Output file to concatenate results to
  -n  <string>   : Optional note placed in second field of result
  -a  <0,1,2>    : Enable autonuma mode <1,2>
  -z  <0,1>      : Enable autonuma-demotion
  -t  <integer>  : Tier up <int>MB of data into Node 0
  -x  <int>g     : max memory usage
  -s  <int>g     : max memory+swap usage
  -r  <string>   : memcached args
```

example test plan:

```
#!/bin/bash

# Run the workload with no special settings
./run.sh -n "Default Settings"

# Bind the workload to NUMA 0
./run.sh -c 0 -m 0 -n "cpu=0 mem=0"

# Interleave the workload between Node 0 and Node 2 with weighted interleave
./run.sh -c 0 -m 0,2 -n "cpu=0 mem=0,2 --weighted-interleave=0,2" -p "--weighted-interleave=0,2"

# Primarily use NODE 2, but allow non-movable allocations to NODE 0
./run.sh -c 0 -m 0,2 -n "cpu=0 mem=0,2 --preferred=2" -p "--preferred=2"
```

