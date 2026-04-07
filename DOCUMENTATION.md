# **Sensea Spa Availability Scanner — Technical Documentation**
## **Overview**
The Sensea Scanner is a Ruby-based web scraping application that monitors real-time appointment availability at the Sensea Nordic Spa. It automatically navigates the spa's Acuity Scheduling booking site using a headless Chrome browser, extracts open time slots for both massage services and Spa Pass sessions, and publishes the results to a lightweight web dashboard. The entire system runs continuously inside a Docker container, with a cron job triggering the scraper every 30 minutes.
---
## **System Architecture**
The application is composed of four integrated components:
**1\. Ruby Scraper (sensea\_scanner.rb)** The core of the system. A SenseaScanner class that drives a headless Chrome browser via the Ferrum library to visit Acuity Scheduling booking pages, extract staff calendars and available time slots, and write the results as JSON to disk.
**2\. Scheduler (cron)** A crontab entry inside the container runs the scanner every 30 minutes. Output (both stdout and stderr) is forwarded to Docker's log stream so it is visible via docker logs or Portainer.
**3\. Web Server** A lightweight Ruby HTTP server (ruby \-run \-e httpd) serves static files from the www/ directory on port 8081\. This includes the generated appointments.json data file and the frontend UI.
**4\. Docker Container** The entire application is packaged as a Docker image based on ruby:3.2-slim, with Google Chrome installed for headless browsing. A docker-compose.yml is provided for deployment, configured with restart: always so the container recovers automatically after a reboot or crash.
---
## **Data Flow**
The end-to-end data flow at each scan cycle is:
1. Cron fires the Ruby script every 30 minutes.
2. The script launches a headless Chrome browser session.
3. It navigates to Acuity Scheduling booking pages for the Sensea spa.
4. It reads the window.BUSINESS JavaScript object embedded on each page to discover available appointment types, calendars (staff), and their IDs — without relying on fragile HTML scraping.
5. For massage appointments, it opens each staff member's calendar, clicks through available days, and records each open time slot.
6. For Spa Pass sessions, it reads a chronological list view and paginates through it using the "MORE TIMES" button.
7. All results are serialized to www/appointments.json, and an MD5 hash of the file is written to www/appointments.md5.
8. The frontend fetches the latest data and renders it in the browser.
---
## **The Scraper in Detail**
### **Browser Initialization**
The SenseaScanner class initializes a Ferrum browser instance with a realistic user-agent string and headless mode enabled by default. The browser is configured with a 120-second timeout, a 1280×1024 window size, and several Chrome flags (\--no-sandbox, \--disable-dev-shm-usage, \--disable-gpu) for compatibility in containerized environments.
### **Scanning Modes**
The scan type is controlled by the SCAN\_TYPE environment variable. When set to massage, only massage availability is scanned. When set to spapass, only Spa Pass slots are scanned. By default (or when set to both), both are scanned in sequence.
### **Massage Scanning**
The scanner supports three massage appointment types: Swedish, Deep Tissue, and Couples. Each has a hardcoded Acuity URL containing its appointment type ID. When scanning a massage type, the scanner:
1. Navigates to the appointment type's booking page and waits for the window.BUSINESS object to load.
2. Looks up the appointment type by ID to get the list of valid calendar (staff) IDs.
3. For each staff member, constructs a direct booking URL by appending \&calendarID=XXXX to the base URL.
4. Optionally filters staff by the TARGET\_STAFF environment variable (a comma-separated list of partial name matches).
5. Calls scan\_staff for each staff member, which navigates to their calendar and calls scrape\_month for the current and next month.
### **The scrape\_month Method**
This method extracts all available slots from a single month calendar view:
* It reads the month/year from the calendar navigation header (e.g., "April 2026").
* It finds all non-disabled day buttons using the XPath selector for react-calendar\_\_tile elements.
* For each available day, it clicks the button to reveal that day's time slots.
* It scrapes time slots by looking for input\[name='time'\] elements, labels or divs with class time-selection, or as a fallback, \<p\> tags matching a time pattern (e.g., "10:30 AM").
* It extracts the "spots left" count if present (e.g., "7 spots left") to surface limited availability.
* It uses date information from the button's aria-label attribute, with a fallback that constructs the date from the day number and the identified month/year.
### **Spa Pass Scanning**
Spa Pass sessions use a different Acuity view — a chronological list rather than a calendar. The scanner:
1. Navigates to the Spa Pass category URL to load the window.BUSINESS data.
2. Dynamically discovers all appointment types in any category whose name contains "Spa Pass" — making it resilient to the spa adding or removing pass types.
3. For each Spa Pass type, navigates to its booking page and waits for \<h2\> date headers to appear.
4. Extracts slots by walking \<h2\> (date headers) and \<h3\> (time slots) elements in the page's \<main\> container via an inline JavaScript evaluation.
5. Paginates by clicking the "MORE TIMES" button, up to a maximum of 20 pages per pass type, stopping once slots fall beyond the configured day limit.
### **Date Filtering and Output**
After scanning, all slots are filtered to include only those within DAYS\_TO\_SCAN days from today (default: 30). The results are stored in a hash keyed by a display name (e.g., "Therapist Name (Swedish)" or "Spa Pass Morning"), where each entry contains:
* image\_url — the staff member's or pass type's thumbnail image
* description — a description from the Acuity calendar data
* booking\_url — a deep link directly to the booking form for that provider/type
* slots — an array of \[date, time, spots\] tuples
A \_meta key is added with a generated\_at ISO 8601 timestamp. The complete hash is pretty-printed as JSON, written to www/appointments.json, and its MD5 hash is written to www/appointments.md5.
---
## **The Frontend**
The frontend is a single-page application consisting of a plain HTML file (www/index.html), a JavaScript file (www/assets/js/script.js), and a CSS stylesheet.
### **Smart Caching Strategy**
The frontend uses a two-step fetch strategy to balance freshness with performance:
1. appointments.md5 is fetched with a timestamp cache-buster (?t=\<epoch\>) so it is always fresh.
2. appointments.json is then fetched using the MD5 hash as a version parameter (?v=\<hash\>). This allows the browser to cache the (potentially large) JSON file indefinitely — it will only be re-fetched when the content actually changes and produces a new hash.
### **Rendering Logic**
The JavaScript flattens the JSON data into a single list of appointment objects, groups them by date, sorts the dates chronologically, and sorts individual time slots within each day by time of day. Each appointment is rendered as a clickable tile that links directly to the Acuity booking page. Tiles include:
* The staff or pass type's thumbnail image
* The appointment time
* The staff or pass type name
* A badge indicating the appointment type (e.g., "Swedish", "Deep Tissue", "Spa Pass")
* A "spots left" badge that turns a warning color when only 1–2 spots remain
The "last updated" timestamp is taken from the \_meta.generated\_at field in the JSON.
---
## **Configuration**
All runtime behavior is controlled via environment variables:
| Variable | Default | Description |
| :---- | :---- | :---- |
| SCAN\_TYPE | both | What to scan: massage, spapass, or both |
| MASSAGE\_TYPE | all | Massage type filter: swedish, deep\_tissue, couples, or all |
| TARGET\_STAFF | *(empty)* | Comma-separated list of staff name substrings to include |
| DAYS\_TO\_SCAN | 30 | How many days into the future to scan |
| HEADLESS | true | Set to false to run Chrome with a visible window (for debugging) |
| TZ | UTC | Timezone for the container; affects cron timing and log timestamps |
---
## **Deployment**
The application is deployed as a Docker container. The Dockerfile builds from ruby:3.2-slim, installs Google Chrome from the official Google Linux repository, installs the Ruby gem dependencies via Bundler, and sets the CMD to a start.sh script that launches both the cron daemon and the web server.
The docker-compose.yml configures the container with restart: always, sets TZ=America/Halifax, and connects the container to an external Docker network (dinghy\_net) — suitable for use alongside a reverse proxy such as Nginx or Traefik.
A GitHub Actions workflow (docker-publish.yml) is configured to build and publish the Docker image automatically on push, using GitHub Actions Cache to cache the Chrome installation layer and reduce build times from roughly two minutes to around thirty seconds.
---
## **Project Structure**
sensea\_scanner.rb       Main scraper script (SenseaScanner class)
Dockerfile              Container build definition
docker-compose.yml      Deployment configuration
crontab                 Cron schedule (every 30 minutes)
start.sh                Container entrypoint: starts cron \+ web server
Gemfile / Gemfile.lock  Ruby dependency definitions
www/
  index.html            Frontend single-page app
  appointments.json     Generated availability data (output of scraper)
  appointments.md5      MD5 hash of the JSON (for frontend cache busting)
  assets/
    css/style.css       Frontend styles
    js/script.js        Frontend rendering and fetch logic
    img/                Fallback images (spa\_pass.png, couples\_massage.png)
.github/workflows/
  docker-publish.yml    CI/CD pipeline for Docker image publishing
