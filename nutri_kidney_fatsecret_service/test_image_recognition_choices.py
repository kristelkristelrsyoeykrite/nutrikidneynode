import os
import sys
import unittest
import base64
import requests
from types import ModuleType
from types import SimpleNamespace
from unittest.mock import patch


sys.path.insert(0, os.path.dirname(__file__))

# The tests use fake API clients, so the optional OAuth transport is not needed.
if "requests_oauthlib" not in sys.modules:
    requests_oauthlib = ModuleType("requests_oauthlib")
    requests_oauthlib.OAuth1Session = object
    sys.modules["requests_oauthlib"] = requests_oauthlib

from image_recognition import ImageRecognitionHandler  # noqa: E402
from meal_logging import MealLoggingService  # noqa: E402


class _FakeFeature:
    class Type:
        LABEL_DETECTION = "label"
        OBJECT_LOCALIZATION = "object"
        WEB_DETECTION = "web"
        TEXT_DETECTION = "text"

    def __init__(self, type_, max_results):
        self.type_ = type_
        self.max_results = max_results


class _FakeVisionModule:
    Feature = _FakeFeature

    @staticmethod
    def Image(content):
        return SimpleNamespace(content=content)


class _FakeVisionClient:
    def annotate_image(self, request):
        return SimpleNamespace(
            error=SimpleNamespace(message=""),
            label_annotations=[
                SimpleNamespace(description="Fried chicken", score=0.91),
                SimpleNamespace(description="Food", score=0.99),
            ],
            localized_object_annotations=[
                SimpleNamespace(name="Chicken", score=0.82),
                SimpleNamespace(name="Plate", score=0.79),
            ],
            web_detection=SimpleNamespace(
                web_entities=[
                    SimpleNamespace(description="Chicken adobo", score=0.77),
                    SimpleNamespace(description="Fried chicken", score=0.70),
                ]
            ),
            text_annotations=[
                SimpleNamespace(description="JOLLIBEE\nChickenjoy\nOfficial Receipt")
            ],
        )


class _FakeFatSecretClient:
    def search_foods(self, query, page):
        return {
            "foods": [
                {
                    "food_id": "fs-1",
                    "food_name": "Fried Chicken",
                    "food_type": "Generic",
                    "food_description": "Per 1 serving",
                    "source": "fatsecret",
                },
                {
                    "food_id": "fs-2",
                    "food_name": "Fried Chicken with Rice",
                    "food_type": "Generic",
                    "food_description": "Per meal",
                    "source": "fatsecret",
                },
            ]
        }


class _FakeUSDAClient:
    def search_foods(self, query, page, page_size=10):
        return {
            "foods": [
                {
                    "food_id": "usda:123",
                    "food_name": "Chicken, broilers or fryers, fried",
                    "food_type": "Survey (FNDDS)",
                    "source": "usda",
                    "data_source": "usda",
                },
                {
                    "food_id": "usda:456",
                    "food_name": "Chicken and rice",
                    "food_type": "Survey (FNDDS)",
                    "source": "usda",
                    "data_source": "usda",
                },
            ]
        }


class _FakeResponse:
    def __init__(self, data, status_code=200):
        self._data = data
        self.status_code = status_code
        self.ok = 200 <= status_code < 400

    def raise_for_status(self):
        return None

    def json(self):
        return self._data


