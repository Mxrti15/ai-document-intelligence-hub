import { useState } from "react";
import {
  DocumentRecord,
  RagAnswerResponse,
  askDocument,
  indexDocumentForRag
} from "../api/client";

type RagPanelProps = {
  selectedDocument: DocumentRecord | null;
  onError: (message: string) => void;
};

export function RagPanel({ selectedDocument, onError }: RagPanelProps) {
  const [question, setQuestion] = useState("Resume los puntos principales de este documento.");
  const [answer, setAnswer] = useState<RagAnswerResponse | null>(null);
  const [indexStatus, setIndexStatus] = useState<string | null>(null);
  const [loading, setLoading] = useState<"index" | "ask" | null>(null);

  async function handleIndex() {
    if (!selectedDocument) return;
    setLoading("index");
    setIndexStatus(null);
    try {
      const result = await indexDocumentForRag(selectedDocument.id);
      setIndexStatus(
        `${result.chunks_indexed} fragmentos indexados en ${result.index_name} (${result.latency_ms} ms).`
      );
    } catch (error) {
      onError(error instanceof Error ? error.message : "No se pudo indexar el documento.");
    } finally {
      setLoading(null);
    }
  }

  async function handleAsk() {
    if (!selectedDocument || !question.trim()) return;
    setLoading("ask");
    try {
      const result = await askDocument(selectedDocument.id, question.trim());
      setAnswer(result);
    } catch (error) {
      onError(error instanceof Error ? error.message : "No se pudo consultar el documento.");
    } finally {
      setLoading(null);
    }
  }

  return (
    <section className="card panel-wide rag-panel">
      <div className="section-heading">
        <span className="section-kicker">RAG</span>
        <h2>Preguntar al documento</h2>
        <p className="muted">
          Indexa el PDF en Azure AI Search y consulta respuestas con citas de fragmentos.
        </p>
      </div>

      <div className="rag-controls">
        <button disabled={!selectedDocument || loading !== null} onClick={handleIndex} type="button">
          {loading === "index" ? "Indexando..." : "Indexar para RAG"}
        </button>
        <textarea
          disabled={!selectedDocument || loading !== null}
          onChange={(event) => setQuestion(event.target.value)}
          rows={3}
          value={question}
        />
        <button disabled={!selectedDocument || loading !== null} onClick={handleAsk} type="button">
          {loading === "ask" ? "Preguntando..." : "Preguntar"}
        </button>
      </div>

      {!selectedDocument ? <p className="muted">Selecciona un documento para usar RAG.</p> : null}
      {indexStatus ? <div className="alert alert-ok">{indexStatus}</div> : null}

      {answer ? (
        <div className="rag-answer">
          <h3>Respuesta</h3>
          <p>{answer.answer}</p>
          <div className="usage-pill">
            Tokens: {String(answer.usage.total_tokens ?? 0)} - {answer.latency_ms} ms
          </div>
          <h3>Citas</h3>
          <div className="citation-list">
            {answer.citations.map((citation) => (
              <article className="citation-card" key={citation.chunk_id}>
                <strong>{citation.chunk_id}</strong>
                <span>{citation.filename ?? "Documento"}</span>
                <p>{citation.content_preview}</p>
              </article>
            ))}
          </div>
        </div>
      ) : null}
    </section>
  );
}
