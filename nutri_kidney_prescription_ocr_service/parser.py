import re


DOSAGE_RE = re.compile(
    r"\b\d+(?:\.\d+)?\s*(?:mg|mcg|g|ml|mL|meg|tablet(?:s)?|tab(?:s)?|capsule(?:s)?|cap(?:s)?|drop(?:s)?|puff(?:s)?|teaspoon(?:s)?)\b(?:\s*/\s*\d+(?:\.\d+)?\s*(?:ml|mL))?",
    re.IGNORECASE,
)

FREQUENCY_RE = re.compile(
    r"(once daily|twice daily|three times daily|four times daily|every\s+\d+\s*(?:hour|hours)|\d+\s*x\s*(?:daily|day)|before meals|after meals|at bedtime|as needed|prn|bid|tid|qid)",
    re.IGNORECASE,
)

FORM_RE = re.compile(
    r"\b(capsule|cap|tablet|tab|syrup|suspension|solution|cream|ointment|drop|drops|inhaler|patch)\b",
    re.IGNORECASE,
)

DURATION_RE = re.compile(
    r"\b(\d+\s*(?:day|days|week|weeks|month|months)|x\s*\d+\s*(?:day|days|week|weeks))\b",
    re.IGNORECASE,
)

INSTRUCTION_RE = re.compile(
    r"(after meal(?:s)?|before meal(?:s)?|with food|without food|take with water|prn|as needed|at bedtime)",
    re.IGNORECASE,
)

STOPWORDS = {
    "take",
    "give",
    "apply",
    "dispense",
    "label",
    "bottle",
    "needed",
    "every",
    "hours",
    "hour",
    "needed",
    "tablet",
    "capsule",
    "tab",
    "cap",
    "syrup",
    "sig",
}

NOISE_PREFIXES = (
    "dispense",
    "label",
    "directions",
    "instruction",
    "instructions",
    "qty",
    "quantity",
)

COMMON_MEDICATION_HINTS = [
    "amoxicillin",
    "paracetamol",
    "acetaminophen",
    "ibuprofen",
    "losartan",
    "amlodipine",
    "metformin",
    "omeprazole",
    "cetirizine",
    "salbutamol",
    "calcium carbonate",
    "ferrous sulfate",
]

def _fuzz() -> object:
    # Lazy import to keep service startup fast.
    from rapidfuzz import fuzz  # type: ignore

    return fuzz


def normalize_whitespace(text: str) -> str:
    return re.sub(r"[ \t]+", " ", text or "").strip()


def split_segments(text: str) -> list[str]:
    normalized = (text or "").replace("|", "\n")
    normalized = re.sub(r"[;]+", "\n", normalized)
    normalized = re.sub(r"(?<=[a-z0-9])\s{2,}(?=[A-Z])", "\n", normalized)
    segments = [normalize_whitespace(segment) for segment in normalized.splitlines()]
    return [segment for segment in segments if len(segment) >= 3]


def find_known_medication_name(text: str) -> str:
    lower = normalize_whitespace(text).lower()
    if not lower:
        return ""
    best_name = ""
    best_score = 0
    fuzz = _fuzz()
    for candidate in COMMON_MEDICATION_HINTS:
        if candidate in lower:
            return candidate
        score = fuzz.partial_ratio(lower, candidate)
        if score > best_score:
            best_name = candidate
            best_score = score
    return best_name if best_score >= 88 else ""


def extract_candidate_name(prefix: str) -> str:
    cleaned = re.sub(r"^[\W\d_]+", "", normalize_whitespace(prefix)).strip(" -:")
    cleaned = re.sub(r"^\(([^)]+)\)$", r"\1", cleaned)
    lowered = cleaned.lower()
    for noise in NOISE_PREFIXES:
        if lowered.startswith(f"{noise}:") or lowered == noise:
            return ""

    hint_match = find_known_medication_name(cleaned)
    if hint_match:
        return hint_match

    parts = [part for part in cleaned.split() if part.lower() not in STOPWORDS]
    return " ".join(parts[:3]).strip()


def fuzzy_normalize_candidate(name: str) -> str:
    normalized = normalize_whitespace(name).lower()
    if not normalized:
        return ""

    best_name = normalized
    best_score = 0
    fuzz = _fuzz()
    for candidate in COMMON_MEDICATION_HINTS:
        score = fuzz.ratio(normalized, candidate)
        if score > best_score:
            best_name = candidate
            best_score = score

    return best_name if best_score >= 82 else name


