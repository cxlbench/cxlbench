#!/usr/bin/env bash 

function download() {
	# TODO: Use git to get the latest tag, then download the latest version of node_exporter
	# Download node_exporter
	echo "Downloading Node Exporter from https://github.com/prometheus/node_exporter/releases/download/v1.5.0/node_exporter-1.5.0.linux-amd64.tar.gz"
	if wget https://github.com/prometheus/node_exporter/releases/download/v1.5.0/node_exporter-1.5.0.linux-amd64.tar.gz
	then
		echo "Download successful"
	else
		echo "Download Failed! See previous error(s)"
		exit 1
	fi
}

function unpack() {
	# Unpack the tar ball
	echo "Unpacking the tar ball"
	if tar xfz node_exporter-*.*-amd64.tar.gz
	then
		echo "Unpacked Successfully."
	else
		echo "Unpacking failed! See previous error(s) for more info)."
		exit 1
	fi
}

function create_sym_link() {
	# Create a symlink 
	if ln -s $(ls -d node_exporter*/) node_exporter
	then
		echo "Created a symbolinc link for 'node_exporter'"
	else
		echo "Failed to create symlink. Check previous error(s) for more info."
		exit 1
	fi
}

# Main
download
unpack
create_sym_link
exit 0
