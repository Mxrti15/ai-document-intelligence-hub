from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from app.api import routes_analysis, routes_analytics, routes_documents, routes_health
from app.core.config import settings
from app.core.logging import configure_logging
from app.core.telemetry import configure_telemetry
from app.db.database import init_db


configure_logging()
app = FastAPI(title=settings.app_name)
configure_telemetry(app)

app.add_middleware(
    CORSMiddleware,
    allow_origins=[
        "http://localhost:5173",
        "http://127.0.0.1:5173",
    ],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)


@app.on_event("startup")
def on_startup() -> None:
    init_db()


app.include_router(routes_health.router)
app.include_router(routes_documents.router)
app.include_router(routes_analysis.router)
app.include_router(routes_analytics.router)
