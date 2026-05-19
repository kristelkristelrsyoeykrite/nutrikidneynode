"""
FoodMatcher: choose the best FatSecret food_id from image-detected labels.

This module sits between:
 - Image label detection (FatSecret image recognition or Google Vision)
 - FatSecret foods.search + food.get

Goals:
 - Never trust the first search result blindly
 - Generate multiple search queries per detected label
 - Rank all candidate results with a confidence score
 - Support "confirm with user" behavior when confidence is not high enough
"""

from __future__ import annotations

import re
from dataclasses import dataclass
from difflib import SequenceMatcher
from typing import Any, Callable, Dict, Iterable, List, Optional, Sequence, Tuple


_WHITESPACE_RE = re.compile(r"\s+")
_NON_WORD_RE = re.compile(r"[^a-z0-9\s]+")


def _normalize_text(value: str) -> str:
    value = _WHITESPACE_RE.sub(" ", str(value or "").strip().lower())
    value = _NON_WORD_RE.sub(" ", value)
    return _WHITESPACE_RE.sub(" ", value).strip()


def _tokenize(value: str) -> List[str]:
    normalized = _normalize_text(value)
    if not normalized:
        return []
    return [token for token in normalized.split(" ") if token]


def _fuzzy_ratio(a: str, b: str) -> float:
    a = str(a or "")
    b = str(b or "")
    if not a or not b:
        return 0.0
    try:
        from rapidfuzz import fuzz  # type: ignore

        return float(fuzz.token_set_ratio(a, b))
    except Exception:
        pass
    return SequenceMatcher(None, a.lower(), b.lower()).ratio() * 100.0


@dataclass(frozen=True)
class MatchCandidate:
    food_id: str
    food_name: str
    brand_name: str = ""
    food_type: str = ""
    food_description: str = ""
    matched_query: str = ""
    raw: Optional[Dict[str, Any]] = None


@dataclass(frozen=True)
class ScoredMatch:
    candidate: MatchCandidate
    score: float
    reasons: Tuple[str, ...] = ()


