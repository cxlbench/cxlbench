# CXL Benchmark Suite

## Overview

CXLBench is a comprehensive benchmarking suite designed to evaluate and analyze the performance of Compute Express Link (CXL) technology. This repository provides a collection of tools, benchmarks, and utilities to assess various aspects of CXL implementations, including latency, bandwidth, and overall system performance.

This repository has several standard benchmarks that have been made to work with DRAM and CXL. Each benchmark stands alone. Read the 'README.md' for each benchmark for instructions.

## Purpose

The primary goals of CXLBench are:

1. To provide a standardized set of benchmarks for CXL technology
2. To enable researchers, developers, and industry professionals to evaluate CXL performance across different hardware configurations
3. To facilitate the comparison of various CXL implementations and their impact on system performance
4. To support the ongoing development and optimization of CXL technology

## Directory Structure

```bash
cxlbench/
├── benchmarks/         // All benchmarks
├── lib/                // Helper libraries for the benchmark scripts
├── tools/              // Helper tools for the benchmark suite scripts
├── CONTRIBUTING.md     // How to contribute to this project
├── LICENSE             // License file
└── README.md           // This file
```

## Included Benchmarks

This table shows the list of benchmarks included in this suite:

| Benchmark | Description |
|-----------|-------------|
| cloudsuite3/graph-analytics   | The Graph Analytics benchmark relies on the Spark framework to perform graph analytics on large-scale datasets |
| cloudsuite3/inmem-analytics   | This benchmark uses Apache Spark and runs a collaborative filtering algorithm (alternating least squares, ALS) provided by Spark MLlib in memory on a dataset of user-movie ratings. The metric of interest is the time in seconds for computing movie recommendations. |
| GPU/NVidia/nvbandwidth | EA tool for bandwidth measurements on NVIDIA GPUs |
| GPU/NVidia/cuda_examples | Evaluates the data transfer rates for NVidia GPUs |
| IntelMLC | Runs the Intel Memory Latency Checker (MLC) |
| memcached | Memcached is a general-purpose distributed memory-caching system |
| redis | Redis is a source-available, in-memory storage, used as a distributed, in-memory key–value database, cache and message broker |
| stream | The STREAM benchmark is a simple synthetic benchmark program that measures sustainable memory bandwidth (in MB/s) and the corresponding computation rate for simple vector kernels.  |
| tpcc | TPC-C (Transaction Processing Performance Council Benchmark C, is a benchmark used to compare the performance of online transaction processing systems. |

## How to Install CXLBench

To clone the CXLBench repository along with its submodules, use the following command:

```bash
git clone --recursive https://github.com/cxlbench/cxlbench.git
```

This will clone the main repository and initialize all submodules, including the CUDA examples and NVIDIA Bandwidth Test tool.

## Updating CXLBench

To update CXLBench, use the following command:
```bash
git pull
```

To update the submodules to their latest commits, run:
```bash
git submodule update --remote
```

## Getting Started

- Clone the repository as described above
- Choose a benchmark to run from the `benchmarks/` directory
- Follow the specific instructions for each benchmark in its respective directory

## Contributing
We welcome contributions to CXLBench! Please read our [CONTRIBUTING.md](./CONTRIBUTING.md) file for guidelines on how to submit issues, feature requests, and pull requests.

## License
CXLBench is released under the [MIT License](./LICENSE.md). ![License](https://img.shields.io/badge/license-MIT-blue.svg)

## Acknowledgments
We would like to thank the contributors of the following projects, which are included as submodules in this repository:
- [CUDA Examples](https://github.com/drkennetz/cuda_examples) by drkennetz
- [NVIDIA Bandwidth Test](https://github.com/NVIDIA/nvbandwidth) by NVIDIA

## Contributors

![Contributors](https://contributors-img.web.app/image?repo=cxlbench/cxlbench)

## Contact
For questions, suggestions, or support, please open an issue in this repository.
