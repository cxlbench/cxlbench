#/usr/bin/env bash 

function download_prometheus() {
	if wget https://github.com/prometheus/prometheus/releases/download/v2.43.0/prometheus-2.43.0.linux-amd64.tar.gz
	then
		echo "Downloaded Prometheus Successfully"
	else
		echo "Download Failed! Check previous error(s) for more info."
		exit 1
	fi
}

function unpack_prometheus() {
	if tar xf prometheus-*.*-amd64.tar.gz
	then
		echo "Unpacked Prometheus successfully"
	else
		echo "Failed to unpack Prometheus tar ball. Check previous error(s) for more info."
		exit 1
	fi
}

# Main
download_prometheus
unpack_prometheus

# Create a symlink 
if ln -s $(ls -d prometheus*/) prometheus
then
	echo "Created a symbolinc link for 'prometheus'"
else
	echo "Failed to create symlink. Check previous error(s) for more info."
fi
