#!/bin/bash

set -e

if docker ps | grep "ankurcha/tokumx" >/dev/null; then
    docker ps | grep "ankurcha/tokumx" | awk '{ print $1 }' | xargs -r docker stop >/dev/null
    echo "Stopped the cluster and cleared all of the running containers."
fi
