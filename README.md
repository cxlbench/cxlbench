# cxl_bandwidth
Perform CXL Bandwidth and Latency Measurements using Intel MLC

# Troubleshooting

If you encounter the following error:

```
alloc_mem_onnode(): unable to mbind: : Invalid argument
Buffer allocation failed!
```

Verify the DRAM and CXL memory NUMA node memory is ONLINE

```
# lsmem -o+ZONES,NODE
RANGE                                  SIZE   STATE REMOVABLE   BLOCK          ZONES NODE
0x0000000000000000-0x000000007fffffff    2G  online       yes       0           None    0
0x0000000100000000-0x000000107fffffff   62G  online       yes    2-32         Normal    0
0x0000001080000000-0x000000307fffffff  128G  online       yes   33-96         Normal    1
0x0000003080000000-0x000000407fffffff   64G  online       yes  97-128         Normal    3
0x0000004080000000-0x000000607fffffff  128G offline           129-192 Normal/Movable    2
0x0000006080000000-0x000000707fffffff   64G offline           193-224 Normal/Movable    4


Memory block size:         2G
Total online memory:     256G
Total offline memory:    192G
```

To resolve this, online the memory blocks

```
$ cd /sys/bus/node/devices/node2
$ for m in `find . -name "memory*[0-9]"`
do
  sudo echo online > $m/state
done

# lsmem
lsmem -o+ZONES,NODE
RANGE                                  SIZE   STATE REMOVABLE   BLOCK          ZONES NODE
0x0000000000000000-0x000000007fffffff    2G  online       yes       0           None    0
0x0000000100000000-0x000000107fffffff   62G  online       yes    2-32         Normal    0
0x0000001080000000-0x000000307fffffff  128G  online       yes   33-96         Normal    1
0x0000003080000000-0x000000407fffffff   64G  online       yes  97-128         Normal    3
0x0000004080000000-0x000000607fffffff  128G  online       yes 129-192         Normal    2 <<<
0x0000006080000000-0x000000707fffffff   64G offline           193-224 Normal/Movable    4

Memory block size:         2G
Total online memory:     384G
Total offline memory:     64G
```
