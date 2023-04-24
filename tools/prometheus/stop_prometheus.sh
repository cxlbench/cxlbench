#!/usr/bin/env bash 

PID=$(pgrep prometheus)
if [[ ! -z "${PID}" ]]
then
	kill ${PID}
	echo "Prometheus stopped"
else
	echo "Prometheus wasn't running"
fi
