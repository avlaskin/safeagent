FROM python:3.12-slim

WORKDIR /app
RUN mkdir -p /app/data

RUN apt-get update
RUN rm -rf /var/lib/apt/lists/*

# Copy project files
COPY requirements.txt .

RUN pip install --upgrade pip
RUN pip install .
RUN pip install -r requirements.txt

# Hermes addition
RUN pip install hermes-agent
