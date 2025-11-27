FROM python:3.11-slim

# Set working directory
WORKDIR /app

# Install dependencies
RUN pip install --no-cache-dir \
    deluge-client \
    requests

# Run the supervisor
CMD ["python", "-u", "/app/supervisor.py"]