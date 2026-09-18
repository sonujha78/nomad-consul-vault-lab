FROM python:3.12-alpine
RUN pip install --no-cache-dir nats-py
WORKDIR /app
COPY publisher.py subscriber.py /app/
