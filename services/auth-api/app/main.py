from fastapi import FastAPI, Response
from app.api.auth import router as auth_router
from app.api.billing import router as billing_router
from prometheus_client import generate_latest, CONTENT_TYPE_LATEST, Counter


app = FastAPI(title="Auth API")

app.include_router(auth_router)
app.include_router(billing_router)

REQUESTS = Counter('auth_requests_total', 'Total HTTP requests (auth-api)')


@app.get("/health")
def health():
    REQUESTS.inc()
    return {"status": "ok"}


@app.get("/metrics")
def metrics():
    return Response(generate_latest(), media_type=CONTENT_TYPE_LATEST)
