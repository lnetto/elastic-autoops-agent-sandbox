#!/bin/bash

set -e

# Clean up any existing instance
echo "Cleaning up existing instances..."
multipass delete autoops 2>/dev/null || true
multipass purge

echo "Launching multipass instance 'autoops'..."
multipass launch --name autoops docker
sleep 5
multipass exec autoops -- docker stop portainer
sleep 5

echo "Current multipass instances:"
multipass list

echo "Transferring scripts..."
multipass transfer introduce_issues.sh autoops:/home/ubuntu/

# Make scripts executable
multipass exec autoops -- bash -c 'chmod +x /home/ubuntu/*.sh'

# Start Elasticsearch and capture output
echo "Starting Elasticsearch 9.1.3..."
multipass exec autoops -- bash -c "curl -fsSL https://elastic.co/start-local | sh -s -- -v 9.1.3 --esonly" 2>&1 | tee es_startup.log

echo "Waiting for Elasticsearch to fully start..."
sleep 15

# Extract endpoint and API key from output
echo "Extracting credentials..."
ES_ENDPOINT=$(grep "Elasticsearch API endpoint:" es_startup.log | awk '{print $NF}')
ES_LOCAL_API_KEY=$(grep "API key:" es_startup.log | awk '{print $NF}')

# Check container status
echo ""
echo "Docker container status:"
multipass exec autoops -- docker ps --format "table {{.Image}}\t{{.Status}}\t{{.Names}}"

# Test connection (optional)
echo ""
echo "Testing connection..."
multipass exec autoops -- bash -c "curl -H 'Authorization: ApiKey $ES_LOCAL_API_KEY' http://localhost:9200"

# Introducing Issues
echo "Introducing issues..."
multipass exec autoops -- bash -c '/home/ubuntu/introduce_issues.sh'

echo ""
echo "===== ELASTICSEARCH CREDENTIALS ====="
echo "Endpoint: $ES_ENDPOINT"
echo "API Key:  $ES_LOCAL_API_KEY"
echo "======================================"
