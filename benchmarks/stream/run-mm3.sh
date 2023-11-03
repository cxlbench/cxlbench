#!/usr/bin/env bash

OUTPUT_DIR=output-`date --iso-8601=seconds`
mkdir -p ${OUTPUT_DIR}

function write_tiering_mode() {
    local tiering_mode=$1

    local input=$(sudo cat /etc/memverge/mmtier_cfg.json)

    local updated_json=$(echo "${input}" | jq --argjson tiering_mode "\"${tiering_mode}\"" '.global.tiering_mode = $tiering_mode')

    echo "$updated_json" | sudo tee /etc/memverge/mmtier_cfg.json > /dev/null
}

function write_config_target_pid() {
    local pid_arr=$1

    local input=$(sudo cat /etc/memverge/mmtier_cfg.json)

    local updated_json=$(echo "${input}" | jq --argjson targets "${pid_arr}" '.memory_profiler.targets = $targets')

    echo "$updated_json" | sudo tee /etc/memverge/mmtier_cfg.json > /dev/null
}

function restart_if_failed() {
    if [ "$(systemctl is-failed $1)" = "failed" ]; then
        echo "Service $1 is in a failing state. Restarting..."

        systemctl restart $1
    fi
}

function write_to_config() {
    local pid_arr=$1
    local tiering_mode=$2

    sudo systemctl stop mmtier

    write_config_target_pid ${pid_arr}
    write_tiering_mode ${tiering_mode}

    sleep 10

    sudo systemctl daemon-reload
    sudo systemctl start mmtier

    restart_if_failed "mmtier_mp"
    restart_if_failed "mmtier_dm"
    restart_if_failed "mmtier_de"
    restart_if_failed "mmtier_bw"
}

function run_mm3() {
    local tiering_mode=$1

    threads=(8 16 24 32 40 48 56 64)

    mkdir -p ${OUTPUT_DIR}-${tiering_mode}

    for thread in "${threads[@]}"; do
        write_to_config "[]" ${tiering_mode}

        export OMP_NUM_THREADS=${thread}
        numactl --cpunodebind=1 --membind=1 ./stream_c.exe --ntimes 600 --malloc --array-size 430080000 > ${OUTPUT_DIR}-${tiering_mode}/stream_${thread}.txt &

        pid=$!
        write_to_config "[${pid}]" ${tiering_mode}

        wait ${pid}
    done

    write_to_config "[]" ${tiering_mode}
}

function main() {
    cpu_mode=$(cat /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor | uniq)

    if [ "$cpu_mode" != "performance" ]; then
        echo "Setting CPU cores to performance mode"
        echo "performance" | sudo tee /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor
    fi

    run_mm3 "bandwidth"
    run_mm3 "latency"

    if [ "$cpu_mode" != "performance" ]; then
        echo "Setting CPU cores back to $cpu_mode mode"
        echo "$cpu_mode" | sudo tee /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor
    fi
}

main
