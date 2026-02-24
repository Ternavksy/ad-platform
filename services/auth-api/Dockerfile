FROM python:3.12-slim

WORKDIR /app

RUN pip install --upgrade pip \
    && pip install poetry six prometheus-client

COPY pyproject.toml poetry.lock* ./

RUN poetry config virtualenvs.create false \
    && poetry lock || true \
    && poetry install --no-interaction --no-ansi

COPY . .

EXPOSE 8000
CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8000"]
