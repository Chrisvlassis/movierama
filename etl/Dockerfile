# --------------------------------------------------------- #
# Use the official Python image as base
# --------------------------------------------------------- #
FROM python:3.11-slim

# --------------------------------------------------------- #
# Install Java - required by Spark
# --------------------------------------------------------- #
RUN apt-get update && \
    apt-get install -y default-jdk && \
    apt-get clean
# set Java 
ENV JAVA_HOME=/usr/lib/jvm/default-java

# --------------------------------------------------------- #
# Set working directory inside the container
# All our files will live here
# --------------------------------------------------------- #
WORKDIR /etl_app

# --------------------------------------------------------- #
# Install Python dependencies first
# --------------------------------------------------------- #
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# --------------------------------------------------------- #
# Copy all pipeline code into the container
# --------------------------------------------------------- #
COPY pipeline.py .
COPY extract.py .
COPY transform.py .
COPY load.py .
COPY validation.py .
COPY streaming.py .
COPY tests/ tests/

# --------------------------------------------------------- #
# /data is where we expect input files and write output
# This will be mapped to etl/data/ on your local machine
# via Docker volume mount when running
# --------------------------------------------------------- #
VOLUME ["/data"]

# --------------------------------------------------------- #
# Run the pipeline when container starts
# --------------------------------------------------------- #
CMD ["python", "pipeline.py"]