class ImageRecognitionChoiceTests(unittest.TestCase):
    @patch("image_recognition.requests.post")
    def test_fatsecret_uses_oauth2_v2_json_request(self, post):
        post.side_effect = [
            _FakeResponse({"access_token": "token-123", "expires_in": 3600}),
            _FakeResponse(
                {
                    "food_response": [
                        {
                            "food_id": 3092,
                            "food_name": "Egg",
                            "confidence": 0.94,
                        }
                    ]
                }
            ),
        ]
        handler = ImageRecognitionHandler(_FakeFatSecretClient())

        results = handler._send_to_fatsecret_recognition(
            b"jpeg bytes",
            "image/jpeg",
        )

        self.assertEqual(results[0]["food_id"], 3092)
        token_call, recognition_call = post.call_args_list
        self.assertEqual(
            token_call.args[0],
            "https://oauth.fatsecret.com/connect/token",
        )
        self.assertEqual(
            token_call.kwargs["data"]["scope"],
            "image-recognition",
        )
        self.assertEqual(
            token_call.kwargs["headers"]["Content-Type"],
            "application/x-www-form-urlencoded",
        )
        self.assertEqual(
            recognition_call.args[0],
            "https://platform.fatsecret.com/rest/image-recognition/v2",
        )
        self.assertEqual(
            recognition_call.kwargs["headers"]["Authorization"],
            "Bearer token-123",
        )
        self.assertEqual(recognition_call.kwargs["timeout"], 45)
        self.assertEqual(
            recognition_call.kwargs["json"]["image_b64"],
            base64.b64encode(b"jpeg bytes").decode("ascii"),
        )
        self.assertTrue(
            recognition_call.kwargs["json"]["include_food_data"]
        )

    @patch("image_recognition.requests.post")
    def test_fatsecret_oauth_error_includes_provider_message(self, post):
        post.return_value = _FakeResponse(
            {
                "error": "invalid_scope",
                "error_description": "The requested scope is not enabled.",
            },
            status_code=400,
        )
        handler = ImageRecognitionHandler(_FakeFatSecretClient())

        with self.assertRaisesRegex(
            Exception,
            "invalid_scope.*requested scope is not enabled",
        ):
            handler._get_fatsecret_image_access_token()

    @patch("image_recognition.requests.post")
    def test_fatsecret_http_200_api_error_is_raised(self, post):
        post.side_effect = [
            _FakeResponse({"access_token": "token-123", "expires_in": 3600}),
            _FakeResponse(
                {
                    "error": {
                        "code": 13,
                        "message": "Invalid request parameters.",
                    }
                }
            ),
        ]
        handler = ImageRecognitionHandler(_FakeFatSecretClient())

        with self.assertRaisesRegex(
            Exception,
            "API error 13: Invalid request parameters",
        ):
            handler._send_to_fatsecret_recognition(
                b"jpeg bytes",
                "image/jpeg",
            )

    @patch("image_recognition.requests.post")
    def test_fatsecret_image_timeout_retries_once(self, post):
        post.side_effect = [
            _FakeResponse({"access_token": "token-123", "expires_in": 3600}),
            requests.exceptions.ReadTimeout("slow image recognition"),
            _FakeResponse(
                {
                    "food_response": [
                        {
                            "food_id": 3092,
                            "food_name": "Egg",
                            "confidence": 0.94,
                        }
                    ]
                }
            ),
        ]
        handler = ImageRecognitionHandler(_FakeFatSecretClient())

        results = handler._send_to_fatsecret_recognition(
            b"jpeg bytes",
            "image/jpeg",
        )

        self.assertEqual(results[0]["food_name"], "Egg")
        self.assertEqual(post.call_count, 3)

    def test_fatsecret_failure_keeps_google_vision_fallback(self):
        handler = ImageRecognitionHandler(_FakeFatSecretClient())
        handler._validate_image_file = lambda image_data, content_type: None
        handler._preprocess_image = lambda image: (image, None)
        handler._image_to_bytes = lambda image: b"processed"
        handler._send_to_fatsecret_recognition = lambda *args: (
            (_ for _ in ()).throw(RuntimeError("FatSecret unavailable"))
        )
        handler._detect_with_google_vision = lambda image: [
            {
                "food_name": "Chicken adobo",
                "confidence": 0.88,
                "source": "google_vision",
            }
        ]

        with patch("PIL.Image.open", return_value=object()):
            result = handler.detect_food_candidates(b"image", "image/jpeg")

        self.assertEqual(result["source"], "google_vision")
        self.assertEqual(result["candidates"][0]["food_name"], "Chicken adobo")
        self.assertTrue(
            any("Falling back" in warning for warning in result["warnings"])
        )

    def test_nested_fatsecret_response_extracts_food_candidates(self):
        response = {
            "food_response": {
                "food_entries": [
                    {
                        "food": {
                            "food_id": 3092,
                            "food_name": "Egg",
                        },
                        "confidence": 0.94,
                    },
                    {
                        "food": {
                            "food_id": 1234,
                            "food_entry_name": "Breakfast sausage",
                        },
                        "score": 0.81,
                    },
                ]
            }
        }

        extracted = ImageRecognitionHandler._extract_fatsecret_recognition_results(
            response
        )
        normalized = ImageRecognitionHandler(
            _FakeFatSecretClient()
        )._normalize_fatsecret_candidates(extracted)

        self.assertEqual(
            [candidate["food_name"] for candidate in normalized],
            ["Egg", "Breakfast sausage"],
        )
        self.assertTrue(
            all(
                candidate["source"] == "fatsecret_image_recognition"
                for candidate in normalized
            )
        )

    def test_fatsecret_alternative_label_fields_are_supported(self):
        response = {
            "predictions": [
                {
                    "food_label": "Crispy fried egg",
                    "probability": 0.91,
                }
            ]
        }

        extracted = ImageRecognitionHandler._extract_fatsecret_recognition_results(
            response
        )
        normalized = ImageRecognitionHandler(
            _FakeFatSecretClient()
        )._normalize_fatsecret_candidates(extracted)

        self.assertEqual(normalized[0]["food_name"], "Crispy fried egg")

    def test_fatsecret_schema_summary_excludes_sensitive_values(self):
        summary = ImageRecognitionHandler._fatsecret_response_schema(
            {
                "access_token": "secret-token",
                "results": [{"candidate": {"display_text": "Egg"}}],
            }
        )

        self.assertIn("$.results:array[1]", summary)
        self.assertNotIn("secret-token", summary)
        self.assertNotIn("Egg", summary)

    def test_successful_fatsecret_results_skip_google_fallback(self):
        handler = ImageRecognitionHandler(_FakeFatSecretClient())
        handler._validate_image_file = lambda image_data, content_type: None
        handler._preprocess_image = lambda image: (image, None)
        handler._image_to_bytes = lambda image: b"processed"
        handler._send_to_fatsecret_recognition = lambda *args: [
            {
                "food": {
                    "food_id": 3092,
                    "food_name": "Egg",
                },
                "confidence": 0.94,
            }
        ]
        google_called = []
        handler._detect_with_google_vision = lambda image: google_called.append(True)

        with patch("PIL.Image.open", return_value=object()):
            result = handler.detect_food_candidates(b"image", "image/jpeg")

        self.assertEqual(result["source"], "fatsecret")
        self.assertEqual(result["candidates"][0]["food_name"], "Egg")
        self.assertEqual(
            result["fatsecret_candidates"][0]["food_name"],
            "Egg",
        )
        self.assertEqual(google_called, [])

    def test_google_vision_fuses_multiple_signal_types(self):
        handler = ImageRecognitionHandler(_FakeFatSecretClient())
        handler._google_vision_client = lambda: (
            _FakeVisionModule,
            _FakeVisionClient(),
        )

        candidates = handler._detect_with_google_vision(b"image")
        names = {candidate["food_name"] for candidate in candidates}
        signals = {candidate["vision_signal"] for candidate in candidates}

        self.assertIn("Chicken adobo", names)
        self.assertIn("Fried chicken", names)
        self.assertIn("Chickenjoy", names)
        self.assertTrue({"web", "label", "object", "text"}.issubset(signals))
        self.assertEqual(len(names), len(candidates))

    def test_catalog_matching_returns_unique_fatsecret_and_usda_choices(self):
        service = MealLoggingService(fatsecret_client=_FakeFatSecretClient())
        service.usda_client = _FakeUSDAClient()

        matches = service._rank_image_catalog_matches(
            ["fried chicken", "chicken and rice"],
            limit=8,
        )

        self.assertGreaterEqual(len(matches), 3)
        self.assertEqual(
            len({match["food_id"] for match in matches}),
            len(matches),
        )
        self.assertIn("fatsecret", {match["source"] for match in matches})
        self.assertIn("usda", {match["source"] for match in matches})
        self.assertGreaterEqual(matches[0]["score"], matches[-1]["score"])

    def test_specific_dish_is_searched_before_cuisine_and_broad_labels(self):
        class RecordingFatSecretClient:
            def __init__(self):
                self.queries = []

            def search_foods(self, query, page):
                self.queries.append(query)
                if query.lower() == "sinigang":
                    return {
                        "foods": [
                            {
                                "food_id": "fs-sinigang",
                                "food_name": "Sinigang",
                                "food_type": "Generic",
                                "food_description": "Per 1 bowl",
                                "source": "fatsecret",
                            }
                        ]
                    }
                return {"foods": []}

        class EmptyUSDAClient:
            def search_foods(self, query, page, page_size=10):
                return {"foods": []}

        fatsecret = RecordingFatSecretClient()
        service = MealLoggingService(fatsecret_client=fatsecret)
        service.usda_client = EmptyUSDAClient()

        matches = service._rank_image_catalog_matches(
            [
                "malaysian filipino vegetable",
                "Malaysian cuisine",
                "Filipino cuisine",
                "Vegetable",
                "malaysian",
                "Sinigang",
                "filipino",
                "Produce",
            ],
            limit=8,
        )

        self.assertTrue(matches)
        self.assertEqual(matches[0]["food_name"], "Sinigang")
        self.assertEqual(fatsecret.queries[0].lower(), "sinigang")


if __name__ == "__main__":
    unittest.main()
