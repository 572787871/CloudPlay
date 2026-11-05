# syntax=docker/dockerfile:1
ARG BASE_IMAGE=debian:13-slim
FROM ${BASE_IMAGE}
RUN apt-get update && apt-get install -y --no-install-recommends aria2 python3 ca-certificates \
    && rm -rf /var/lib/apt/lists/*
WORKDIR /app
COPY --chmod=644 health.py /app/health.py
USER 10001:10001
STOPSIGNAL SIGTERM
CMD ["aria2c", "--conf-path=/config/aria2.conf"]
