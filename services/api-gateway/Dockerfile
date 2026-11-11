FROM python:3.12-slim
RUN apt-get update && apt-get upgrade -y --no-install-recommends && rm -rf /var/lib/apt/lists/*
ENV PYTHONUNBUFFERED=1 PIP_NO_CACHE_DIR=1
WORKDIR /app
COPY requirements.txt .
RUN pip install --upgrade "pip>=26.2.0" && pip install -r requirements.txt && pip install --upgrade "setuptools>=78.1.1"
COPY . .
RUN useradd -r -u 10001 appuser && chown -R appuser /app
USER appuser
EXPOSE 8080
CMD ["uvicorn", "app:app", "--host", "0.0.0.0", "--port", "8080"]
