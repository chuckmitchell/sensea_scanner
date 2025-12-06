#!/bin/bash

# Export environment variables to a file for cron to use
printenv | sed 's/^\(.*\)$/export \1/g' > /app/env.sh
chmod +x /app/env.sh

# Start cron
service cron start

# Run scanner immediately on startup so data is available
echo "Running initial scan..."
. /app/env.sh && ruby sensea_scanner.rb

# Start a simple Ruby web server in the foreground on port 8080
echo "Starting web server on port 8081..."
ruby -run -e httpd www -p 8081
