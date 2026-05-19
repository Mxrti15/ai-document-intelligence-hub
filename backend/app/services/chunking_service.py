import re


def _normalize_text(text: str) -> str:
    return re.sub(r"\s+", " ", text).strip()


def chunk_text(
    text: str,
    chunk_size: int,
    overlap: int,
    max_chunks: int,
    document_id: int | None = None,
) -> list[dict]:
    normalized = _normalize_text(text)
    if not normalized:
        return []

    safe_chunk_size = max(chunk_size, 200)
    safe_overlap = max(0, min(overlap, safe_chunk_size - 1))
    chunks: list[dict] = []
    start = 0

    while start < len(normalized) and len(chunks) < max_chunks:
        end = min(start + safe_chunk_size, len(normalized))
        content = normalized[start:end].strip()
        if content:
            chunk_index = len(chunks) + 1
            prefix = f"doc-{document_id}" if document_id is not None else "doc"
            chunks.append(
                {
                    "chunk_id": f"{prefix}-chunk-{chunk_index:04d}",
                    "content": content,
                    "chunk_index": chunk_index,
                }
            )
        if end >= len(normalized):
            break
        start = end - safe_overlap

    return chunks
