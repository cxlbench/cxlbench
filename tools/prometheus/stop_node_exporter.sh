#!/usr/bin/env bash 

PID=$(pgrep node_exporter)
if [[ ! -z "${PID}" ]]
then
	kill ${PID}
	echo "node_exporter stopped"
else
	echo "node_exporter wasn't running"
fi

