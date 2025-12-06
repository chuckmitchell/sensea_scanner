#!/bin/bash

# Export environment variables to a file for cron to use
printenv | sed 's/^\(.*\)$/export \1/g' > /app/env.sh
chmod +x /app/env.sh

# Setup Cron dynamically based on env var
INTERVAL=${SCAN_INTERVAL:-30}
echo "Setting up cron to run every $INTERVAL minutes..."
echo "*/$INTERVAL * * * * . /app/env.sh && cd /app && ruby sensea_scanner.rb > /proc/1/fd/1 2>/proc/1/fd/2" > /etc/cron.d/sensea-cron
chmod 0644 /etc/cron.d/sensea-cron
crontab /etc/cron.d/sensea-cron

# Start cron
service cron start

# Run scanner immediately on startup so data is available
echo "Running initial scan in background..."
. /app/env.sh && ruby sensea_scanner.rb &

# Start a simple Ruby web server in the foreground on port 8080
echo "Starting web server on port 8081..."
ruby -run -e httpd www -p 8081
