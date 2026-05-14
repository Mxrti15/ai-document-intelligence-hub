from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    app_name: str = "AI Document Intelligence Hub"
    environment: str = "local"
    database_url: str = "sqlite:///./data/app.db"
    storage_mode: str = "local"
    local_storage_path: str = "./data/documents"
    max_upload_size_mb: int = 10
    allowed_extensions: str = "pdf"

    model_config = SettingsConfigDict(
        env_file=".env",
        env_file_encoding="utf-8",
    )


settings = Settings()
