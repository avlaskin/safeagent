FROM python:3.12-slim

WORKDIR /app
RUN mkdir -p /app/data

# Install system dependencies
RUN apt-get update -qq \
    && DEBIAN_FRONTEND=noninteractive apt-get install -y -qq --no-install-recommends curl git ca-certificates \
    # Install Node.js v20 (required for WhatsApp Baileys bridge)
    && curl -fsSL https://deb.nodesource.com/setup_20.x | bash - \
    && DEBIAN_FRONTEND=noninteractive apt-get install -y -qq nodejs \
    && rm -rf /var/lib/apt/lists/*

# Copy project files
COPY requirements.txt .

# Install python dependencies and hermes-agent with extras
RUN pip install --quiet --upgrade pip \
    && pip install --quiet -r requirements.txt \
    && pip install --quiet "hermes-agent[messaging,google,anthropic,cli,web]" playwright

# Install Chromium browser for web tools
RUN DEBIAN_FRONTEND=noninteractive python -m playwright install --with-deps chromium
