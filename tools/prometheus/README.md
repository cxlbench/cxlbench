The scripts in this directory simplify the installation and start/stop of Prometheus, MySQL, and Node exporters on a single host. It is possible to use these scripts to install Prometheus on a data collection host and the exporters on the compute host(s). Additional configuration will be required to achieve this. See the Prometheus documentation for more info. 

The tools are downloaded and executed from the current working directory. No packages are installed, making for an easy deployment.

```
create_prometheus_snapshot.sh
install-all.sh
install_mysqld_exporter.sh
install_node_exporter.sh
install_prometheus.sh
start-all.sh
start_mysqld_exporter.sh
start_node_exporter.sh
start_prometheus.sh
stop-all.sh
stop_mysqld_exporter.sh
stop_node_exporter.sh
stop_prometheus.sh
```

The product versions that will be used are:

 - Prometheus v2.43.0
 - MySQL Exporter v0.14.0
 - NodeExporter v1.5.0

## TODO
The following items are on the to do list:

 - Always download the latest release
 - Run in Podman
 - Create uninstall* scripts
 - Create a data exporter so the Prometheus TSDB can be exported and imported to another data analysis host and graphed with Grafana
