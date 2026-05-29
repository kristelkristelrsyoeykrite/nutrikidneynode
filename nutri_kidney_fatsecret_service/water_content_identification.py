"""
USDA water-content identification and fluid contribution logic.

This module keeps the USDA FoodData Central lookup separate from the
FatSecret food flow. Call it when a user selects/logs a food and you have the
child's daily fluid restriction in mL.
"""
import os
import re
from collections.abc import Iterable
from dataclasses import dataclass
from difflib import SequenceMatcher
from typing import Any, Dict, Optional

import requests


NO_WATER_DATA_MESSAGE = "No water content data available for this food."
SIGNIFICANT_FLUID_WARNING = (
    "Warning: This food may consume a large portion of your daily fluid "
    "allowance. You may need to reduce your remaining fluid intake today."
)


@dataclass(frozen=True)
class WaterContentResult:
    """
    Fluid contribution preview for one selected food.

    This object is intentionally a preview. Store its values in foodLog and
    hydrationLog only after the user confirms adding the food.
    """

    food_name: str
    serving_size: Optional[float]
    serving_unit: Optional[str]
    usda_water_content_grams: Optional[float]
    water_content_ml: float
    is_liquid_or_drink: bool
    drink_fluid_ml: float
    total_fluid_contribution_ml: float
    daily_fluid_limit_ml: float
    current_daily_fluid_consumed_ml: float
    updated_daily_fluid_consumed_ml: float
    remaining_fluid_allowance_ml: float
    fluid_contribution_percent: Optional[float]
    show_fluid_warning: bool
    warning: Optional[str]
    message: Optional[str]
    water_data_available: bool
    source: str = "FatSecret"

    def to_dict(self) -> Dict[str, Any]:
        return {
            "food_name": self.food_name,
            "serving_size": self.serving_size,
            "serving_unit": self.serving_unit,
            "source": self.source,
            "usda_water_content_grams": self.usda_water_content_grams,
            "water_content_ml": self.water_content_ml,
            "is_liquid_or_drink": self.is_liquid_or_drink,
            "drink_fluid_ml": self.drink_fluid_ml,
            "total_fluid_contribution_ml": self.total_fluid_contribution_ml,
            "daily_fluid_limit_ml": self.daily_fluid_limit_ml,
            "current_daily_fluid_consumed_ml": self.current_daily_fluid_consumed_ml,
            "updated_daily_fluid_consumed_ml": self.updated_daily_fluid_consumed_ml,
            "remaining_fluid_allowance_ml": self.remaining_fluid_allowance_ml,
            "fluid_contribution_percent": self.fluid_contribution_percent,
            "show_fluid_warning": self.show_fluid_warning,
            "warning": self.warning,
            "message": self.message,
            "water_data_available": self.water_data_available,
        }

    def food_log_fields(self) -> Dict[str, Any]:
        """Fields to merge into foodLog after user confirmation."""
        return {
            "foodName": self.food_name,
            "servingSize": self.serving_size,
            "servingUnit": self.serving_unit,
            "source": self.source,
            "usdaWaterContentGrams": self.usda_water_content_grams,
            "waterContentMl": self.water_content_ml,
            "isLiquidOrDrink": self.is_liquid_or_drink,
            "drinkFluidMl": self.drink_fluid_ml,
            "totalFluidContributionMl": self.total_fluid_contribution_ml,
            "fluidContributionPercent": self.fluid_contribution_percent,
            "showFluidWarning": self.show_fluid_warning,
        }

    def hydration_log_fields(
        self,
        user_id: str,
        food_log_id: str,
        logged_at: Any,
    ) -> Optional[Dict[str, Any]]:
        """Hydration log payload after confirmation, or None when no fluid is added."""
        if self.total_fluid_contribution_ml <= 0:
            return None

        return {
            "userId": user_id,
            "source": "foodLog",
            "foodLogId": food_log_id,
            "amountMl": self.total_fluid_contribution_ml,
            "type": "drink" if self.is_liquid_or_drink else "food_water",
            "loggedAt": logged_at,
        }


