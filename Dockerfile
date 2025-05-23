# Use official Python base image
FROM python:3.10

# Set working directory
WORKDIR /app

# Copy all files to container
COPY . /app

# Install dependencies
RUN pip install --upgrade pip && pip install -r requirements.txt

# Default command (can be overridden)
CMD ["pytest"]
