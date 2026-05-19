from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    app_name: str = "AI Document Intelligence Hub"
    environment: str = "local"
    database_mode: str = "sqlite"
    database_url: str = "sqlite:///./data/app.db"
    azure_sql_server: str | None = None
    azure_sql_database: str | None = None
    azure_sql_username: str | None = None
    azure_sql_password: str | None = None
    storage_mode: str = "local"
    local_storage_path: str = "./data/documents"
    max_upload_size_mb: int = 10
    allowed_extensions: str = "pdf"
    azure_storage_account_name: str | None = None
    azure_storage_container_name: str = "documents"
    azure_client_id: str | None = None
    ai_analysis_provider: str = "mock"
    azure_openai_endpoint: str | None = None
    azure_openai_deployment_name: str | None = None
    azure_openai_api_version: str = "2024-10-21"
    azure_openai_auth_mode: str = "managed_identity"
    ai_max_input_chars: int = 12000
    ai_max_output_tokens: int = 800

    model_config = SettingsConfigDict(
        env_file=".env",
        env_file_encoding="utf-8",
    )


settings = Settings()