class USDAWaterContentIdentifier:
    """Fetches USDA water data and computes fluid contribution warnings."""

    USDA_SEARCH_URL = "https://api.nal.usda.gov/fdc/v1/foods/search"
    USDA_FOOD_URL = "https://api.nal.usda.gov/fdc/v1/food/{fdc_id}"
    WATER_NUTRIENT_NAME = "water"
    WATER_NUTRIENT_NUMBER = "255"
    WARNING_THRESHOLD_PERCENT = 20.0
    USDA_SEARCH_PAGE_SIZE = 12
    USDA_DETAIL_LOOKUP_LIMIT = 4
    MIN_FUZZY_MATCH_SCORE = 45.0
    PREFERRED_DATA_TYPES = {
        "foundation",
        "sr legacy",
        "survey (fndds)",
    }
    GENERIC_PREP_WORDS = {
        "raw",
        "fresh",
        "frozen",
        "cooked",
        "boiled",
        "fried",
        "grilled",
        "baked",
        "roasted",
        "homemade",
        "recipe",
        "generic",
        "brand",
        "with",
        "without",
    }
    LIQUID_CATEGORY_KEYWORDS = {
        "beverage",
        "drink",
        "juice",
        "milk",
        "coffee",
        "tea",
        "soup",
        "smoothie",
        "soft drink",
        "water",
    }

    def __init__(
        self,
        api_key: Optional[str] = None,
        timeout_seconds: int = 10,
    ) -> None:
        self.api_key = api_key or os.getenv("USDA_FDC_API_KEY") or "DEMO_KEY"
        self.timeout_seconds = timeout_seconds

    def analyze_selected_food(
        self,
        food_name: str,
        daily_fluid_limit_ml: float,
        total_daily_fluid_consumed_ml: float = 0.0,
        fdc_id: Optional[str] = None,
        fatsecret_food_details: Optional[Dict[str, Any]] = None,
        serving_amount_grams: Optional[float] = None,
        serving_size: Optional[float] = None,
        serving_unit: Optional[str] = None,
    ) -> WaterContentResult:
        """
        Build a user-facing preview before saving the food log.

        Rule to avoid double-counting:
        - Liquid/drink: totalFluidFromFood = servingAmountMl.
        - Solid food: totalFluidFromFood = USDA waterContentMl.
        """
        limit_ml = self._positive_float(daily_fluid_limit_ml)
        consumed_ml = max(float(total_daily_fluid_consumed_ml or 0.0), 0.0)

        if limit_ml is None:
            raise ValueError("daily_fluid_limit_ml must be greater than 0.")

        details = fatsecret_food_details or {}
        detected_serving_grams = self._positive_float(serving_amount_grams)
        if detected_serving_grams is None:
            detected_serving_grams = self._extract_serving_amount_grams(details)
        display_serving_size = serving_size
        if display_serving_size is None:
            display_serving_size = detected_serving_grams
        display_serving_unit = serving_unit or self._extract_serving_unit(details)

        is_liquid = self.is_liquid_or_drink(food_name, details)
        water_grams = self.fetch_water_content_grams(food_name, fdc_id=fdc_id)
        water_data_available = water_grams is not None

        # 1 g water is approximately 1 mL water.
        water_content_ml = water_grams if water_grams is not None else 0.0

        # For water-like liquids, serving grams are treated as mL by approximation.
        drink_fluid_ml = detected_serving_grams if is_liquid and detected_serving_grams else 0.0
        total_fluid_ml = drink_fluid_ml if is_liquid else water_content_ml

        contribution_percent = (
            (total_fluid_ml / limit_ml) * 100.0 if total_fluid_ml > 0 else None
        )
        updated_total_ml = consumed_ml + total_fluid_ml
        remaining_ml = limit_ml - updated_total_ml
        show_warning = (
            contribution_percent is not None
            and contribution_percent >= self.WARNING_THRESHOLD_PERCENT
        )
        warning = (
            SIGNIFICANT_FLUID_WARNING
            if show_warning
            else None
        )
        message = None if water_data_available else NO_WATER_DATA_MESSAGE

        return WaterContentResult(
            food_name=food_name,
            serving_size=self._round_optional(display_serving_size),
            serving_unit=display_serving_unit,
            usda_water_content_grams=self._round_optional(water_grams),
            water_content_ml=round(water_content_ml, 2),
            is_liquid_or_drink=is_liquid,
            drink_fluid_ml=round(drink_fluid_ml, 2),
            total_fluid_contribution_ml=round(total_fluid_ml, 2),
            daily_fluid_limit_ml=round(limit_ml, 2),
            current_daily_fluid_consumed_ml=round(consumed_ml, 2),
            updated_daily_fluid_consumed_ml=round(updated_total_ml, 2),
            remaining_fluid_allowance_ml=round(remaining_ml, 2),
            fluid_contribution_percent=self._round_optional(contribution_percent),
            show_fluid_warning=show_warning,
            warning=warning,
            message=message,
            water_data_available=water_data_available,
        )

    def is_liquid_or_drink(
        self,
        food_name: str,
        fatsecret_food_details: Optional[Dict[str, Any]] = None,
    ) -> bool:
        """Detect liquid/drink foods from FatSecret fields and food name."""
        details = fatsecret_food_details or {}
        text_parts = [
            food_name,
            details.get("food_name"),
            details.get("food_type"),
            details.get("food_description"),
            details.get("food_url"),
            details.get("brand_name"),
            details.get("category"),
            details.get("food_category"),
            details.get("foodCategory"),
        ]

        categories = details.get("categories") or details.get("food_categories")
        if isinstance(categories, Iterable) and not isinstance(categories, (str, bytes, dict)):
            text_parts.extend(str(item) for item in categories)

        haystack = " ".join(str(part or "").lower() for part in text_parts)
        return any(keyword in haystack for keyword in self.LIQUID_CATEGORY_KEYWORDS)

    def fetch_water_content_grams(
        self,
        food_name: str,
        fdc_id: Optional[str] = None,
    ) -> Optional[float]:
        """Return USDA Water nutrient grams, or None when unavailable."""
        food_data = self._fetch_food_by_id(fdc_id) if fdc_id else None
        if food_data is None:
            return self._search_best_water_grams(food_name)
        return self._extract_water_grams(food_data)

    def _search_best_water_grams(self, food_name: str) -> Optional[float]:
        query = self._clean_search_query(food_name)
        if not query:
            return None

        response = requests.get(
            self.USDA_SEARCH_URL,
            params={
                "api_key": self.api_key,
                "query": query,
                "pageSize": self.USDA_SEARCH_PAGE_SIZE,
            },
            timeout=self.timeout_seconds,
        )
        response.raise_for_status()
        payload = response.json()
        foods = payload.get("foods")
        if not isinstance(foods, list) or not foods:
            return None

        ranked_foods = self._rank_usda_foods(query, foods)
        if not ranked_foods:
            return None

        for score, food in ranked_foods:
            if score < self.MIN_FUZZY_MATCH_SCORE:
                continue
            water_grams = self._extract_water_grams(food)
            if water_grams is not None:
                return water_grams

        for score, food in ranked_foods[: self.USDA_DETAIL_LOOKUP_LIMIT]:
            if score < self.MIN_FUZZY_MATCH_SCORE:
                continue
            fdc_id = food.get("fdcId") or food.get("fdc_id")
            detailed_food = self._fetch_food_by_id(str(fdc_id)) if fdc_id else None
            if not detailed_food:
                continue
            water_grams = self._extract_water_grams(detailed_food)
            if water_grams is not None:
                return water_grams

        return None

    def _rank_usda_foods(
        self,
        query: str,
        foods: Iterable[Dict[str, Any]],
    ) -> list[tuple[float, Dict[str, Any]]]:
        query_tokens = set(self._tokenize(query))
        ranked: list[tuple[float, Dict[str, Any]]] = []

        for food in foods:
            if not isinstance(food, dict):
                continue
            description = str(food.get("description") or food.get("lowercaseDescription") or "")
            brand = str(food.get("brandName") or "")
            data_type = str(food.get("dataType") or "").lower()
            candidate_text = " ".join(part for part in [description, brand] if part)
            normalized_candidate = self._normalize_text(candidate_text)
            if not normalized_candidate:
                continue

            candidate_tokens = set(self._tokenize(normalized_candidate))
            token_overlap = (
                len(query_tokens & candidate_tokens) / max(len(query_tokens), 1)
                if query_tokens
                else 0.0
            )
            fuzzy_score = self._fuzzy_ratio(query, normalized_candidate)
            score = (fuzzy_score * 0.75) + (token_overlap * 25.0)

            if data_type in self.PREFERRED_DATA_TYPES:
                score += 8.0
            if str(food.get("foodCategory") or "").lower() in {"fruits and fruit juices", "vegetables and vegetable products"}:
                score += 3.0
            if description and self._normalize_text(description) == self._normalize_text(query):
                score += 12.0

            ranked.append((score, food))

        ranked.sort(key=lambda item: item[0], reverse=True)
        return ranked

    def _fetch_food_by_id(self, fdc_id: Optional[str]) -> Optional[Dict[str, Any]]:
        clean_id = str(fdc_id or "").strip()
        if not clean_id:
            return None

        response = requests.get(
            self.USDA_FOOD_URL.format(fdc_id=clean_id),
            params={"api_key": self.api_key},
            timeout=self.timeout_seconds,
        )
        response.raise_for_status()
        payload = response.json()
        return payload if isinstance(payload, dict) else None

    def _extract_water_grams(self, food_data: Dict[str, Any]) -> Optional[float]:
        nutrients = food_data.get("foodNutrients")
        if not isinstance(nutrients, list):
            return None

        for nutrient_row in nutrients:
            if not isinstance(nutrient_row, dict):
                continue
            nutrient = nutrient_row.get("nutrient")
            nutrient_name = ""
            nutrient_number = ""

            if isinstance(nutrient, dict):
                nutrient_name = str(nutrient.get("name") or "").lower().strip()
                nutrient_number = str(nutrient.get("number") or "").strip()
            else:
                nutrient_name = str(nutrient_row.get("nutrientName") or "").lower().strip()
                nutrient_number = str(nutrient_row.get("nutrientNumber") or "").strip()

            is_water = (
                nutrient_name == self.WATER_NUTRIENT_NAME
                or nutrient_number == self.WATER_NUTRIENT_NUMBER
            )
            if not is_water:
                continue

            amount = (
                nutrient_row.get("amount")
                if nutrient_row.get("amount") is not None
                else nutrient_row.get("value")
            )
            return self._positive_float(amount)

        return None

    def _extract_serving_amount_grams(self, details: Dict[str, Any]) -> Optional[float]:
        serving = self._first_serving(details)
        if serving:
            amount = (
                serving.get("metric_serving_amount")
                or serving.get("metricServingAmount")
                or serving.get("serving_amount")
                or serving.get("servingAmount")
            )
            unit = (
                serving.get("metric_serving_unit")
                or serving.get("metricServingUnit")
                or serving.get("serving_unit")
                or serving.get("servingUnit")
            )
            if str(unit or "").lower().strip() in {"g", "gram", "grams"}:
                return self._positive_float(amount)
        return self._positive_float(
            details.get("metric_serving_amount")
            or details.get("metricServingAmount")
            or details.get("serving_amount")
            or details.get("servingAmount")
        )

    def _extract_serving_unit(self, details: Dict[str, Any]) -> Optional[str]:
        serving = self._first_serving(details)
        if serving:
            unit = (
                serving.get("metric_serving_unit")
                or serving.get("metricServingUnit")
                or serving.get("serving_unit")
                or serving.get("servingUnit")
            )
            if unit:
                return str(unit)
        unit = details.get("metric_serving_unit") or details.get("serving_unit")
        return str(unit) if unit else None

    @staticmethod
    def _first_serving(details: Dict[str, Any]) -> Optional[Dict[str, Any]]:
        servings = details.get("servings")
        if isinstance(servings, dict):
            serving = servings.get("serving")
            if isinstance(serving, list) and serving:
                return serving[0] if isinstance(serving[0], dict) else None
            if isinstance(serving, dict):
                return serving
        if isinstance(servings, list) and servings:
            return servings[0] if isinstance(servings[0], dict) else None
        return None

    @staticmethod
    def _round_optional(value: Any) -> Optional[float]:
        try:
            return round(float(value), 2)
        except (TypeError, ValueError):
            return None

    @staticmethod
    def _positive_float(value: Any) -> Optional[float]:
        try:
            numeric = float(value)
        except (TypeError, ValueError):
            return None
        return numeric if numeric > 0 else None

    @classmethod
    def _clean_search_query(cls, value: str) -> str:
        normalized = cls._normalize_text(value)
        tokens = [
            token
            for token in normalized.split()
            if token and token not in cls.GENERIC_PREP_WORDS
        ]
        return " ".join(tokens) or normalized

    @staticmethod
    def _normalize_text(value: str) -> str:
        text = str(value or "").lower()
        text = re.sub(r"\([^)]*\)", " ", text)
        text = re.sub(r"[^a-z0-9\s]+", " ", text)
        text = re.sub(r"\s+", " ", text)
        return text.strip()

    @classmethod
    def _tokenize(cls, value: str) -> list[str]:
        return [token for token in cls._normalize_text(value).split() if token]

    @classmethod
    def _fuzzy_ratio(cls, a: str, b: str) -> float:
        a = cls._normalize_text(a)
        b = cls._normalize_text(b)
        if not a or not b:
            return 0.0
        try:
            from rapidfuzz import fuzz  # type: ignore

            return float(fuzz.token_set_ratio(a, b))
        except Exception:
            return SequenceMatcher(None, a, b).ratio() * 100.0
