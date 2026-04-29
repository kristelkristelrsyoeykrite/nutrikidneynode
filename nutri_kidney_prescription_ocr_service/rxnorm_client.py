import requests
import logging

logger = logging.getLogger(__name__)

RXNORM_BASE_URL = "https://rxnav.nlm.nih.gov/REST"


class RxNormClient:
    def __init__(self, base_url: str = RXNORM_BASE_URL, timeout: int = 15):
        self.base_url = base_url.rstrip("/")
        self.timeout = timeout

    def find_rxcui(self, drug_name: str) -> dict:
        logger.info("RxNorm lookup started for drug name: %s", drug_name)
        response = requests.get(
            f"{self.base_url}/rxcui.json",
            params={"name": drug_name, "search": 2},
            timeout=self.timeout,
        )
        response.raise_for_status()
        payload = response.json() or {}
        id_group = payload.get("idGroup") or {}
        rxcui_list = id_group.get("rxnormId") or []
        logger.info(
            "RxNorm lookup finished for %s. rxcui=%s",
            drug_name,
            rxcui_list[0] if rxcui_list else None,
        )
        return {
            "name": drug_name,
            "rxcui": rxcui_list[0] if rxcui_list else None,
            "raw": payload,
        }

    def get_properties(self, rxcui: str) -> dict:
        logger.info("RxNorm properties lookup started for rxcui=%s", rxcui)
        response = requests.get(
            f"{self.base_url}/rxcui/{rxcui}/properties.json",
            timeout=self.timeout,
        )
        response.raise_for_status()
        payload = response.json() or {}
        properties = payload.get("properties") or {}
        logger.info(
            "RxNorm properties lookup finished for rxcui=%s name=%s",
            rxcui,
            properties.get("name"),
        )
        return {
            "rxcui": rxcui,
            "name": properties.get("name"),
            "synonym": properties.get("synonym"),
            "tty": properties.get("tty"),
            "language": properties.get("language"),
            "raw": payload,
        }
