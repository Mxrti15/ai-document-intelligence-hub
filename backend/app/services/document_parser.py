from io import BytesIO
from pathlib import Path

from pypdf import PdfReader
from pypdf.errors import PdfReadError


class DocumentParserError(Exception):
    pass


def extract_text_from_pdf(file_path: str) -> str:
    path = Path(file_path)
    if not path.exists():
        raise DocumentParserError("PDF file not found.")

    return extract_text_from_pdf_bytes(path.read_bytes())


def extract_text_from_pdf_bytes(file_bytes: bytes) -> str:
    if not file_bytes:
        raise DocumentParserError("PDF file is empty.")

    try:
        reader = PdfReader(BytesIO(file_bytes))
        page_texts = [page.extract_text() or "" for page in reader.pages]
    except PdfReadError as exc:
        raise DocumentParserError("PDF file is corrupted or cannot be read.") from exc
    except OSError as exc:
        raise DocumentParserError("PDF file cannot be opened.") from exc

    text = "\n\n".join(page_text.strip() for page_text in page_texts if page_text.strip()).strip()
    if not text:
        raise DocumentParserError("PDF does not contain extractable text.")

    return text