def _append_candidate(
    medications: list[dict],
    seen: set,
    *,
    name: str,
    dosage: str,
    form: str,
    frequency: str,
    duration: str,
    instructions: str,
    raw_line: str,
) -> None:
    normalized_name = fuzzy_normalize_candidate(name)
    if not normalized_name or len(normalized_name.strip()) < 2:
        return

    normalized_instructions = normalize_whitespace(instructions)
    key = (
        normalized_name.lower(),
        dosage.lower(),
        frequency.lower(),
        form.lower(),
        duration.lower(),
        normalized_instructions.lower(),
    )
    if key in seen:
        return
    seen.add(key)
    medications.append(
        {
            "medicineName": normalized_name,
            "dosage": dosage,
            "form": form,
            "frequency": frequency,
            "duration": duration,
            "instructions": normalized_instructions,
            "rawLine": raw_line,
        }
    )


def _extract_context_fields(text: str, fallback_form: str = "") -> dict[str, str]:
    dosage_match = DOSAGE_RE.search(text)
    frequency_match = FREQUENCY_RE.search(text)
    form_match = FORM_RE.search(text)
    duration_match = DURATION_RE.search(text)
    instruction_match = INSTRUCTION_RE.search(text)
    dosage = dosage_match.group(0).strip() if dosage_match else ""
    frequency = frequency_match.group(0).strip() if frequency_match else ""
    form = form_match.group(0).strip() if form_match else fallback_form
    duration = duration_match.group(0).strip() if duration_match else ""
    instructions = (
        instruction_match.group(0).strip()
        if instruction_match
        else normalize_whitespace(text[dosage_match.end() :] if dosage_match else text)
    )
    return {
        "dosage": dosage,
        "frequency": frequency,
        "form": form,
        "duration": duration,
        "instructions": instructions,
    }


def _parse_known_medication_matches(text: str, medications: list[dict], seen: set) -> None:
    if not text:
        return

    full_text = normalize_whitespace(text)
    if not full_text:
        return

    lower_text = full_text.lower()
    for candidate in COMMON_MEDICATION_HINTS:
        start = 0
        while True:
            index = lower_text.find(candidate, start)
            if index == -1:
                break
            window_start = max(0, index - 40)
            window_end = min(len(full_text), index + len(candidate) + 140)
            context = full_text[window_start:window_end]
            fields = _extract_context_fields(context)
            _append_candidate(
                medications,
                seen,
                name=candidate,
                dosage=fields["dosage"],
                form=fields["form"],
                frequency=fields["frequency"],
                duration=fields["duration"],
                instructions=fields["instructions"],
                raw_line=context,
            )
            start = index + len(candidate)


def parse_prescription_text(text: str) -> list[dict]:
    medications: list[dict] = []
    seen = set()
    active_name = ""
    active_form = ""

    segments = split_segments(text)
    _parse_known_medication_matches(text, medications, seen)

    for line in segments:
        lower = line.lower()
        if any(
            token in lower
            for token in [
                "rx",
                "sig:",
                "doctor",
                "dr.",
                "patient",
                "address",
                "date",
                "clinic",
                "license",
            ]
        ):
            continue

        explicit_name = extract_candidate_name(re.split(r"[:(]", line, maxsplit=1)[0])
        if explicit_name:
            active_name = fuzzy_normalize_candidate(explicit_name)

        form_match = FORM_RE.search(line)
        if form_match:
            active_form = form_match.group(0).strip()

        dosage_match = DOSAGE_RE.search(line)
        if not dosage_match:
            hinted_name = find_known_medication_name(line)
            if hinted_name:
                active_name = fuzzy_normalize_candidate(hinted_name)
            continue

        dosage = dosage_match.group(0).strip()
        frequency_match = FREQUENCY_RE.search(line)
        frequency = frequency_match.group(0).strip() if frequency_match else ""
        duration_match = DURATION_RE.search(line)
        instruction_match = INSTRUCTION_RE.search(line)
        name = extract_candidate_name(line[: dosage_match.start()])
        if not name:
            name = find_known_medication_name(line)
        if not name and active_name:
            name = active_name
        instructions = normalize_whitespace(line[dosage_match.end() :])

        if not name:
            continue

        if len(name) < 2:
            continue

        normalized_instructions = instruction_match.group(0).strip() if instruction_match else instructions
        form = form_match.group(0).strip() if form_match else active_form
        duration = duration_match.group(0).strip() if duration_match else ""
        _append_candidate(
            medications,
            seen,
            name=name,
            dosage=dosage,
            form=form,
            frequency=frequency,
            duration=duration,
            instructions=normalized_instructions,
            raw_line=line,
        )

    return medications
