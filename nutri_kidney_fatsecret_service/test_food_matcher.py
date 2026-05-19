import pathlib
import sys
import unittest

SERVICE_DIR = pathlib.Path(__file__).resolve().parent
if str(SERVICE_DIR) not in sys.path:
    sys.path.insert(0, str(SERVICE_DIR))

from food_matcher import FoodMatcher, MatchCandidate  # noqa: E402


class FoodMatcherTests(unittest.TestCase):
    def test_clean_detected_labels_removes_generic(self):
        matcher = FoodMatcher(weak_labels={"food", "meal", "fast food"})
        cleaned = matcher.clean_detected_labels(["fried chicken", "food", "meal", "fried chicken"])
        self.assertEqual(cleaned, ["fried chicken"])

    def test_generate_search_queries_has_variations(self):
        matcher = FoodMatcher(prep_tokens={"fried"})
        queries = matcher.generate_search_queries("fried chicken")
        self.assertIn("fried chicken", queries)
        self.assertTrue(any("," in q for q in queries))

    def test_rank_prefers_exact_dish_over_sandwich(self):
        matcher = FoodMatcher(prep_tokens={"fried"})
        candidates = [
            MatchCandidate(
                food_id="1",
                food_name="Chicken, fried, battered",
                food_description="Per 1 serving - Calories: 250kcal",
                matched_query="fried chicken",
                food_type="Generic",
            ),
            MatchCandidate(
                food_id="2",
                food_name="Chicken sandwich with fries",
                food_description="Per 1 sandwich - Calories: 650kcal",
                matched_query="fried chicken",
                food_type="Generic",
            ),
        ]
        ranked = matcher.rank("fried chicken", candidates)
        self.assertTrue(ranked)
        self.assertEqual(ranked[0].candidate.food_id, "1")


if __name__ == "__main__":
    unittest.main()
