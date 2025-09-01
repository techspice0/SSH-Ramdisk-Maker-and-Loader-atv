#!/bin/bash

# Simple wrapper for iproxy + ssh
# Usage: ./sshtools.sh <local_port> <remote_port> <device_ip>

LOCAL_PORT=${1:-2222}
REMOTE_PORT=${2:-22}
DEVICE_IP=${3:-127.0.0.1}

echo "Starting iproxy on $LOCAL_PORT -> $REMOTE_PORT..."
./bin/iproxy $LOCAL_PORT $REMOTE_PORT &

IPROXY_PID=$!
sleep 2

echo "Connecting via SSH..."
ssh root@$DEVICE_IP -p $LOCAL_PORT

echo "Stopping iproxy..."
kill $IPROXY_PID
