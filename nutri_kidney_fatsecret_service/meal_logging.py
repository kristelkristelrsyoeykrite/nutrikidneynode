"""
NutriKidney staged meal logging service.

Flow:
1. Search returns selectable foods only.
2. Selected food_id retrieves FatSecret food.get.v5 servings/nutrients.
3. Preview calculates serving totals and CKD interpretation.
4. Save stores the finalized meal and refreshes daily summaries.
"""
import json
import logging
import os
import re
from copy import deepcopy
from datetime import datetime, timezone
from difflib import SequenceMatcher
from typing import Any, Dict, List, Optional
from uuid import uuid4

from config import get_config
from error_handler import NoResultsError, ValidationError, FatSecretAPIError
from error_handler import TimeoutError as ServiceTimeoutError
from fatsecret_client import FatSecretClient
from food_matcher import FoodMatcher
from models import (
    ChildProfileContext,
    MealFoodDetailsResult,
    MealLoggingFoodChoice,
    MealLoggingSearchResult,
    MealLogRecord,
    MealNutrients,
    MealPreviewRequest,
    MealPreviewResult,
    MealSaveRequest,
    MealSaveResult,
    MealServing,
)
from response_formatter import ResponseFormatter
from phosphorus_service import get_phosphorus_guide

logger = logging.getLogger(__name__)


_SPACY_NLP = None
_SPACY_LOAD_ATTEMPTED = False


