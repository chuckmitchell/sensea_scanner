FROM ruby:3.2-slim

# Install dependencies for Chrome, Ferrum, and Cron
RUN apt-get update && apt-get install -y \
    wget \
    gnupg \
    cron \
    procps \
    build-essential \
    && rm -rf /var/lib/apt/lists/*

# Install Chrome
RUN wget -q -O - https://dl-ssl.google.com/linux/linux_signing_key.pub | gpg --dearmor -o /usr/share/keyrings/google-chrome.gpg \
    && echo "deb [arch=amd64 signed-by=/usr/share/keyrings/google-chrome.gpg] http://dl.google.com/linux/chrome/deb/ stable main" > /etc/apt/sources.list.d/google.list \
    && apt-get update \
    && apt-get install -y google-chrome-stable \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Copy Gemfile and install gems
COPY Gemfile Gemfile.lock ./
RUN bundle install

# Copy application code
COPY . .

# Setup Cron
COPY crontab /etc/cron.d/sensea-cron
RUN chmod 0644 /etc/cron.d/sensea-cron && crontab /etc/cron.d/sensea-cron
RUN touch /var/log/cron.log

# Make scripts executable
RUN chmod +x start.sh

# Set environment variables
ENV HEADLESS=true
ENV FERRUM_BROWSER_PATH=/usr/bin/google-chrome

# Expose web server port
EXPOSE 8081

CMD ["./start.sh"]
