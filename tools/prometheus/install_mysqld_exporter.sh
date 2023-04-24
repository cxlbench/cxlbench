#!/usr/bin/env bash 

# See Install instructions at https://grafana.com/oss/prometheus/exporters/mysql-exporter/?tab=installation

function download() {
	# TODO: Use git to get the latest tag, then download the latest version of node_exporter
	# Download mysql_exporter 
	echo "Downloading MySQL Exporter from https://github.com/prometheus/mysqld_exporter/releases/download/v0.14.0/mysqld_exporter-0.14.0.linux-amd64.tar.gz"
	if wget https://github.com/prometheus/mysqld_exporter/releases/download/v0.14.0/mysqld_exporter-0.14.0.linux-amd64.tar.gz
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
	if tar xfz mysqld_exporter-0.14.0.linux-amd64.tar.gz
	then
		echo "MySQL Exporter Unpacked Successfully."
	else
		echo "Unpacking MySQL Exporter failed! See previous error(s) for more info)."
		exit 1
	fi
}

function configure() {
	local MySQL_Exporter_Password="Memverge#123"
	echo 
	echo "=== Configure the MySQL Database ==="
	echo "You must create the 'exporter' user within the MySQL database instance"
	echo "Start the MySQL database and run the following"

	cat << "EOF"
mysql --user=root --password="Memverge#123"  -A -e" \
CREATE USER IF NOT EXISTS 'exporter'@'%' IDENTIFIED BY '${MySQL_Exporter_Password}' WITH MAX_USER_CONNECTIONS 5; \

FLUSH PRIVILEGES;"
EOF

	# Wait for the user to press Enter/Return before proceeding
	read -rp "Press Enter to continue once the 'exporter' user has been created" </dev/tty
	echo "=== Configure Complete ==="
}

function create_sym_link() {
	# Create a symlink 
	if ln -s $(ls -d mysqld_exporter*/) mysqld_exporter
	then
        	echo "Created a symbolinc link for 'mysqld_exporter'"
	else
        	echo "Failed to create symlink. Check previous error(s) for more info."
		exit 1
	fi
}

# Main
download
unpack
create_sym_link
configure
exit 0
