FROM python:3.12-slim-bookworm
ENV PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1
RUN useradd --uid 10001 --no-create-home --shell /usr/sbin/nologin app
RUN apt-get update -y \
    && rm -rf /var/lib/apt/lists/* \
    && apt-get clean
WORKDIR /app
COPY worker/requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY worker/worker.py worker/healthcheck.py ./
RUN mkdir /reports && chown 10001:10001 /reports
USER 10001
HEALTHCHECK --interval=10s --timeout=5s --start-period=15s --retries=3 CMD [ "python", "healthcheck.py" ]
CMD ["python", "worker.py"]