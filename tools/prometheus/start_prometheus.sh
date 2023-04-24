#!/usr/bin/env bash 

function create_config_file() {
	echo "Generating prometheus.yml"
	cat <<'EOF' > ./prometheus/prometheus.yml
# Global Config Options
global:
  scrape_interval: 15s

# A list of scrape configurations.
scrape_configs:
  - job_name: node
    static_configs:
      - targets: ['localhost:9100']
  - job_name: mysql
    static_configs:
      - targets: ['localhost:9104']
EOF
}

# Main 
create_config_file

cd prometheus
mkdir data
if ./prometheus --config.file=./prometheus.yml --storage.tsdb.path=./data/ --web.enable-admin-api > prometheus.log 2>&1 &
then
	echo "Prometheus Started Successfully"
else
	echo "Failed to start prometheus. Check the logs for details."
	exit 1
fi

exit 0