class MealLoggingService:
    """Staged NutriKidney meal logging workflow."""

    GENERIC_GOOGLE_LABELS = {
        "food",
        "ingredient",
        "meat",
        "fried food",
        "dish",
        "cuisine",
        "fast food",
        "tableware",
        "condiment",
        "cooking",
        "recipe",
        "meal",
        "dishware",
        "serveware",
    }

    NON_INGREDIENT_TOKENS = {
        "food",
        "ingredient",
        "dish",
        "cuisine",
        "meat",
        "fast",
        "fried",
        "grilled",
        "roasted",
        "baked",
        "boiled",
        "steamed",
        "breaded",
        "coated",
        "crispy",
        "spicy",
        "deep",
        "tableware",
        "condiment",
        "cooking",
        "recipe",
        "meal",
    }

    CORE_NUTRIENTS = [
        "calories",
        "protein",
        "fat",
        "carbohydrate",
        "sodium",
        "potassium",
    ]

    OPTIONAL_NUTRIENTS = [
        "fiber",
        "sugar",
        "calcium",
        "iron",
        "cholesterol",
        "saturated_fat",
        "vitamin_a",
        "vitamin_c",
        "vitamin_d",
    ]

    PREPARATION_TOKENS = {
        "fried",
        "crispy",
        "grilled",
        "roasted",
        "baked",
        "boiled",
        "steamed",
        "breaded",
        "coated",
        "spicy",
    }

    UNREQUESTED_SPECIFICITY_TOKENS = {
        "skin",
        "skins",
        "breast",
        "thigh",
        "wing",
        "wings",
        "drumstick",
        "drumsticks",
        "liver",
        "gizzard",
        "feet",
    }

    REMOVABLE_ADJECTIVES = {
        "crispy",
        "fresh",
        "tasty",
        "delicious",
        "savory",
        "yummy",
        "golden",
        "hot",
        "cold",
    }

    NUTRIENT_ALIASES = {
        "calories": ["calories"],
        "protein": ["protein"],
        "fat": ["fat"],
        "carbohydrate": ["carbohydrate", "carbohydrates", "carbs"],
        "sodium": ["sodium"],
        "potassium": ["potassium"],
        "fiber": ["fiber"],
        "sugar": ["sugar"],
        "calcium": ["calcium"],
        "iron": ["iron"],
        "cholesterol": ["cholesterol"],
        "saturated_fat": ["saturated_fat", "saturated_fatty_acids", "sat_fat"],
        "vitamin_a": ["vitamin_a"],
        "vitamin_c": ["vitamin_c"],
        "vitamin_d": ["vitamin_d"],
    }

    def __init__(self, fatsecret_client: Optional[FatSecretClient] = None):
        self.config = get_config()
        self.fatsecret_client = fatsecret_client or FatSecretClient()
        self.image_handler = None
        self.food_matcher = FoodMatcher(
            weak_labels=self.GENERIC_GOOGLE_LABELS,
            prep_tokens=self.PREPARATION_TOKENS,
        )
        self._food_details_cache: Dict[str, Dict[str, Any]] = {}

    def search(self, query: str, page: int = 0) -> Dict[str, Any]:
        """Search FatSecret for selectable food choices only."""
        normalized_query = self._normalize_query(query)

        try:
            raw_results = self.fatsecret_client.search_foods(normalized_query, page)
        except Exception as e:
            logger.error("Meal logging food search failed", exc_info=True)
            raise FatSecretAPIError(
                "Food search is temporarily unavailable.",
                details={"reason": str(e.__class__.__name__)},
            )

        choices = [
            self._search_item_to_choice(item)
            for item in raw_results.get("foods", [])
            if item.get("food_id") and item.get("food_name")
        ]

        result = MealLoggingSearchResult(
            query=query,
            normalized_query=normalized_query,
            choices=choices,
            total_results=raw_results.get("total_results", len(choices)),
        )
        return ResponseFormatter.success_response("meal_logging_search", result)

    def food_details(self, food_id: str) -> Dict[str, Any]:
        """Retrieve food.get.v5 details and apply NutriKidney interpretation."""
        details = self._get_raw_food_details(food_id)
        result = self._build_food_details_result(details)
        return ResponseFormatter.success_response("meal_logging_food_details", result)

    def recognize_image(self, image_data: bytes, content_type: str) -> Dict[str, Any]:
        """
        Recognize a food image and return the best FatSecret nutrition match.

        Flow:
        1. Try FatSecret image recognition.
        2. If FatSecret succeeds, retrieve food.get.v5 for that food.
        3. If FatSecret fails, use Google Vision food labels.
        4. If labels are not food-like, stop with a controlled error.
        5. Use RapidFuzz to select the best FatSecret search result.
        6. Return the selected food details and serving nutrients.
        """
        if self.image_handler is None:
            # Lazy import to keep FastAPI startup fast (PIL/vision deps live here).
            from image_recognition import ImageRecognitionHandler

            self.image_handler = ImageRecognitionHandler(self.fatsecret_client)

        detection = self.image_handler.detect_food_candidates(image_data, content_type)
        warnings = detection.get("warnings", [])
        source = detection.get("source", "manual")
        candidates = detection.get("candidates", [])

        if source == "fatsecret" and candidates:
            # Do not blindly trust the first FatSecret recognition item.
            # Rank candidates via foods.search + matcher before picking a food_id.
            label_candidates = [
                str(item.get("food_name") or "").strip()
                for item in (candidates or [])
                if item.get("food_name")
            ]
            selected = None
            if label_candidates:
                selected = self._best_fatsecret_match(label_candidates)

            if not selected:
                selected = candidates[0]

            food_id = selected.get("food_id")
            if not food_id and selected.get("food_name"):
                selected = self._best_fatsecret_match(selected.get("food_name", "food"))
                food_id = selected["food_id"]

            details = self._get_raw_food_details(str(food_id))
            food = self._build_food_details_result(details)

            raw_confidence = selected.get("confidence")
            if isinstance(raw_confidence, str):
                confidence_bucket = raw_confidence
            elif "score" in selected:
                confidence_bucket = self.food_matcher.confidence_bucket(
                    float(selected.get("score") or 0.0)
                )
            else:
                try:
                    numeric_confidence = float(raw_confidence or 0.0)
                except Exception:
                    numeric_confidence = 0.0
                confidence_bucket = (
                    "high"
                    if numeric_confidence >= 0.85
                    else "medium"
                    if numeric_confidence >= 0.65
                    else "low"
                )

            return ResponseFormatter.success_response(
                "meal_logging_image_recognition",
                {
                    "source": "fatsecret",
                    "matched_label": selected.get("food_name") or food.food_name,
                    "match_score": selected.get("score") or selected.get("confidence"),
                    "match_confidence": confidence_bucket,
                    "needs_confirmation": (confidence_bucket != "high"),
                    "suggested_matches": selected.get("top_matches") or [],
                    "food": food.model_dump(),
                    "warnings": warnings,
                    "message": (
                        "Food recognized with FatSecret image recognition."
                        if confidence_bucket == "high"
                        else "Is this the food you logged? Please confirm the suggested match."
                        if confidence_bucket == "medium"
                        else "We couldn't confidently match this food. Please choose from the suggested matches."
                    ),
                },
            )

        if source != "google_vision" or not candidates:
            raise NoResultsError("The image could not be identified as food.")

        label_analysis = self._google_label_analysis(candidates)
        label_queries = label_analysis["queries"]
        if not label_queries:
            raise NoResultsError("The image could not be identified as food.")

        selected = self._best_fatsecret_match(label_queries)
        matched_label = selected.get("matched_query") or label_queries[0]
        details = self._get_raw_food_details(selected["food_id"])
        food = self._build_food_details_result(details)
        recognized_foods = [food.model_dump()]

        multi_queries = (
            label_analysis["ingredient_labels"]
            if len(label_analysis["ingredient_labels"]) > 1
            else label_analysis["dish_labels"][:3]
        )
        additional_matches = self._best_fatsecret_matches(multi_queries)
        for match in additional_matches:
            if str(match.get("food_id")) == str(selected.get("food_id")):
                continue
            try:
                match_details = self._get_raw_food_details(match["food_id"])
                matched_food = self._build_food_details_result(match_details)
                recognized_foods.append(matched_food.model_dump())
            except Exception:
                logger.warning(
                    "Skipping additional ingredient match '%s' due to details lookup failure",
                    match.get("food_name") or match.get("matched_query"),
                )

        return ResponseFormatter.success_response(
            "meal_logging_image_recognition",
            {
                "source": "google_vision_rapidfuzz",
                "recognition_mode": label_analysis["recognition_mode"],
                "matched_label": matched_label,
                "google_labels": label_queries,
                "dish_labels": label_analysis["dish_labels"],
                "ingredient_labels": label_analysis["ingredient_labels"],
                "match_score": selected["score"],
                "match_confidence": selected.get("confidence") or "unknown",
                "needs_confirmation": (selected.get("confidence") != "high"),
                "suggested_matches": selected.get("top_matches") or [],
                "food": food.model_dump(),
                "recognized_foods": recognized_foods,
                "warnings": warnings,
                "message": (
                    "Food recognized with Google Vision and matched to FatSecret."
                    if selected.get("confidence") == "high"
                    else "Is this the food you logged? Please confirm the suggested match."
                    if selected.get("confidence") == "medium"
                    else "We couldn't confidently match this food. Please choose from the suggested matches."
                ),
            },
        )

    def _google_label_queries(self, candidates: List[Dict[str, Any]]) -> List[str]:
        """Prefer specific food labels and skip generic Google Vision labels."""
        return self._google_label_analysis(candidates)["queries"]

    def _google_label_analysis(self, candidates: List[Dict[str, Any]]) -> Dict[str, Any]:
        """Build both dish-level and ingredient-level queries from Google Vision labels."""
        labels = [
            str(candidate.get("food_name", "")).strip()
            for candidate in candidates
            if candidate.get("food_name")
        ]
        filtered = []
        seen = set()
        for label in labels:
            normalized = " ".join(label.lower().split())
            if normalized in self.GENERIC_GOOGLE_LABELS or normalized in seen:
                continue
            filtered.append(label)
            seen.add(normalized)

        filtered.sort(
            key=lambda value: (
                self._google_label_priority(value),
                len(value.split()),
                len(value),
            ),
            reverse=True,
        )

        collapsed = []
        collapsed_token_sets = []
        for label in filtered:
            label_tokens = self._food_tokens(label)
            if not label_tokens:
                continue

            is_generic_duplicate = False
            for existing_tokens in collapsed_token_sets:
                has_specific_prep = bool(existing_tokens & self.PREPARATION_TOKENS)
                if has_specific_prep and label_tokens < existing_tokens:
                    is_generic_duplicate = True
                    break

            if is_generic_duplicate:
                continue

            collapsed.append(label)
            collapsed_token_sets.append(label_tokens)

        dish_labels = collapsed[:5]
        ingredient_labels = self._extract_ingredient_labels(dish_labels)
        queries = list(dish_labels)

        if ingredient_labels:
            combined = " ".join(ingredient_labels[:3]).strip()
            if combined and combined.lower() not in {query.lower() for query in queries}:
                queries.append(combined)
            for ingredient in ingredient_labels[:5]:
                if ingredient.lower() not in {query.lower() for query in queries}:
                    queries.append(ingredient)

        recognition_mode = "ingredient_based" if ingredient_labels else "single_food"
        if any(len(label.split()) > 1 for label in dish_labels):
            recognition_mode = "single_food_or_ingredients" if ingredient_labels else "single_food"

        logger.info(
            "Google Vision label analysis: dish_labels=%s ingredient_labels=%s recognition_mode=%s",
            dish_labels,
            ingredient_labels,
            recognition_mode,
        )
        return {
            "queries": queries,
            "dish_labels": dish_labels,
            "ingredient_labels": ingredient_labels,
            "recognition_mode": recognition_mode,
        }

    def _google_label_priority(self, label: str) -> int:
        """Prioritize specific dish names over generic scene/context labels."""
        normalized = " ".join(label.lower().split())
        if normalized in self.GENERIC_GOOGLE_LABELS:
            return 0

        tokens = self._food_tokens(label)
        if not tokens:
            return 0

        if tokens & {"tableware", "condiment", "cooking", "recipe"}:
            return 1

        # Single specific dish names like "omurice" should be tried early.
        if len(tokens) == 1:
            return 4

        # Multi-word food labels like "fried chicken" stay high priority too.
        if tokens & self.PREPARATION_TOKENS:
            return 5

        return 3

    def _extract_ingredient_labels(self, labels: List[str]) -> List[str]:
        """Extract likely ingredient tokens from Google Vision labels."""
        ingredients = []
        seen = set()
        for label in labels:
            for token in self._food_tokens(label):
                if token in self.NON_INGREDIENT_TOKENS:
                    continue
                if token in self.PREPARATION_TOKENS:
                    continue
                if token in seen:
                    continue
                seen.add(token)
                ingredients.append(token)
        return ingredients[:6]

    def preview(self, request: MealPreviewRequest) -> Dict[str, Any]:
        """Calculate final nutrients and CKD interpretation without saving."""
        result = self._build_preview(request)
        return ResponseFormatter.success_response("meal_logging_preview", result)

    def save(self, request: MealSaveRequest) -> Dict[str, Any]:
        """Recompute preview, save meal log, then refresh daily summaries."""
        preview_request = MealPreviewRequest(**request.model_dump())
        preview = self._build_preview(preview_request)
        now = datetime.now(timezone.utc)

        meal_log = MealLogRecord(
            **preview.model_dump(),
            meal_log_id=str(uuid4()),
            created_at=now,
            updated_at=now,
        )

        records = self._read_json_list(self.config.MEAL_LOG_STORAGE_PATH)
        records.append(meal_log.model_dump(mode="json"))
        self._write_json_list(self.config.MEAL_LOG_STORAGE_PATH, records)

        daily_summary_status = "updated"
        try:
            self._recompute_daily_summary(
                meal_log.child_profile_id,
                meal_log.logged_at.date().isoformat(),
            )
        except Exception:
            logger.error("Daily summary aggregation failed after meal save", exc_info=True)
            daily_summary_status = "queued_for_retry"

        result = MealSaveResult(
            meal_log=meal_log,
            daily_summary_status=daily_summary_status,
            audit_status="recorded",
        )
        return ResponseFormatter.success_response("meal_logging_save", result)

    def _build_preview(self, request: MealPreviewRequest) -> MealPreviewResult:
        if request.logged_at is None:
            raise ValidationError("Meal logging requires a valid date-time.")

        details = self._get_raw_food_details(request.food_id)
        food_details = self._build_food_details_result(details)
        serving = self._find_serving(food_details.servings, request.serving_id)
        final_nutrients = self._multiply_nutrients(serving.nutrients, request.quantity)
        child_context = request.child_context or self._get_child_context(
            request.child_profile_id
        )
        safety = self._build_safety_interpretation(
            food_details,
            serving,
            final_nutrients,
            child_context,
        )

        return MealPreviewResult(
            preview_id=str(uuid4()),
            user_id=request.user_id,
            child_profile_id=request.child_profile_id,
            meal_type=request.meal_type,
            logged_at=request.logged_at,
            food_id=food_details.food_id,
            food_name=food_details.food_name,
            brand_name=food_details.brand_name,
            food_type=food_details.food_type,
            selected_serving_id=serving.serving_id,
            selected_serving_description=serving.serving_description,
            selected_quantity=request.quantity,
            base_serving=serving,
            base_serving_nutrients=serving.nutrients,
            final_nutrients=final_nutrients,
            phosphorus_tag=food_details.phosphorus_tag,
            phosphorus_confidence=food_details.phosphorus_confidence,
            phosphorus_note=food_details.phosphorus_note,
            potassium_reliability_note=food_details.potassium_reliability_note,
            safety_flags=safety["safety_flags"],
            insights=safety["insights"],
            child_context_snapshot=child_context,
            user_notes=request.user_notes,
        )

    def _get_raw_food_details(self, food_id: str) -> Dict[str, Any]:
        if food_id in self._food_details_cache:
            return deepcopy(self._food_details_cache[food_id])

        try:
            details = self.fatsecret_client.get_food_details_v5(food_id)
        except Exception as e:
            logger.error("FatSecret food.get.v5 failed", exc_info=True)
            raise FatSecretAPIError(
                "Food details are temporarily unavailable. Please try another item.",
                details={"food_id": food_id, "reason": str(e.__class__.__name__)},
            )

        self._food_details_cache[food_id] = deepcopy(details)
        return details

    def _build_food_details_result(self, details: Dict[str, Any]) -> MealFoodDetailsResult:
        servings = self._extract_servings(details)
        if not servings:
            raise NoResultsError("This item cannot be logged right now because no servings were returned.")

        phosphorus = self._tag_phosphorus(details)
        phosphorus_value = (
            phosphorus.get("phosphorus", {})
            .get("phosphorus", {})
            .get("value_mg")
        )
        if phosphorus_value is not None:
            for serving in servings:
                serving.nutrients.phosphorus = phosphorus_value

        potassium_note = (
            "Potassium is provider-estimated only. Use with caution for CKD decisions."
        )

        safety_flags = []
        if any(serving.is_derived_display_only for serving in servings):
            safety_flags.append(
                {
                    "type": "derived_serving",
                    "severity": "info",
                    "message": (
                        "Some standardized servings are display-only from FatSecret "
                        "and should not be used to create provider-side food entries."
                    ),
                }
            )

        return MealFoodDetailsResult(
            food_id=str(details.get("food_id")),
            food_name=details.get("food_name", "Unknown food"),
            brand_name=details.get("brand_name"),
            food_type=details.get("food_type"),
            servings=servings,
            phosphorus_tag=phosphorus["tag"],
            phosphorus_confidence=phosphorus["confidence"],
            phosphorus_note=phosphorus["note"],
            phosphorus=phosphorus["phosphorus"],
            potassium_reliability_note=potassium_note,
            safety_flags=safety_flags,
        )

    def _extract_servings(self, details: Dict[str, Any]) -> List[MealServing]:
        raw_servings = details.get("servings", {}).get("serving")
        if isinstance(raw_servings, dict):
            raw_servings = [raw_servings]
        if not isinstance(raw_servings, list):
            return []

        servings = []
        for raw in raw_servings:
            serving_id = str(raw.get("serving_id", "0"))
            serving_description = raw.get("serving_description")
            number_of_units = self._to_float(raw.get("number_of_units"))
            measurement_description = raw.get("measurement_description")
            metric_amount = self._to_float(raw.get("metric_serving_amount"))
            metric_unit = raw.get("metric_serving_unit")

            servings.append(
                MealServing(
                    serving_id=serving_id,
                    serving_description=serving_description,
                    metric_serving_amount=metric_amount,
                    metric_serving_unit=metric_unit,
                    number_of_units=number_of_units,
                    measurement_description=measurement_description,
                    display_text=self._serving_display_text(
                        serving_description,
                        number_of_units,
                        measurement_description,
                        metric_amount,
                        metric_unit,
                    ),
                    nutrients=self._extract_nutrients(raw),
                    raw_serving=raw,
                    is_derived_display_only=serving_id == "0",
                )
            )

        return servings

    def _extract_nutrients(self, raw: Dict[str, Any]) -> MealNutrients:
        nutrients = {}
        for nutrient, aliases in self.NUTRIENT_ALIASES.items():
            value = None
            for alias in aliases:
                if alias in raw:
                    value = self._to_float(raw.get(alias))
                    break
            nutrients[nutrient] = value

        return MealNutrients(**nutrients)

    def _multiply_nutrients(self, nutrients: MealNutrients, quantity: float) -> MealNutrients:
        calculated = {}
        for key, value in nutrients.model_dump().items():
            calculated[key] = round(value * quantity, 4) if value is not None else None
        return MealNutrients(**calculated)

    def _build_safety_interpretation(
        self,
        food_details: MealFoodDetailsResult,
        serving: MealServing,
        final_nutrients: MealNutrients,
        child_context: ChildProfileContext,
    ) -> Dict[str, List[Dict[str, Any]]]:
        flags = list(food_details.safety_flags)
        insights = []
        targets = child_context.targets

        sodium = final_nutrients.sodium
        sodium_limit = targets.get("sodium")
        if sodium is None:
            flags.append(
                {
                    "type": "missing_sodium",
                    "severity": "caution",
                    "message": "Sodium data is missing for this serving.",
                }
            )
        elif sodium_limit and sodium > sodium_limit:
            insights.append(
                {
                    "type": "sodium",
                    "severity": "caution",
                    "message": "This food may be high in sodium for your current plan.",
                    "value": sodium,
                    "target": sodium_limit,
                }
            )

        potassium = final_nutrients.potassium
        potassium_limit = targets.get("potassium")
        flags.append(
            {
                "type": "potassium_reliability",
                "severity": "caution",
                "message": food_details.potassium_reliability_note,
            }
        )
        if potassium is not None and potassium_limit and potassium > potassium_limit:
            insights.append(
                {
                    "type": "potassium",
                    "severity": "caution",
                    "message": "Potassium estimate may need checking for this profile.",
                    "value": potassium,
                    "target": potassium_limit,
                }
            )

        if "high" in food_details.phosphorus_tag:
            insights.append(
                {
                    "type": "phosphorus",
                    "severity": "review",
                    "message": (
                        "This food may be higher in phosphorus. Consider caregiver "
                        "or dietitian review if this is a frequent choice."
                    ),
                    "tag": food_details.phosphorus_tag,
                    "confidence": food_details.phosphorus_confidence,
                }
            )
        elif "unavailable" in food_details.phosphorus_tag:
            flags.append(
                {
                    "type": "phosphorus_unavailable",
                    "severity": "caution",
                    "message": food_details.phosphorus_note,
                }
            )

        if serving.is_derived_display_only:
            flags.append(
                {
                    "type": "derived_serving_selected",
                    "severity": "info",
                    "message": (
                        "Selected serving is provider-derived display data; "
                        "NutriKidney can store it locally but cannot use it for "
                        "provider-side food entry creation."
                    ),
                }
            )

        if not insights:
            insights.append(
                {
                    "type": "meal_context",
                    "severity": "info",
                    "message": "Meal nutrients were calculated and are ready for review.",
                }
            )

        return {"safety_flags": flags, "insights": insights}

    def _tag_phosphorus(self, details: Dict[str, Any]) -> Dict[str, Any]:
        """Call the CSV-backed phosphorus guide service."""
        food_name = str(details.get("food_name") or "")
        phosphorus_result = get_phosphorus_guide().analyze(food_name)
        phosphorus = phosphorus_result.get("phosphorus", {})
        level = phosphorus.get("level", "unknown")

        if level == "unknown":
            tag = "phosphorus data unavailable, use caution"
        else:
            tag = f"{level} phosphorus"

        match_type = phosphorus_result.get("match_type", "none")
        confidence = "reference_table_exact" if match_type == "exact" else match_type
        note = phosphorus.get("message", "No phosphorus guide match found")
        notes = phosphorus.get("notes") or []
        if notes:
            note = f"{note}. {' '.join(notes)}"

        return {
            "tag": tag,
            "confidence": confidence,
            "note": note,
            "phosphorus": phosphorus_result,
        }

    def _get_child_context(self, child_profile_id: str) -> ChildProfileContext:
        """Fetch child profile context. Placeholder until connected to app DB."""
        return ChildProfileContext(
            child_profile_id=child_profile_id,
            ckd_stage="unknown",
            dialysis_status="unknown",
            diet_pattern="unknown",
            targets=dict(self.config.DEFAULT_CKD_TARGETS),
        )

    def _find_serving(self, servings: List[MealServing], serving_id: str) -> MealServing:
        for serving in servings:
            if serving.serving_id == str(serving_id):
                return serving
        raise ValidationError("Selected serving is no longer valid. Reload the serving list.")

    def _best_fatsecret_match(self, query: Any) -> Dict[str, Any]:
        raw_labels = query if isinstance(query, list) else [query]
        cleaned_labels = self.food_matcher.clean_detected_labels(
            [str(value) for value in raw_labels if value is not None]
        )
        if not cleaned_labels:
            cleaned_labels = self._expand_image_match_queries(raw_labels)

        logger.info("Image fallback labels cleaned from %s to %s", raw_labels, cleaned_labels)

        best = None
        best_score = -1.0
        best_ranked = []
        last_timeout = None

        for label in cleaned_labels[:4]:
            search_variations = self.food_matcher.generate_search_queries(label)
            if not search_variations:
                continue

            logger.info("Image fallback search variations for '%s': %s", label, search_variations)

            candidates = []
            seen = set()
            for search_query in search_variations:
                try:
                    raw_results = self.fatsecret_client.search_foods(search_query, 0)
                except ServiceTimeoutError as e:
                    logger.warning(
                        "FatSecret image fallback search timed out for '%s'; trying next query",
                        search_query,
                    )
                    last_timeout = e
                    continue
                except Exception as e:
                    logger.warning(
                        "FatSecret image fallback search failed for '%s': %s",
                        search_query,
                        str(e),
                    )
                    continue

                foods = (raw_results or {}).get("foods", [])[:10]
                for candidate in self.food_matcher.build_candidates(foods, matched_query=search_query):
                    if candidate.food_id in seen:
                        continue
                    seen.add(candidate.food_id)
                    candidates.append(candidate)

            ranked = self.food_matcher.rank(
                label,
                candidates,
                get_details=None,  # details fetched after selection
            )
            if not ranked:
                continue

            top = ranked[0]
            if top.score > best_score:
                best_score = top.score
                best_ranked = ranked[:3]
                best = {
                    "food_id": top.candidate.food_id,
                    "food_name": top.candidate.food_name,
                    "score": round(top.score, 2),
                    "matched_query": top.candidate.matched_query or label,
                    "raw_match": top.candidate.raw or {},
                    "confidence": self.food_matcher.confidence_bucket(top.score),
                    "top_matches": [
                        {
                            "food_id": item.candidate.food_id,
                            "food_name": item.candidate.food_name,
                            "score": round(item.score, 2),
                            "matched_query": item.candidate.matched_query,
                            "food_type": item.candidate.food_type,
                            "brand_name": item.candidate.brand_name,
                        }
                        for item in best_ranked
                    ],
                }

            if best and best_score >= 85:
                break

        if best:
            logger.info(
                "Image fallback matched '%s' to FatSecret food '%s' with score %.2f",
                best.get("matched_query"),
                best.get("food_name"),
                best.get("score"),
            )
            return best

        if last_timeout:
            raise FatSecretAPIError(
                "FatSecret food matching timed out after image recognition. Please try again or enter the food manually.",
                details={"reason": "fatsecret_search_timeout"},
            )

        raise NoResultsError("No matching FatSecret food was found for this image.")

    def _best_fatsecret_matches(self, queries: List[str], limit: int = 5) -> List[Dict[str, Any]]:
        """Return the best unique FatSecret match for each query."""
        matches = []
        seen_food_ids = set()
        for query in queries:
            try:
                match = self._best_fatsecret_match(query)
            except Exception as e:
                logger.warning(
                    "Additional ingredient search failed for '%s': %s",
                    query,
                    str(e),
                )
                continue

            food_id = str(match.get("food_id") or "")
            if not food_id or food_id in seen_food_ids:
                continue
            seen_food_ids.add(food_id)
            matches.append(match)
            if len(matches) >= limit:
                break
        return matches

    @staticmethod
    def _fuzzy_score(query: str, candidate: str) -> float:
        try:
            from rapidfuzz import fuzz  # type: ignore

            return float(fuzz.token_set_ratio(query, candidate))
        except Exception:
            pass
        return SequenceMatcher(None, query.lower(), candidate.lower()).ratio() * 100

    def _image_match_score(self, query: str, candidate: str) -> float:
        """Score image labels against FatSecret results with key-word penalties."""
        base_score = self._fuzzy_score(query, candidate)
        query_tokens = self._food_tokens(query)
        candidate_tokens = self._food_tokens(candidate)
        if not query_tokens:
            return base_score

        missing_tokens = query_tokens - candidate_tokens
        extra_tokens = candidate_tokens - query_tokens
        score = base_score

        # Cooking/preparation words matter clinically and visually. If Google
        # says "fried chicken", "chicken breast" should not outrank fried items.
        score -= 28 * len(missing_tokens & self.PREPARATION_TOKENS)

        # Penalize missing core words, but less aggressively than prep words.
        score -= 8 * len(missing_tokens - self.PREPARATION_TOKENS)

        # Penalize extra specificity when the image label did not ask for it.
        # This helps keep "fried chicken" from matching "chicken skins".
        score -= 6 * len(extra_tokens - self.PREPARATION_TOKENS)
        score -= 18 * len(extra_tokens & self.UNREQUESTED_SPECIFICITY_TOKENS)

        if query_tokens.issubset(candidate_tokens):
            score += 18

        candidate_name = candidate.lower()
        if "breast" in candidate_name and "breast" not in query_tokens:
            score -= 18
        if ("skin" in candidate_name or "skins" in candidate_name) and "skin" not in query_tokens and "skins" not in query_tokens:
            score -= 28
        if "baby food" in candidate_name and "baby" not in query_tokens:
            score -= 35

        return max(0.0, min(100.0, score))

    def _expand_image_match_queries(self, queries: List[Any]) -> List[str]:
        """Add provider-friendly variants while removing generic fallback labels."""
        normalized_queries = []
        seen = set()

        for raw_query in queries:
            query = " ".join(str(raw_query or "").strip().split())
            normalized = query.lower()
            if not query or normalized in seen:
                continue

            normalized_queries.append(query)
            seen.add(normalized)

            adjective_stripped = self._remove_adjectives_only(query)
            adjective_stripped_normalized = adjective_stripped.lower()
            if adjective_stripped and adjective_stripped_normalized != normalized:
                logger.info(
                    "Adjective cleanup for image label '%s' -> '%s'",
                    query,
                    adjective_stripped,
                )
            if (
                adjective_stripped
                and adjective_stripped_normalized not in seen
                and adjective_stripped_normalized != normalized
            ):
                normalized_queries.append(adjective_stripped)
                seen.add(adjective_stripped_normalized)

            tokens = self._food_tokens(query)
            if {"fried", "chicken"}.issubset(tokens):
                for variant in [
                    "fried or coated chicken",
                    "breaded chicken",
                    "coated chicken",
                ]:
                    if variant not in seen:
                        normalized_queries.append(variant)
                        seen.add(variant)

        specific_token_sets = [
            self._food_tokens(query)
            for query in normalized_queries
            if self._food_tokens(query) & self.PREPARATION_TOKENS
        ]

        if not specific_token_sets:
            return normalized_queries

        filtered = []
        for query in normalized_queries:
            tokens = self._food_tokens(query)
            is_generic_subset = any(tokens < specific_tokens for specific_tokens in specific_token_sets)
            if is_generic_subset:
                continue
            filtered.append(query)

        return filtered

    def _remove_adjectives_only(self, query: str) -> str:
        """
        Remove adjectives while preserving preparation words when possible.

        Example:
        - "crispy fried chicken" -> "fried chicken"
        """
        text = " ".join(str(query or "").strip().split())
        if not text:
            return ""

        nlp = self._get_spacy_nlp()
        if nlp is None:
            tokens = [
                token
                for token in text.split()
                if token.lower() not in self.REMOVABLE_ADJECTIVES
            ]
            return " ".join(tokens)

        try:
            doc = nlp(text)
        except Exception:
            return text

        kept_tokens = []
        for token in doc:
            lower = token.text.lower()
            if lower in self.PREPARATION_TOKENS:
                kept_tokens.append(token.text)
                continue
            if token.pos_ == "ADJ":
                continue
            kept_tokens.append(token.text)

        collapsed = " ".join(part for part in kept_tokens if part.strip()).strip()
        return collapsed or text

    @staticmethod
    def _get_spacy_nlp():
        """Lazily load spaCy so adjective cleanup remains optional."""
        global _SPACY_NLP, _SPACY_LOAD_ATTEMPTED

        if _SPACY_LOAD_ATTEMPTED:
            return _SPACY_NLP

        _SPACY_LOAD_ATTEMPTED = True
        try:
            import spacy  # type: ignore
        except Exception:
            logger.info("spaCy not installed; using simple adjective fallback list")
            return None

        try:
            _SPACY_NLP = spacy.load("en_core_web_sm")
            logger.info("Loaded spaCy model for adjective cleanup")
            return _SPACY_NLP
        except Exception:
            logger.warning(
                "spaCy model not available; adjective cleanup will use a simple fallback list"
            )
            return None

    @staticmethod
    def _food_tokens(value: str) -> set[str]:
        stop_words = {
            "food",
            "ingredient",
            "dish",
            "cuisine",
            "meat",
            "with",
            "and",
            "the",
            "generic",
        }
        return {
            token
            for token in re.findall(r"[a-z]+", value.lower())
            if len(token) > 2 and token not in stop_words
        }

    def _search_item_to_choice(self, item: Dict[str, Any]) -> MealLoggingFoodChoice:
        return MealLoggingFoodChoice(
            food_id=str(item.get("food_id")),
            food_name=item.get("food_name"),
            brand_name=item.get("brand_name"),
            food_type=item.get("food_type"),
            food_url=item.get("food_url"),
            preview_description=item.get("food_description"),
        )

    def _normalize_query(self, query: str) -> str:
        normalized = " ".join((query or "").strip().split())
        if not normalized:
            raise ValidationError("Food search query cannot be empty.")
        return normalized

    def _serving_display_text(
        self,
        serving_description: Optional[str],
        number_of_units: Optional[float],
        measurement_description: Optional[str],
        metric_amount: Optional[float],
        metric_unit: Optional[str],
    ) -> str:
        if serving_description:
            return serving_description

        parts = []
        if number_of_units is not None and measurement_description:
            parts.append(f"{number_of_units:g} {measurement_description}")
        if metric_amount is not None and metric_unit:
            parts.append(f"{metric_amount:g} {metric_unit}")
        return " / ".join(parts) if parts else "Serving"

    def _to_float(self, value: Any) -> Optional[float]:
        if value is None or value == "":
            return None
        if isinstance(value, (int, float)):
            return float(value)
        try:
            return float(str(value).split()[0])
        except (TypeError, ValueError, IndexError):
            return None

    def _read_json_list(self, path: str) -> List[Dict[str, Any]]:
        if not os.path.exists(path):
            return []
        with open(path, "r", encoding="utf-8") as handle:
            data = json.load(handle)
        return data if isinstance(data, list) else []

    def _write_json_list(self, path: str, records: List[Dict[str, Any]]) -> None:
        os.makedirs(os.path.dirname(path), exist_ok=True)
        with open(path, "w", encoding="utf-8") as handle:
            json.dump(records, handle, indent=2)

    def _recompute_daily_summary(self, child_profile_id: str, log_date: str) -> None:
        records = self._read_json_list(self.config.MEAL_LOG_STORAGE_PATH)
        totals = {nutrient: 0.0 for nutrient in self.CORE_NUTRIENTS}

        for record in records:
            if record.get("deleted_at"):
                continue
            if record.get("child_profile_id") != child_profile_id:
                continue
            if not str(record.get("logged_at", "")).startswith(log_date):
                continue

            nutrients = record.get("final_nutrients", {})
            for nutrient in totals:
                value = nutrients.get(nutrient)
                if value is not None:
                    totals[nutrient] += float(value)

        summaries = self._read_json_list(self.config.DAILY_SUMMARY_STORAGE_PATH)
        summaries = [
            summary
            for summary in summaries
            if not (
                summary.get("child_profile_id") == child_profile_id
                and summary.get("date") == log_date
            )
        ]
        summaries.append(
            {
                "child_profile_id": child_profile_id,
                "date": log_date,
                "totals": {key: round(value, 4) for key, value in totals.items()},
                "updated_at": datetime.now(timezone.utc).isoformat(),
            }
        )
        self._write_json_list(self.config.DAILY_SUMMARY_STORAGE_PATH, summaries)


_meal_logging_service: Optional[MealLoggingService] = None


def get_meal_logging_service() -> MealLoggingService:
    """Get or create singleton meal logging service."""
    global _meal_logging_service
    if _meal_logging_service is None:
        _meal_logging_service = MealLoggingService()
    return _meal_logging_service
