#!/bin/bash
set -e

# Run network initialization
/scripts/init-network.sh

# Execute the command passed to the container
exec "$@"