class FoodMatcher:
    """
    Ranks FatSecret search results against image-detected labels.

    The matcher is designed to be used by the Python service layer; it is
    intentionally conservative and returns structured data for UI prompting.
    """

    DEFAULT_WEAK_LABELS = {
        "food",
        "meal",
        "dish",
        "plate",
        "ingredient",
        "meat",
        "vegetable",
        "cuisine",
        "fast food",
        "tableware",
        "dishware",
        "serveware",
    }

    DEFAULT_UNRELATED_TOKENS = {
        "sandwich",
        "burger",
        "fries",
        "rice",
        "noodles",
        "pizza",
        "taco",
        "burrito",
        "pasta",
        "salad",
        "soup",
        "wrap",
        "cake",
        "cookie",
        "ice",
        "cream",
        "soda",
        "cola",
        "chips",
    }

    DEFAULT_CKD_CORE_NUTRIENTS = ("sodium", "potassium", "phosphorus")

    def __init__(
        self,
        weak_labels: Optional[Iterable[str]] = None,
        prep_tokens: Optional[Iterable[str]] = None,
        unrelated_tokens: Optional[Iterable[str]] = None,
    ) -> None:
        self.weak_labels = {str(v).strip().lower() for v in (weak_labels or self.DEFAULT_WEAK_LABELS) if str(v).strip()}
        self.prep_tokens = {str(v).strip().lower() for v in (prep_tokens or ()) if str(v).strip()}
        self.unrelated_tokens = {
            str(v).strip().lower()
            for v in (unrelated_tokens or self.DEFAULT_UNRELATED_TOKENS)
            if str(v).strip()
        }

    def clean_detected_labels(self, labels: Sequence[str]) -> List[str]:
        """
        Remove weak/generic labels while keeping stronger multi-word labels first.
        """
        seen = set()
        cleaned: List[str] = []
        for raw in labels or []:
            label = " ".join(str(raw or "").strip().split())
            normalized = label.lower()
            if not label or normalized in seen:
                continue
            seen.add(normalized)
            if normalized in self.weak_labels:
                continue
            cleaned.append(label)

        # Prefer more specific labels (more words, longer), keep stable order otherwise.
        cleaned.sort(key=lambda value: (len(value.split()), len(value)), reverse=True)
        return cleaned

    def generate_search_queries(self, label: str, max_queries: int = 6) -> List[str]:
        """
        Generate provider-friendly variations for FatSecret foods.search.
        """
        base = " ".join(str(label or "").strip().split())
        if not base:
            return []

        tokens = _tokenize(base)
        if not tokens:
            return []

        queries: List[str] = []

        def _add(q: str) -> None:
            q = " ".join(str(q or "").strip().split())
            if len(q) < 2:
                return
            if q.lower() in {existing.lower() for existing in queries}:
                return
            queries.append(q)

        _add(base)

        # Swap order for two-token labels ("chicken fried")
        if len(tokens) == 2:
            _add(f"{tokens[1]} {tokens[0]}")

        # Comma-separated variant ("chicken, fried, battered")
        if len(tokens) >= 2:
            _add(", ".join(tokens))

        # Add common modifiers that help disambiguate generic vs branded results
        _add(f"homemade {base}")
        _add(f"{base} recipe")

        # If there's a preparation token, try the reverse "chicken fried"
        if self.prep_tokens and any(t in self.prep_tokens for t in tokens) and len(tokens) >= 2:
            _add(" ".join(reversed(tokens)))

        return queries[:max_queries]

    def build_candidates(
        self,
        search_results: Sequence[Dict[str, Any]],
        matched_query: str,
    ) -> List[MatchCandidate]:
        candidates: List[MatchCandidate] = []
        for item in search_results or []:
            food_id = str(item.get("food_id") or "").strip()
            if not food_id:
                continue
            candidates.append(
                MatchCandidate(
                    food_id=food_id,
                    food_name=str(item.get("food_name") or "").strip(),
                    brand_name=str(item.get("brand_name") or "").strip(),
                    food_type=str(item.get("food_type") or "").strip(),
                    food_description=str(item.get("food_description") or "").strip(),
                    matched_query=matched_query,
                    raw=item if isinstance(item, dict) else None,
                )
            )
        return candidates

    def rank(
        self,
        detected_label: str,
        candidates: Sequence[MatchCandidate],
        *,
        get_details: Optional[Callable[[str], Dict[str, Any]]] = None,
        ckd_core_nutrients: Sequence[str] = DEFAULT_CKD_CORE_NUTRIENTS,
    ) -> List[ScoredMatch]:
        """
        Score all candidates and return sorted best-first.

        If get_details is provided, we will optionally apply a small CKD completeness
        bonus using the top candidates' details (kept intentionally lightweight).
        """
        label = " ".join(str(detected_label or "").strip().split())
        label_tokens = set(_tokenize(label))
        required_prep = set()
        if self.prep_tokens and label_tokens:
            required_prep = label_tokens.intersection(self.prep_tokens)

        scored: List[ScoredMatch] = []
        for candidate in candidates or []:
            food_name = candidate.food_name or ""
            haystack = " ".join(
                part
                for part in [
                    candidate.food_name,
                    candidate.brand_name,
                    candidate.food_description,
                ]
                if part
            )

            name_similarity = _fuzzy_ratio(label, food_name)
            full_similarity = _fuzzy_ratio(label, haystack)
            name_similarity_score = max(name_similarity, full_similarity - 8.0)

            candidate_tokens = set(_tokenize(haystack))
            overlap = 0.0
            if label_tokens:
                overlap = (len(label_tokens.intersection(candidate_tokens)) / max(1, len(label_tokens))) * 100.0

            # Preparation tokens are clinically important; missing them is a strong negative.
            prep_ok = True
            if required_prep:
                prep_ok = bool(required_prep.intersection(candidate_tokens))

            brandish = (candidate.food_type or "").lower()
            is_brand = "brand" in brandish or bool(candidate.brand_name)
            is_generic = "generic" in brandish or not is_brand

            score = 0.0
            reasons: List[str] = []

            score += 0.62 * name_similarity_score
            score += 0.22 * overlap

            if is_generic:
                score += 6.0
                reasons.append("generic_bonus")
            if is_brand:
                score -= 10.0
                reasons.append("branded_penalty")

            if not prep_ok:
                score -= 22.0
                reasons.append("missing_prep_penalty")

            # Penalize unrelated words that often indicate a different dish.
            if self.unrelated_tokens and label_tokens:
                extra_unrelated = (candidate_tokens - label_tokens).intersection(self.unrelated_tokens)
                if extra_unrelated:
                    score -= min(18.0, 6.0 * len(extra_unrelated))
                    reasons.append("unrelated_word_penalty")

            # Serving hint bonus: descriptions often include "Per 1 serving" etc.
            if "per " in (candidate.food_description or "").lower() or "serving" in (candidate.food_description or "").lower():
                score += 3.0
                reasons.append("serving_hint_bonus")

            scored.append(
                ScoredMatch(
                    candidate=candidate,
                    score=max(0.0, min(100.0, float(score))),
                    reasons=tuple(reasons),
                )
            )

        scored.sort(key=lambda item: item.score, reverse=True)

        # Optional CKD completeness bonus using details for top 3 (lightweight).
        if get_details and scored:
            top = scored[:3]
            enriched: List[ScoredMatch] = []
            for item in top:
                bonus = 0.0
                try:
                    details = get_details(item.candidate.food_id)
                    nutrients_blob = str(details.get("food_description") or "").lower()
                    found = 0
                    for nutrient in ckd_core_nutrients:
                        if nutrient and nutrient.lower() in nutrients_blob:
                            found += 1
                    if found >= 2:
                        bonus = 4.0
                    elif found == 1:
                        bonus = 2.0
                except Exception:
                    bonus = 0.0

                enriched.append(
                    ScoredMatch(
                        candidate=item.candidate,
                        score=max(0.0, min(100.0, item.score + bonus)),
                        reasons=item.reasons + (("ckd_completeness_bonus",) if bonus else ()),
                    )
                )

            remainder = scored[3:]
            scored = sorted(enriched + remainder, key=lambda item: item.score, reverse=True)

        return scored

    @staticmethod
    def confidence_bucket(score: float) -> str:
        if score >= 85:
            return "high"
        if score >= 65:
            return "medium"
        return "low"
