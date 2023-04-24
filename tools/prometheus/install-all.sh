#!/usr/bin/bash

if ! ./install_node_exporter.sh
then
	echo "Error: Installation of node_exporter failed with previous error(s). Exiting"
	exit 1
fi

if ! ./install_mysqld_exporter.sh
then
	echo "Error: Installation of mysql_exporter failed with previous error(s). Exiting"
	exit 1
fi

if ! ./install_prometheus.sh
then
	echo "Error: Installation of prometheus failed with previous error(s). Exiting"
	exit 1
fi

echo "Installation of node_exporter, mysqld_exporter, and prometheus was successful!"
exit 0
