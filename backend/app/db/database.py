from collections.abc import Generator
from pathlib import Path

from sqlalchemy import create_engine, text
from sqlalchemy.engine import URL, Engine, make_url
from sqlalchemy.orm import DeclarativeBase, Session, sessionmaker

from app.core.config import settings


def _ensure_sqlite_parent_dir(database_url: str) -> None:
    url = make_url(database_url)

    if not url.drivername.startswith("sqlite"):
        return

    database_path = url.database
    if not database_path or database_path == ":memory:":
        return

    Path(database_path).parent.mkdir(parents=True, exist_ok=True)


def _require_sql_setting(value: str | None, name: str) -> str:
    if not value:
        raise RuntimeError(f"{name} is required when DATABASE_MODE=azure_sql.")
    return value


def _build_azure_sql_url() -> URL:
    return URL.create(
        "mssql+pyodbc",
        username=_require_sql_setting(settings.azure_sql_username, "AZURE_SQL_USERNAME"),
        password=_require_sql_setting(settings.azure_sql_password, "AZURE_SQL_PASSWORD"),
        host=_require_sql_setting(settings.azure_sql_server, "AZURE_SQL_SERVER"),
        port=1433,
        database=_require_sql_setting(settings.azure_sql_database, "AZURE_SQL_DATABASE"),
        query={
            "driver": "ODBC Driver 18 for SQL Server",
            "Encrypt": "yes",
            "TrustServerCertificate": "no",
            "Connection Timeout": "30",
        },
    )


def _create_engine() -> Engine:
    if settings.database_mode == "azure_sql":
        return create_engine(
            _build_azure_sql_url(),
            pool_pre_ping=True,
            pool_size=5,
            max_overflow=10,
            pool_recycle=1800,
        )

    _ensure_sqlite_parent_dir(settings.database_url)
    connect_args = (
        {"check_same_thread": False} if settings.database_url.startswith("sqlite") else {}
    )
    return create_engine(settings.database_url, connect_args=connect_args)


engine = _create_engine()
SessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=engine)


class Base(DeclarativeBase):
    pass


def get_db() -> Generator[Session, None, None]:
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()


def check_database_ready() -> None:
    with engine.connect() as connection:
        connection.execute(text("SELECT 1"))


def init_db() -> None:
    from app.db import models  # noqa: F401

    Base.metadata.create_all(bind=engine)
