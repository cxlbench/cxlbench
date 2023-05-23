#!/usr/bin/sh

if ! ./start_node_exporter.sh 
then
	echo "Failed to start node_exporter. Check the logs for more info. Exiting!"
fi

if ! ./start_mysqld_exporter.sh
then
	echo "Failed to start mysqld_exporter. Check the logs for more info. Exiting!"
fi

if ! ./start_prometheus.sh
then
	echo "Failed to start prometheus. Check the logs for more info. Exiting!"
fi

exit 

