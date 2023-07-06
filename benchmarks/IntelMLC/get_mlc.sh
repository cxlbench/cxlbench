#!/bin/bash

wget https://downloadmirror.intel.com/763324/mlc_v3.10.tgz
mkdir -p mlc_v3.10
tar xf mlc_v3.10.tgz -C mlc_v3.10
cp mlc_v3.10/Linux/mlc .
