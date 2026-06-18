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
import time
from typing import Dict, Any, List, Optional
from threading import RLock
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
        self._search_cache: Dict[str, Dict[str, Any]] = {}
        self._search_cache_lock = RLock()
        self._search_cache_ttl_seconds = 24 * 60 * 60
        self._platform_access_token: Optional[str] = None
        self._platform_access_token_expires_at: float = 0.0

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
                response = self._session.get(
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
                        # Refresh the OAuth session once and retry.
                        self._session = self._create_oauth_session()
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

    def _get_platform_access_token(self) -> str:
        """Get an OAuth2 bearer token for platform REST endpoints."""
        if (
            self._platform_access_token
            and time.time() < self._platform_access_token_expires_at - 60
        ):
            return self._platform_access_token

        try:
            response = requests.post(
                self.config.FATSECRET_OAUTH2_TOKEN_URL,
                auth=(
                    self.config.FATSECRET_CLIENT_ID,
                    self.config.FATSECRET_CLIENT_SECRET,
                ),
                data={
                    "grant_type": "client_credentials",
                    "scope": self.config.FATSECRET_PLATFORM_SCOPE,
                },
                headers={
                    "Accept": "application/json",
                    "Content-Type": "application/x-www-form-urlencoded",
                },
                timeout=self.config.REQUEST_TIMEOUT,
            )
            response.raise_for_status()
            token_data = response.json()
        except requests.exceptions.Timeout:
            raise ServiceTimeoutError("FatSecret OAuth2 token request timed out")
        except requests.exceptions.RequestException as e:
            raise AuthenticationError(f"FatSecret OAuth2 token request failed: {str(e)}")
        except ValueError as e:
            raise AuthenticationError(f"FatSecret OAuth2 returned invalid JSON: {str(e)}")

        access_token = token_data.get("access_token")
        if not access_token:
            raise AuthenticationError("FatSecret OAuth2 response did not include an access token")

        expires_in = int(token_data.get("expires_in") or 3600)
        self._platform_access_token = str(access_token)
        self._platform_access_token_expires_at = time.time() + expires_in
        return self._platform_access_token

    def _make_platform_get_request(
        self,
        url: str,
        params: Dict[str, str],
    ) -> Dict[str, Any]:
        """Make a bearer-token GET request to a FatSecret platform endpoint."""
        token = self._get_platform_access_token()
        try:
            response = requests.get(
                url,
                params=params,
                headers={
                    "Accept": "application/json",
                    "Authorization": f"Bearer {token}",
                },
                timeout=self.config.REQUEST_TIMEOUT,
            )
            response.raise_for_status()
            data = response.json()
        except requests.exceptions.Timeout:
            raise ServiceTimeoutError("FatSecret platform request timed out")
        except requests.exceptions.RequestException as e:
            raise FatSecretAPIError(f"FatSecret platform request failed: {str(e)}")
        except ValueError as e:
            raise FatSecretAPIError(f"FatSecret platform returned invalid JSON: {str(e)}")

        if "error" in data:
            raise FatSecretAPIError(
                f"FatSecret platform API error: {data.get('error')}",
                details={"fatsecret_error": data.get("error")},
            )

        return data

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

        normalized_key = f"{' '.join(query.lower().split())}|{int(page)}"
        now = time.time()
        with self._search_cache_lock:
            cached = self._search_cache.get(normalized_key)
            if cached and cached.get("expires_at", 0) > now:
                return dict(cached.get("value") or {})
        
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
        
        result = {
            "foods": foods,
            "total_results": len(foods),
            "query": query,
        }

        with self._search_cache_lock:
            self._search_cache[normalized_key] = {
                "expires_at": now + self._search_cache_ttl_seconds,
                "value": result,
            }

        return result

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

    def search_recipes(
        self,
        query: str,
        page: int = 0,
        max_calories: Optional[int] = None,
        recipe_types: Optional[str] = None,
    ) -> Dict[str, Any]:
        """
        Search for recipes by text query using recipes.search.v3.
        
        Algorithm:
        1. Validate query
        2. Send request with optional filters (calories, recipe type, etc.)
        3. Return raw recipe results with recipe_id, name, image, nutrition
        
        Args:
            query: Recipe search query (e.g., "chicken with rice")
            page: Page number for pagination (0-indexed)
            max_calories: Optional max calories filter
            recipe_types: Optional recipe type filter (e.g., "main_course")
            
        Returns:
            Raw FatSecret recipe search results including recipe_id, nutrition
            
        Raises:
            ValidationError: If query is invalid
            FatSecretAPIError: If API request fails
            NoResultsError: If no results found
        """
        # Validate query
        if not query or not isinstance(query, str):
            raise ValidationError("Recipe query must be a non-empty string")
        
        query = query.strip()
        if len(query) < 2:
            raise ValidationError("Recipe query must be at least 2 characters")
        if len(query) > 100:
            raise ValidationError("Recipe query must be less than 100 characters")
        
        logger.info(f"Searching recipes: {query}, page {page}")
        
        params = {
            "search_expression": query,
            "page_number": str(page),
            "format": "json",
        }
        
        # Add optional filters
        if max_calories is not None and max_calories > 0:
            params["max_calories"] = str(max_calories)
        if recipe_types:
            params["recipe_types"] = recipe_types
        
        try:
            response = self._make_platform_get_request(
                self.config.FATSECRET_RECIPE_SEARCH_URL,
                params,
            )
        except Exception as platform_error:
            logger.warning(
                "FatSecret platform recipe search failed; falling back to server.api: %s",
                str(platform_error),
            )
            fallback_params = {
                **params,
                "method": "recipes.search.v3",
            }
            response = self._make_request(fallback_params)
        
        # Check if results exist
        recipes = response.get("recipes", {}).get("recipe", [])
        if not recipes:
            raise NoResultsError(f"No recipes found matching '{query}'")
        
        # Ensure recipes is a list
        if not isinstance(recipes, list):
            recipes = [recipes]
        
        return {
            "recipes": recipes,
            "total_results": len(recipes),
            "query": query,
        }

    def get_recipe_details(self, recipe_id: str) -> Dict[str, Any]:
        """
        Retrieve detailed nutrition information for a specific recipe.
        
        Algorithm:
        1. Validate recipe_id (must be numeric string)
        2. Request recipe details
        3. Extract ingredients and nutrition data
        4. Return complete recipe data
        
        Args:
            recipe_id: FatSecret recipe ID
            
        Returns:
            Detailed recipe data including ingredients and nutrition
            
        Raises:
            ValidationError: If recipe_id is invalid
            FatSecretAPIError: If API request fails
        """
        # Validate recipe_id - ensure it's a string
        if not recipe_id:
            raise ValidationError("Recipe ID must be a non-empty string")
        recipe_id = str(recipe_id).strip()
        
        if not recipe_id.isdigit():
            raise ValidationError("Recipe ID must be numeric")
        
        logger.info(f"Getting recipe details for ID: {recipe_id}")
        
        params = {
            "method": "recipe.get",
            "recipe_id": recipe_id,
            "format": "json",
        }
        
        response = self._make_request(params)
        
        recipe_data = response.get("recipe")
        if not recipe_data:
            raise NoResultsError(f"Recipe not found with ID: {recipe_id}")
        
        return recipe_data

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
