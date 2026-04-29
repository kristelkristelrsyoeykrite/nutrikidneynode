"""
Error handling for FatSecret service.
Provides structured error responses that are safe for client apps.
"""
from typing import Optional, Any, Dict
from enum import Enum


class ErrorType(str, Enum):
    """Enum of possible error types."""
    INVALID_CREDENTIALS = "invalid_credentials"
    AUTH_FAILURE = "auth_failure"
    API_REQUEST_FAILED = "api_request_failed"
    INVALID_FOOD_ID = "invalid_food_id"
    INVALID_QUERY = "invalid_query"
    INVALID_IMAGE = "invalid_image"
    FILE_TOO_LARGE = "file_too_large"
    UNSUPPORTED_IMAGE_TYPE = "unsupported_image_type"
    IMAGE_UPLOAD_FAILED = "image_upload_failed"
    NO_RESULTS_FOUND = "no_results_found"
    INCOMPLETE_DATA = "incomplete_data"
    TIMEOUT = "timeout"
    UNKNOWN = "unknown"


class NutriKidneyServiceError(Exception):
    """Base exception for NutriKidney FatSecret service."""

    def __init__(
        self,
        message: str,
        error_type: ErrorType = ErrorType.UNKNOWN,
        details: Optional[Dict[str, Any]] = None,
        status_code: int = 500,
    ):
        self.message = message
        self.error_type = error_type
        self.details = details or {}
        self.status_code = status_code
        super().__init__(self.message)

    def to_dict(self) -> Dict[str, Any]:
        """Convert error to dictionary for API response."""
        return {
            "success": False,
            "error": self.message,
            "error_type": self.error_type.value,
            "details": self.details,
        }


class CredentialsError(NutriKidneyServiceError):
    """Raised when API credentials are missing or invalid."""

    def __init__(self, message: str = "Invalid FatSecret API credentials"):
        super().__init__(
            message,
            error_type=ErrorType.INVALID_CREDENTIALS,
            status_code=401,
        )


class AuthenticationError(NutriKidneyServiceError):
    """Raised when FatSecret authentication fails."""

    def __init__(self, message: str = "FatSecret authentication failed"):
        super().__init__(
            message,
            error_type=ErrorType.AUTH_FAILURE,
            status_code=401,
        )


class FatSecretAPIError(NutriKidneyServiceError):
    """Raised when FatSecret API request fails."""

    def __init__(
        self,
        message: str = "FatSecret API request failed",
        details: Optional[Dict[str, Any]] = None,
    ):
        super().__init__(
            message,
            error_type=ErrorType.API_REQUEST_FAILED,
            details=details,
            status_code=502,
        )


class ValidationError(NutriKidneyServiceError):
    """Raised when validation fails."""

    def __init__(
        self,
        message: str,
        error_type: ErrorType = ErrorType.INVALID_QUERY,
    ):
        super().__init__(
            message,
            error_type=error_type,
            status_code=400,
        )


class ImageError(NutriKidneyServiceError):
    """Raised when image processing fails."""

    def __init__(
        self,
        message: str,
        error_type: ErrorType = ErrorType.INVALID_IMAGE,
    ):
        super().__init__(
            message,
            error_type=error_type,
            status_code=400,
        )


class NoResultsError(NutriKidneyServiceError):
    """Raised when no results are found."""

    def __init__(self, message: str = "No results found"):
        super().__init__(
            message,
            error_type=ErrorType.NO_RESULTS_FOUND,
            status_code=404,
        )


class TimeoutError(NutriKidneyServiceError):
    """Raised when request times out."""

    def __init__(self, message: str = "Request timed out"):
        super().__init__(
            message,
            error_type=ErrorType.TIMEOUT,
            status_code=408,
        )


def safe_error_response(error: Exception) -> Dict[str, Any]:
    """
    Convert any exception to a safe error response.
    Never expose sensitive information or internal details.
    """
    if isinstance(error, NutriKidneyServiceError):
        return error.to_dict()

    # Unknown error - return generic message
    return {
        "success": False,
        "error": "An unexpected error occurred",
        "error_type": ErrorType.UNKNOWN.value,
        "details": {},
    }
