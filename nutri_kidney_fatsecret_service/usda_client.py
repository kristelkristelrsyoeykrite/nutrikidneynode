"""
USDA FoodData Central client for NutriKidney nutrition lookup.

FoodData Central nutrient values are usually reported per 100 g. This client
keeps USDA IDs namespaced as ``usda:<fdcId>`` so they can travel through the
same app paths as FatSecret food IDs without ambiguity.
"""
import os
import re
from difflib import SequenceMatcher
from typing import Any, Dict, Iterable, List, Optional

import requests

from config import get_config
from error_handler import FatSecretAPIError, NoResultsError, ValidationError


class USDAFoodDataClient:
    """Small FoodData Central lookup client."""

    SEARCH_URL = "https://api.nal.usda.gov/fdc/v1/foods/search"
    FOOD_URL = "https://api.nal.usda.gov/fdc/v1/food/{fdc_id}"
    FOOD_ID_PREFIX = "usda:"
    DEFAULT_PAGE_SIZE = 10

    NUTRIENT_NUMBERS = {
        "calories": {"208", "1008"},
        "protein": {"203", "1003"},
        "fat": {"204", "1004"},
        "carbohydrates": {"205", "1005"},
        "fiber": {"291", "1079"},
        "sugar": {"269", "2000"},
        "sodium": {"307", "1093"},
        "potassium": {"306", "1092"},
        "phosphorus": {"305", "1091"},
        "calcium": {"301", "1087"},
    }
    NUTRIENT_NAME_ALIASES = {
        "calories": {"energy", "energy (atwater general factors)", "energy (atwater specific factors)"},
        "protein": {"protein"},
        "fat": {"total lipid (fat)", "total fat", "fatty acids, total lipid"},
        "carbohydrates": {"carbohydrate, by difference", "carbohydrate, by summation"},
        "fiber": {"fiber, total dietary", "fiber, total"},
        "sugar": {"sugars, total including nlea", "sugars, total"},
        "sodium": {"sodium, na", "sodium"},
        "potassium": {"potassium, k", "potassium"},
        "phosphorus": {"phosphorus, p", "phosphorus"},
        "calcium": {"calcium, ca", "calcium"},
    }

    PREFERRED_DATA_TYPES = {
        "foundation",
        "sr legacy",
        "survey (fndds)",
    }

    def __init__(self, api_key: Optional[str] = None, timeout_seconds: Optional[int] = None):
        config = get_config()
        self.api_key = api_key or os.getenv("USDA_FDC_API_KEY") or "DEMO_KEY"
        self.timeout_seconds = timeout_seconds or config.REQUEST_TIMEOUT

    @classmethod
    def is_usda_food_id(cls, food_id: Any) -> bool:
        return str(food_id or "").strip().lower().startswith(cls.FOOD_ID_PREFIX)

    @classmethod
    def clean_food_id(cls, food_id: Any) -> str:
        value = str(food_id or "").strip()
        if value.lower().startswith(cls.FOOD_ID_PREFIX):
            value = value[len(cls.FOOD_ID_PREFIX):]
        if not value.isdigit():
            raise ValidationError("USDA food ID must be a numeric fdcId.")
        return value

    @classmethod
    def namespaced_food_id(cls, fdc_id: Any) -> str:
        return f"{cls.FOOD_ID_PREFIX}{str(fdc_id).strip()}"

    def search_foods(self, query: str, page: int = 0, page_size: int = DEFAULT_PAGE_SIZE) -> Dict[str, Any]:
        query = str(query or "").strip()
        if len(query) < 2:
            raise ValidationError("Food query must be at least 2 characters")

        try:
            response = requests.get(
                self.SEARCH_URL,
                params={
                    "api_key": self.api_key,
                    "query": query,
                    "pageNumber": int(page) + 1,
                    "pageSize": page_size,
                },
                timeout=self.timeout_seconds,
            )
            response.raise_for_status()
        except requests.exceptions.RequestException as e:
            raise FatSecretAPIError(
                "USDA FoodData Central search failed",
                details={"reason": str(e.__class__.__name__)},
            ) from e

        payload = response.json()
        foods = payload.get("foods")
        if not isinstance(foods, list) or not foods:
            raise NoResultsError(f"No USDA foods found matching '{query}'")

        ranked = self._rank_foods(query, foods)
        normalized = [self._search_food_to_nutrition(food) for _, food in ranked]
        return {
            "foods": normalized,
            "total_results": payload.get("totalHits") or len(normalized),
            "query": query,
        }

    def get_food_details(self, food_id: str) -> Dict[str, Any]:
        fdc_id = self.clean_food_id(food_id)
        try:
            response = requests.get(
                self.FOOD_URL.format(fdc_id=fdc_id),
                params={"api_key": self.api_key},
                timeout=self.timeout_seconds,
            )
            response.raise_for_status()
        except requests.exceptions.RequestException as e:
            raise FatSecretAPIError(
                "USDA FoodData Central detail lookup failed",
                details={"food_id": food_id, "reason": str(e.__class__.__name__)},
            ) from e

        payload = response.json()
        if not isinstance(payload, dict) or not payload.get("fdcId"):
            raise NoResultsError(f"USDA food not found with ID: {food_id}")

        return self._detail_food_to_nutrition(payload)

    def get_meal_logging_details(self, food_id: str) -> Dict[str, Any]:
        nutrition = self.get_food_details(food_id)
        serving = {
            "serving_id": "usda_100g",
            "serving_description": "100 g",
            "metric_serving_amount": 100,
            "metric_serving_unit": "g",
            "number_of_units": 1,
            "measurement_description": "100 g",
            "calories": nutrition.get("calories"),
            "protein": nutrition.get("protein"),
            "fat": nutrition.get("fat"),
            "carbohydrate": nutrition.get("carbohydrates"),
            "carbohydrates": nutrition.get("carbohydrates"),
            "fiber": nutrition.get("fiber"),
            "sugar": nutrition.get("sugar"),
            "sodium": nutrition.get("sodium"),
            "potassium": nutrition.get("potassium"),
            "phosphorus": nutrition.get("phosphorus"),
            "calcium": nutrition.get("calcium"),
        }
        return {
            "food_id": nutrition["food_id"],
            "fdc_id": nutrition["fdc_id"],
            "food_name": nutrition["food_name"],
            "brand_name": nutrition.get("brand_name"),
            "food_type": nutrition.get("food_type") or "USDA FoodData Central",
            "data_source": "usda",
            "source": "usda",
            "servings": {"serving": [serving]},
            "foodNutrients": nutrition.get("raw", {}).get("foodNutrients", []),
            "raw_usda": nutrition.get("raw", {}),
        }

    def _search_food_to_nutrition(self, food: Dict[str, Any]) -> Dict[str, Any]:
        nutrients = self._extract_nutrients(food.get("foodNutrients"))
        return self._base_food(food, nutrients)

    def _detail_food_to_nutrition(self, food: Dict[str, Any]) -> Dict[str, Any]:
        nutrients = self._extract_nutrients(food.get("foodNutrients"))
        normalized = self._base_food(food, nutrients)
        normalized["raw"] = food
        return normalized

    def _base_food(self, food: Dict[str, Any], nutrients: Dict[str, Optional[float]]) -> Dict[str, Any]:
        fdc_id = food.get("fdcId") or food.get("fdc_id")
        description = food.get("description") or food.get("lowercaseDescription") or "USDA food"
        serving_description = "100 g"
        data_type = food.get("dataType")
        brand_name = food.get("brandName") or food.get("brandOwner")
        return {
            "food_id": self.namespaced_food_id(fdc_id),
            "fdc_id": str(fdc_id),
            "food_name": description,
            "brand_name": brand_name,
            "food_type": data_type,
            "serving_description": serving_description,
            "serving_size": 100.0,
            "source": "usda",
            "data_source": "usda",
            **nutrients,
        }

    def _extract_nutrients(self, rows: Any) -> Dict[str, Optional[float]]:
        output: Dict[str, Optional[float]] = {key: None for key in self.NUTRIENT_NUMBERS}
        if not isinstance(rows, list):
            return output

        for row in rows:
            if not isinstance(row, dict):
                continue
            nutrient = row.get("nutrient") if isinstance(row.get("nutrient"), dict) else {}
            number = str(
                nutrient.get("number")
                or row.get("nutrientNumber")
                or row.get("nutrientId")
                or ""
            ).strip()
            name = str(
                nutrient.get("name")
                or row.get("nutrientName")
                or ""
            ).lower().strip()
            amount = row.get("amount") if row.get("amount") is not None else row.get("value")
            numeric = self._positive_or_zero_float(amount)
            if numeric is None:
                continue

            for field, numbers in self.NUTRIENT_NUMBERS.items():
                if output[field] is not None:
                    continue
                if number in numbers or name in self.NUTRIENT_NAME_ALIASES[field]:
                    output[field] = numeric
                    break

        return output

    def _rank_foods(self, query: str, foods: Iterable[Dict[str, Any]]) -> List[tuple[float, Dict[str, Any]]]:
        query_norm = self._normalize_text(query)
        query_tokens = set(query_norm.split())
        ranked: List[tuple[float, Dict[str, Any]]] = []

        for food in foods:
            description = str(food.get("description") or food.get("lowercaseDescription") or "")
            brand = str(food.get("brandName") or "")
            candidate = self._normalize_text(" ".join(part for part in [description, brand] if part))
            if not candidate:
                continue
            candidate_tokens = set(candidate.split())
            overlap = len(query_tokens & candidate_tokens) / max(len(query_tokens), 1)
            fuzzy = SequenceMatcher(None, query_norm, candidate).ratio() * 100.0
            score = (fuzzy * 0.75) + (overlap * 25.0)
            if str(food.get("dataType") or "").lower() in self.PREFERRED_DATA_TYPES:
                score += 8.0
            ranked.append((score, food))

        ranked.sort(key=lambda item: item[0], reverse=True)
        return ranked

    @staticmethod
    def _positive_or_zero_float(value: Any) -> Optional[float]:
        try:
            numeric = float(value)
        except (TypeError, ValueError):
            return None
        return numeric if numeric >= 0 else None

    @staticmethod
    def _normalize_text(value: str) -> str:
        text = str(value or "").lower()
        text = re.sub(r"\([^)]*\)", " ", text)
        text = re.sub(r"[^a-z0-9\s]+", " ", text)
        text = re.sub(r"\s+", " ", text)
        return text.strip()
