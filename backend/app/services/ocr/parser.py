import re

from app.services.ocr.schemas import ContactFields


EMAIL_RE = re.compile(r"\b[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}\b", re.IGNORECASE)
PHONE_RE = re.compile(r"(?:\+?\d[\d\s().-]{7,}\d)")
URL_RE = re.compile(r"\b(?:https?://|www\.)\S+\b", re.IGNORECASE)

COMPANY_KEYWORD_WEIGHTS = {
    "pty": 4,
    "limited": 4,
    "ltd": 4,
    "llc": 4,
    "inc": 4,
    "corp": 4,
    "corporation": 4,
    "company": 3,
    "co.": 3,
    "technology": 3,
    "technologies": 3,
    "solutions": 3,
    "services": 3,
    "studio": 2,
    "university": 2,
    "group": 1,
}


def parse_contact_fields(raw_text: str) -> ContactFields:
    lines = normalize_lines(raw_text)
    email = first_match(EMAIL_RE, raw_text)
    phone = normalize_phone(first_match(PHONE_RE, raw_text))
    company = infer_company(lines)
    name = infer_name(lines, excluded={email, phone, company})
    return ContactFields(
        name=name,
        company=company,
        email=email,
        phone=phone,
    )


def normalize_lines(raw_text: str) -> list[str]:
    lines = []
    for line in raw_text.splitlines():
        clean = " ".join(line.strip().split())
        if clean:
            lines.append(clean)
    return lines


def first_match(pattern: re.Pattern[str], text: str) -> str | None:
    match = pattern.search(text)
    if match is None:
        return None
    return match.group(0).strip(" ,;:")


def normalize_phone(phone: str | None) -> str | None:
    if phone is None:
        return None
    return " ".join(phone.strip(" ,;:").split())


def infer_company(lines: list[str]) -> str | None:
    candidates: list[tuple[int, str]] = []
    for line in lines:
        lower = line.lower()
        if EMAIL_RE.search(line) or PHONE_RE.search(line) or URL_RE.search(line):
            continue
        score = sum(
            weight
            for keyword, weight in COMPANY_KEYWORD_WEIGHTS.items()
            if keyword in lower
        )
        if score:
            candidates.append((score, line))
    if not candidates:
        return None
    candidates.sort(key=lambda item: item[0], reverse=True)
    return candidates[0][1]


def infer_name(lines: list[str], excluded: set[str | None]) -> str | None:
    exclusions = {value.lower() for value in excluded if value}
    for line in lines:
        lower = line.lower()
        if lower in exclusions:
            continue
        if EMAIL_RE.search(line) or PHONE_RE.search(line) or URL_RE.search(line):
            continue
        if any(keyword in lower for keyword in COMPANY_KEYWORD_WEIGHTS):
            continue
        words = [word for word in re.split(r"\s+", line) if word]
        if 2 <= len(words) <= 4 and not any(char.isdigit() for char in line):
            return line
    return None
