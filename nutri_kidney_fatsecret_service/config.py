"""
Configuration management for NutriKidney FatSecret Service.
Loads settings from environment variables with fallbacks.
"""
import os
from dotenv import load_dotenv

# Load environment variables from .env file
load_dotenv()


class Config:
    """Base configuration class."""

    BASE_DIR = os.path.dirname(os.path.abspath(__file__))
    DATA_DIR = os.path.join(BASE_DIR, "data")

    # FatSecret API Credentials
    FATSECRET_CONSUMER_KEY = os.getenv("FATSECRET_CONSUMER_KEY")
    FATSECRET_CONSUMER_SECRET = os.getenv("FATSECRET_CONSUMER_SECRET")

    # API URLs
    FATSECRET_API_BASE_URL = os.getenv(
        "FATSECRET_API_BASE_URL",
        "https://platform.fatsecret.com/rest/server.api"
    )
    FATSECRET_IMAGE_UPLOAD_URL = os.getenv(
        "FATSECRET_IMAGE_UPLOAD_URL",
        "https://platform.fatsecret.com/rest/food.imagerecognition"
    )

    # Request Configuration
    REQUEST_TIMEOUT = int(os.getenv("REQUEST_TIMEOUT", 10))
    MAX_IMAGE_SIZE_MB = int(os.getenv("MAX_IMAGE_SIZE_MB", 5))
    MAX_IMAGE_SIZE_BYTES = MAX_IMAGE_SIZE_MB * 1024 * 1024

    # Allowed image types
    ALLOWED_IMAGE_TYPES = os.getenv(
        "ALLOWED_IMAGE_TYPES",
        "image/jpeg,image/png,image/jpg"
    ).split(",")

    # Service Configuration
    ENVIRONMENT = os.getenv("ENVIRONMENT", "development")
    DEBUG = os.getenv("DEBUG", "False").lower() == "true"

    # CKD-related nutrients (priority for NutriKidney)
    CKD_PRIORITY_NUTRIENTS = [
        "sodium",
        "potassium",
        "phosphorus",
        "calcium",
        "protein",
    ]

    DEFAULT_CKD_TARGETS = {
        "sodium": 1500.0,
        "potassium": 2000.0,
        "phosphorus": 800.0,
        "protein_min": 0.0,
        "protein_max": 0.0,
    }

    MEAL_LOG_STORAGE_PATH = os.getenv(
        "MEAL_LOG_STORAGE_PATH",
        os.path.join(DATA_DIR, "meal_logs.json"),
    )
    DAILY_SUMMARY_STORAGE_PATH = os.getenv(
        "DAILY_SUMMARY_STORAGE_PATH",
        os.path.join(DATA_DIR, "daily_summaries.json"),
    )

    @staticmethod
    def validate_credentials():
        """Validate that required credentials are set."""
        if not Config.FATSECRET_CONSUMER_KEY or not Config.FATSECRET_CONSUMER_SECRET:
            raise ValueError(
                "Missing FatSecret API credentials. "
                "Set FATSECRET_CONSUMER_KEY and FATSECRET_CONSUMER_SECRET in .env"
            )


class DevelopmentConfig(Config):
    """Development environment configuration."""
    DEBUG = True
    ENVIRONMENT = "development"


class ProductionConfig(Config):
    """Production environment configuration."""
    DEBUG = False
    ENVIRONMENT = "production"


class TestConfig(Config):
    """Testing environment configuration."""
    DEBUG = True
    ENVIRONMENT = "testing"
    REQUEST_TIMEOUT = 5


def get_config():
    """Get the appropriate configuration based on environment."""
    env = os.getenv("ENVIRONMENT", "development").lower()

    if env == "production":
        return ProductionConfig
    elif env == "testing":
        return TestConfig
    else:
        return DevelopmentConfig
