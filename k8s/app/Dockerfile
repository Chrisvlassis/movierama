# use official Python image as base
FROM python:3.11-slim

# set working directory inside the container
WORKDIR /app

# copy requirements first (better caching)
COPY requirements.txt .

# install dependencies
RUN pip install --no-cache-dir -r requirements.txt

# copy the app code
COPY main.py .

# expose port 8000
EXPOSE 8000

# start the app
CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8000"]