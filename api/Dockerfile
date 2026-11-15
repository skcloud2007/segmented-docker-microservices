FROM python:3.12-slim-bookworm
ENV PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1
RUN useradd --uid 10001 --no-create-home --shell /usr/sbin/nologin app
RUN apt-get update -y \
    && rm -rf /var/lib/apt/lists/* \
    && apt-get clean
WORKDIR /app
COPY api/requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY api/app.py api/healthcheck.py ./
USER 10001
EXPOSE 5000
HEALTHCHECK --interval=10s --timeout=20s --start-period=5s --retries=3 CMD [ "python", "healthcheck.py" ]
CMD ["gunicorn", "--bind", "0.0.0.0:5000", "workers=2", "app:app"]