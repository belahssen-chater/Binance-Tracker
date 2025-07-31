FROM python:3.11-alpine

WORKDIR /app

# Install system dependencies
RUN apt-get update && apt-get install -y \
    gcc \
    && rm -rf /var/lib/apt/lists/*

# Copy requirements and install Python dependencies
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copy application code
COPY ws_binance.py .

# Create data and logs directories
RUN mkdir -p data logs

# Set environment variables
ENV LOGSTASH_URL=http://logstash:8080

# Run the application
CMD ["python", "ws_binance.py"]
