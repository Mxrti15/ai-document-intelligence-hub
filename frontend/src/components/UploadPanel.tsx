import { useRef, useState } from "react";
import { DocumentRecord, uploadDocument } from "../api/client";
import { createTestPdfFile } from "../utils/createTestPdf";

type UploadPanelProps = {
  onUploaded: (document: DocumentRecord) => void;
  onError: (message: string) => void;
};

export function UploadPanel({ onUploaded, onError }: UploadPanelProps) {
  const inputRef = useRef<HTMLInputElement | null>(null);
  const [file, setFile] = useState<File | null>(null);
  const [lastUploaded, setLastUploaded] = useState<DocumentRecord | null>(null);
  const [isUploading, setIsUploading] = useState(false);

  function handleGeneratePdf() {
    setFile(createTestPdfFile());
    setLastUploaded(null);
  }

  async function handleUpload() {
    if (!file) {
      onError("Selecciona o genera un PDF antes de subirlo.");
      return;
    }

    try {
      setIsUploading(true);
      const document = await uploadDocument(file);
      setLastUploaded(document);
      onUploaded(document);
    } catch (error) {
      onError(error instanceof Error ? error.message : "No se pudo subir el documento.");
    } finally {
      setIsUploading(false);
    }
  }

  return (
    <section className="panel">
      <div className="panel-header">
        <h2>Subida de documento</h2>
      </div>
      <label className="file-picker">
        <span>PDF manual</span>
        <input
          ref={inputRef}
          accept="application/pdf,.pdf"
          type="file"
          onChange={(event) => setFile(event.target.files?.[0] ?? null)}
        />
      </label>
      <p className="muted">{file ? file.name : "Ningún archivo seleccionado"}</p>
      <div className="actions">
        <button onClick={handleGeneratePdf}>Generar PDF de prueba</button>
        <button disabled={isUploading} onClick={handleUpload}>
          {isUploading ? "Subiendo documento..." : "Subir documento"}
        </button>
      </div>
      {lastUploaded ? <pre>{JSON.stringify(lastUploaded, null, 2)}</pre> : null}
    </section>
  );
}
