#!/bin/bash

wget https://downloadmirror.intel.com/793041/mlc_v3.11.tgz
mkdir -p mlc_v3.11
tar xf mlc_v3.11.tgz -C mlc_v3.11
cp mlc_v3.11/Linux/mlc .
rm mlc_v3.11.tgz
