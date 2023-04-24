#/usr/bin/env bash 

# See https://grafana.com/oss/prometheus/exporters/mysql-exporter/?tab=installation for instructions

mysqld_exporter_pwd="Memverge#123"	# Must match the password in install_mysqld_exporter.sh
export DATA_SOURCE_NAME="exporter:${mysqld_exporter_pwd}@(localhost:3306)/"

# Run mysqld_exporter
cd mysqld_exporter
if ./mysqld_exporter > mysqld_exporter.log 2>&1 &
then
	echo "mysqld_exporter started successfully."
else
	echo "Error starting mysqld_exporter. See 'mysqld_exporter.log' for more details."
	exit 1
fi

# Wait for mysqld_exporter to start the web service
# TODO: Poll the log vs a blanket sleep
echo "Waiting for mysqld_exporter to finish startup sequence..."
sleep 10

# Verify node_exporter is returning data
if curl http://localhost:9104/metrics > /dev/null
then
	echo "mysqld_exporter is working and collecting metrics"
else
	echo "Failed to get metrics on http://localhost:9104/metrics. Check if mysqld_exporter is running and check the 'mysqld_exporter.log'."
	exit 1
fi

exit 0
