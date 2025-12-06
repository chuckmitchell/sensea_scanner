# Sensea Scanner

A Ruby-based web scraper designed to monitor appointment availability for the Sensea Nordic Spa. It runs in a Docker container, periodically scans for open slots, and serves the results via a simple web interface.

## System Architecture

*   **Scraper**: A Ruby script (`sensea_scanner.rb`) using [Ferrum](https://github.com/rubycdp/ferrum) (headless Chrome driver) to navigate the booking site and extract availability.
*   **Scheduler**: `cron` runs the scraper every 15 minutes.
*   **Web Server**: A lightweight Ruby HTTP server (`ruby -run -e httpd`) serves the JSON results and a frontend UI on port `8081`.
*   **Container**: Packaged as a Docker image with Chrome installed, optimized for headless execution.

## Configuration (Environment Variables)

| Variable | Default | Description |
| :--- | :--- | :--- |
| `HEADLESS` | `true` | Run Chrome in headless mode. Set to `false` for debugging (requires GUI). |
| `SCAN_TYPE` | `both` | What to scan. Options: `massage`, `spapass`, `both`. |
| `MASSAGE_TYPE` | `all` | Filter for massage scan. Options: `swedish`, `deep_tissue`, `couples`, `all`. |
| `TARGET_STAFF` | *(Empty)* | Comma-separated list of staff names to filter by (e.g., `Name1,Name2`). |
| `DAYS_TO_SCAN` | `30` | Number of days into the future to look for appointments. |
| `TZ` | `UTC` | Timezone for the container (affects cron schedule and logs). |

## Local Development

1.  **Install Dependencies**:
    ```bash
    bundle install
    ```
2.  **Run Scanner**:
    ```bash
    ruby sensea_scanner.rb
    ```
3.  **Run Web Server**:
    ```bash
    ruby -run -e httpd www -p 8081
    ```

## Docker Deployment

The project is designed to be deployed via **Portainer** or `docker-compose`.

### Build & Run
```bash
docker-compose up -d --build
```

### Manual Trigger
To run the scanner immediately inside the container:
```bash
docker exec -it sensea_scanner bash -c ". /app/env.sh && ruby sensea_scanner.rb"
```

### Logs
Logs are redirected to Docker's standard output, so they are visible in Portainer or via:
```bash
docker logs sensea_scanner
```

## Project Structure

*   `sensea_scanner.rb`: Main scraping logic.
*   `Dockerfile`: Environment setup (Ruby, Chrome, Cron).
*   `crontab`: Schedule definition (runs every 15 mins).
*   `start.sh`: Entrypoint script (starts cron and web server).
*   `www/`: Web root containing `index.html` and generated `appointments.json`.
