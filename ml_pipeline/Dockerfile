FROM python:3.14-slim

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1

WORKDIR /app/ml_pipeline

COPY ml_pipeline/requirements.txt ./requirements.txt
RUN python -m pip install --no-cache-dir --upgrade pip \
    && python -m pip install --no-cache-dir -r requirements.txt

COPY ml_pipeline/ ./

CMD ["sh", "-c", "python enrich_data.py && python main.py"]
