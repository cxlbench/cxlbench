#!/usr/bin/env bash 

PID=$(pgrep mysqld_exporter)
if [[ ! -z "${PID}" ]]
then
	kill ${PID}
	echo "mysqld_exporter stopped"
else
	echo "mysqld_exporter wasn't running"
fi

