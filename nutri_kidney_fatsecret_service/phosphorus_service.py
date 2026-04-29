"""
Phosphorus guide matching for NutriKidney meal logging.

This module owns the CSV-backed phosphorus algorithm:
normalize -> exact match -> RapidFuzz/fallback fuzzy match -> classify -> flags.
"""
import csv
import os
import re
from difflib import SequenceMatcher
from typing import Any, Dict, List, Optional

try:
    from rapidfuzz import fuzz, process
except ImportError:  # pragma: no cover - fallback for local installs.
    fuzz = None
    process = None


class PhosphorusGuide:
    """Lookup phosphorus interpretation from the curated CSV reference."""

    DEFAULT_THRESHOLD = 80

    def __init__(
        self,
        csv_path: Optional[str] = None,
        threshold: int = DEFAULT_THRESHOLD,
    ):
        self.csv_path = csv_path or os.path.join(
            os.path.dirname(__file__),
            "phosphorus_guide_full_reference.csv",
        )
        self.threshold = threshold
        self._rows: Optional[List[Dict[str, Any]]] = None
        self._index: Optional[Dict[str, Dict[str, Any]]] = None

    def analyze(self, food_name: str) -> Dict[str, Any]:
        normalized_name = self.normalize(food_name)
        if not normalized_name:
            return self._unknown(food_name)

        rows = self._load_rows()
        exact = self._load_index().get(normalized_name)
        if exact:
            return self._format_match(food_name, exact, "exact", 100)

        matched_row = None
        score = 0

        if process is not None and fuzz is not None:
            choices = {
                row["normalized_food_name"]: row
                for row in rows
                if row.get("normalized_food_name")
            }
            match = process.extractOne(
                normalized_name,
                choices.keys(),
                scorer=fuzz.token_set_ratio,
            )
            if match:
                matched_key, score, _ = match
                matched_row = choices.get(matched_key)
        else:
            for row in rows:
                candidate = row.get("normalized_food_name", "")
                candidate_score = SequenceMatcher(
                    None,
                    normalized_name,
                    candidate,
                ).ratio() * 100
                if candidate_score > score:
                    score = candidate_score
                    matched_row = row

        if matched_row and score >= self.threshold:
            return self._format_match(food_name, matched_row, "fuzzy", score)

        return self._unknown(food_name)

    @staticmethod
    def normalize(value: str) -> str:
        normalized = re.sub(r"[^a-z0-9\s]", " ", str(value or "").lower())
        return " ".join(normalized.split())

    def _load_rows(self) -> List[Dict[str, Any]]:
        if self._rows is not None:
            return self._rows

        rows = []
        if not os.path.exists(self.csv_path):
            self._rows = rows
            return rows

        with open(self.csv_path, "r", encoding="utf-8-sig", newline="") as handle:
            for raw in csv.DictReader(handle):
                food_name = (raw.get("food_name") or "").strip()
                if not food_name:
                    continue
                rows.append(
                    {
                        "food_name": food_name,
                        "normalized_food_name": self.normalize(food_name),
                        "serving_size": (raw.get("serving_size") or "").strip(),
                        "phosphorus_mg": self._to_float(raw.get("phosphorus_mg")),
                        "potassium_flag": self._to_bool(raw.get("potassium_flag")),
                        "processed_caution": self._to_bool(
                            raw.get("processed_caution")
                        ),
                    }
                )

        self._rows = rows
        self._index = {
            row["normalized_food_name"]: row
            for row in rows
            if row.get("normalized_food_name")
        }
        return rows

    def _load_index(self) -> Dict[str, Dict[str, Any]]:
        if self._index is None:
            self._load_rows()
        return self._index or {}

    def _format_match(
        self,
        food_name: str,
        row: Dict[str, Any],
        match_type: str,
        score: float,
    ) -> Dict[str, Any]:
        phosphorus_mg = row.get("phosphorus_mg")
        level = self._classify(phosphorus_mg)
        message = {
            "low": "Lower phosphorus choice",
            "medium": "Moderate phosphorus, watch portions",
            "high": "High phosphorus",
        }.get(level, "No phosphorus guide match found")

        notes = []
        if row.get("potassium_flag") is True:
            notes.append("High potassium (>=250 mg in guide)")
        if row.get("processed_caution") is True:
            notes.append("Processed food - phosphorus may vary")

        return {
            "food_name": food_name,
            "matched_name": row.get("food_name"),
            "match_type": match_type,
            "match_score": round(float(score), 2),
            "phosphorus": {
                "value_mg": phosphorus_mg,
                "serving_size": row.get("serving_size"),
                "level": level,
                "potassium_flag": row.get("potassium_flag") is True,
                "processed_caution": row.get("processed_caution") is True,
                "message": message,
                "notes": notes,
            },
        }

    @staticmethod
    def _classify(phosphorus_mg: Optional[float]) -> str:
        if phosphorus_mg is None:
            return "unknown"
        if phosphorus_mg <= 100:
            return "low"
        if phosphorus_mg <= 199:
            return "medium"
        return "high"

    @staticmethod
    def _unknown(food_name: str) -> Dict[str, Any]:
        return {
            "food_name": food_name,
            "matched_name": None,
            "match_type": "none",
            "match_score": 0,
            "phosphorus": {
                "value_mg": None,
                "serving_size": None,
                "level": "unknown",
                "potassium_flag": False,
                "processed_caution": False,
                "message": "No phosphorus guide match found",
                "notes": [],
            },
        }

    @staticmethod
    def _to_float(value: Any) -> Optional[float]:
        try:
            return float(value)
        except (TypeError, ValueError):
            return None

    @staticmethod
    def _to_bool(value: Any) -> bool:
        return str(value).strip().lower() in {"true", "1", "yes", "y"}


_phosphorus_guide: Optional[PhosphorusGuide] = None


def get_phosphorus_guide() -> PhosphorusGuide:
    global _phosphorus_guide
    if _phosphorus_guide is None:
        _phosphorus_guide = PhosphorusGuide()
    return _phosphorus_guide
