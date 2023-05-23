#!/usr/bin/env bash

# Creates a snapshot/backup of the Time Series Database
curl -XPOST http://localhost:9090/api/v1/admin/tsdb/snapshot

echo "Snapshot location is 'prometheus/data/snapshots'"
