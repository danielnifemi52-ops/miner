#!/bin/bash
# Setup script for distributed miner project

# Create directory structure
mkdir -p coordinator/server/{middleware,routes,db}
mkdir -p coordinator/dashboard/src/{pages,components,hooks,utils}
mkdir -p agents/{windows,linux,android}
mkdir -p web-miner

echo "Directory structure created!"
