#/usr/bin/env bash 

# Run Node_exporter
cd node_exporter
if ./node_exporter > node_exporter.log 2>&1 &
then
	echo "Node Exporter started successfully."
else
	echo "Error starting node_exporter. See 'node_exporter.log' for more details."
	exit 1
fi

# Wait for node_exporter to start the web service
# TODO: Poll the log vs a blanket sleep
echo "Waiting for Node Exporter to finish startup sequence..."
sleep 5

# Verify node_exporter is returning data
if curl http://localhost:9100/metrics > /dev/null
then
	echo "Node Exporter is working and collecting metrics"
else
	echo "Failed to get metrics on http://localhost:9100/metrics. Check if node_exporter is running."
	exit 1
fi

exit 0
