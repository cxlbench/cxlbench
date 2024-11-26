# Overview

## Setup

Use the tools/docker_prep [README](/tools/docker_prep/README) to stage the docekr image used in this benchmark test.

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
  -w  <string>   : Container name. Default: cxlbench-graph-analytics
  -d  <integer>  : Set the driver memory. Default:64g
  -e  <integer>  : Set the executor memory. Default:64g
  -o  <string>   : Output file to concatenate results to
  -n  <string>   : Optional note placed in second field of result
  -a  <0,1,2>    : Set auto-numa balancing to 0, 1 or 2
  -z  <0,1>      : set auto-numa demotion to 0 or 1.
  -t  <integer>  : set the hot data tier to N MBs
```

## Sample Test plan

Included is a sample test plan for a CXL device on NUMA Node 2.
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

# Tiering

the -t option has been added so that tiering system commands can be tested
add a setup\_env.sh that exports TIER\_CMD1 and friends or modify the script to your needs
