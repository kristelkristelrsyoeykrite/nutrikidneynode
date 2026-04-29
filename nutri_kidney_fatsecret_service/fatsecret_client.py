"""
FatSecret API client for NutriKidney.
Handles OAuth1 authentication and provides methods for:
- Food search
- Food detail lookup
- Image recognition

Algorithm overview:
1. Initialize with OAuth credentials
2. For each request: sign with OAuth1, send to FatSecret
3. Parse response, handle errors
4. Return raw data for normalization
"""
import requests
from typing import Dict, Any, List, Optional
from requests_oauthlib import OAuth1Session
from error_handler import (
    CredentialsError,
    AuthenticationError,
    FatSecretAPIError,
    ValidationError,
    NoResultsError,
    TimeoutError as ServiceTimeoutError,
)
from config import get_config
import logging

logger = logging.getLogger(__name__)


class FatSecretClient:
    """
    OAuth1-authenticated FatSecret API client.
    
    Provides methods for:
    - Text-based food search
    - Food detail retrieval
    - Image recognition request setup (actual upload handled separately)
    """

    # FatSecret API endpoints
    BASE_URL = "https://platform.fatsecret.com/rest/server.api"

    def __init__(self):
        """Initialize client with credentials from config."""
        self.config = get_config()
        self._validate_credentials()
        self._session = self._create_oauth_session()

    def _validate_credentials(self) -> None:
        """Ensure API credentials are available."""
        if not self.config.FATSECRET_CONSUMER_KEY or not self.config.FATSECRET_CONSUMER_SECRET:
            raise CredentialsError(
                "FatSecret API credentials not configured. "
                "Set FATSECRET_CONSUMER_KEY and FATSECRET_CONSUMER_SECRET."
            )
        logger.info("FatSecret credentials validated")

    def _create_oauth_session(self) -> OAuth1Session:
        """Create OAuth1 authenticated session."""
        try:
            session = OAuth1Session(
                client_key=self.config.FATSECRET_CONSUMER_KEY,
                client_secret=self.config.FATSECRET_CONSUMER_SECRET,
            )
            logger.info("OAuth1 session created")
            return session
        except Exception as e:
            raise AuthenticationError(f"Failed to create OAuth session: {str(e)}")

    def _make_request(self, params: Dict[str, str]) -> Dict[str, Any]:
        """
        Make authenticated request to FatSecret API.
        
        Args:
            params: Query parameters for the request
            
        Returns:
            Parsed JSON response
            
        Raises:
            Various NutriKidneyServiceError subclasses
        """
        last_timestamp_error = None

        for attempt in range(2):
            try:
                session = self._create_oauth_session()
                response = session.get(
                    self.BASE_URL,
                    params=params,
                    timeout=self.config.REQUEST_TIMEOUT,
                )

                response.raise_for_status()
                data = response.json()

                if "error" in data:
                    fatsecret_error = data.get("error")
                    if self._is_timestamp_error(fatsecret_error):
                        last_timestamp_error = fatsecret_error
                        logger.warning(
                            "FatSecret rejected oauth_timestamp on attempt %s for method %s",
                            attempt + 1,
                            params.get("method"),
                        )
                        continue

                    raise FatSecretAPIError(
                        f"FatSecret API error: {fatsecret_error}",
                        details={"fatsecret_error": fatsecret_error},
                    )

                logger.debug(f"FatSecret request successful: {params}")
                return data

            except requests.exceptions.Timeout:
                logger.error("FatSecret request timed out")
                raise ServiceTimeoutError("FatSecret request timed out")
            except requests.exceptions.RequestException as e:
                logger.error(f"FatSecret request failed: {str(e)}")
                raise FatSecretAPIError(f"FatSecret request failed: {str(e)}")

        raise FatSecretAPIError(
            "FatSecret rejected the OAuth timestamp. Check the machine clock and try again.",
            details={"fatsecret_error": last_timestamp_error or {"code": 6}},
        )

    @staticmethod
    def _is_timestamp_error(error: Any) -> bool:
        """Return True when FatSecret reports an invalid or expired OAuth timestamp."""
        if not isinstance(error, dict):
            return False

        code = str(error.get("code", "")).strip()
        message = str(error.get("message", "")).lower()
        return code == "6" or "oauth_timestamp" in message or "expired timestamp" in message

    def search_foods(self, query: str, page: int = 0) -> Dict[str, Any]:
        """
        Search for foods by text query.
        
        Algorithm:
        1. Validate query (not empty, reasonable length)
        2. Send request with pagination
        3. Return raw results
        
        Args:
            query: Food search query (e.g., "apple")
            page: Page number for pagination (0-indexed)
            
        Returns:
            Raw FatSecret search results
            
        Raises:
            ValidationError: If query is invalid
            FatSecretAPIError: If API request fails
            NoResultsError: If no results found
        """
        # Validate query
        if not query or not isinstance(query, str):
            raise ValidationError("Food query must be a non-empty string")
        
        query = query.strip()
        if len(query) < 2:
            raise ValidationError("Food query must be at least 2 characters")
        if len(query) > 100:
            raise ValidationError("Food query must be less than 100 characters")
        
        logger.info(f"Searching foods: {query}, page {page}")
        
        params = {
            "method": "foods.search",
            "search_expression": query,
            "page_number": str(page),
            "format": "json",
        }
        
        response = self._make_request(params)
        
        # Check if results exist
        foods = response.get("foods", {}).get("food", [])
        if not foods:
            raise NoResultsError(f"No foods found matching '{query}'")
        
        # Ensure foods is a list
        if not isinstance(foods, list):
            foods = [foods]
        
        return {
            "foods": foods,
            "total_results": len(foods),
            "query": query,
        }

    def get_food_details(self, food_id: str) -> Dict[str, Any]:
        """
        Retrieve detailed nutrition information for a specific food.
        
        Algorithm:
        1. Validate food_id (must be numeric string)
        2. Request food details
        3. Extract nutrition fields
        4. Return complete nutrition data
        
        Args:
            food_id: FatSecret food ID
            
        Returns:
            Detailed food nutrition data
            
        Raises:
            ValidationError: If food_id is invalid
            FatSecretAPIError: If API request fails
        """
        # Validate food_id
        if not food_id or not isinstance(food_id, str):
            raise ValidationError("Food ID must be a non-empty string")
        
        if not food_id.isdigit():
            raise ValidationError("Food ID must be numeric")
        
        logger.info(f"Getting food details for ID: {food_id}")
        
        params = {
            "method": "food.get",
            "food_id": food_id,
            "format": "json",
        }
        
        response = self._make_request(params)
        
        food_data = response.get("food")
        if not food_data:
            raise NoResultsError(f"Food not found with ID: {food_id}")
        
        return food_data

    def get_food_details_v5(self, food_id: str) -> Dict[str, Any]:
        """
        Compatibility wrapper for meal-logging code that expects a v5-style
        details method. FatSecret's current response shape still works with the
        staging flow, so we reuse the standard details lookup here.
        """
        return self.get_food_details(food_id)

    def get_image_recognition_token(self) -> Optional[str]:
        """
        Get a token for image recognition upload.
        
        FatSecret may require a token/session for image uploads.
        Check FatSecret API docs for current image recognition flow.
        
        Returns:
            Token if available, None if not required
        """
        try:
            params = {
                "method": "image.getimageuploadtoken",
                "format": "json",
            }
            response = self._make_request(params)
            token = response.get("token")
            logger.info("Image recognition token obtained")
            return token
        except Exception as e:
            logger.warning(f"Could not obtain image token: {str(e)}")
            return None

    def health_check(self) -> bool:
        """
        Check if FatSecret API is accessible.
        
        Returns:
            True if API is reachable and authenticated
        """
        try:
            params = {
                "method": "profile.get",
                "format": "json",
            }
            self._make_request(params)
            logger.info("FatSecret health check passed")
            return True
        except Exception as e:
            logger.error(f"FatSecret health check failed: {str(e)}")
            return False
