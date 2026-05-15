import { useRef, useState } from "react";
import { DocumentRecord, uploadDocument } from "../api/client";
import { createTestPdfFile } from "../utils/createTestPdf";

type UploadPanelProps = {
  onUploaded: (document: DocumentRecord) => void;
  onError: (message: string) => void;
};

function formatBytes(bytes: number) {
  if (bytes < 1024) {
    return `${bytes} B`;
  }

  if (bytes < 1024 * 1024) {
    return `${(bytes / 1024).toFixed(1)} KB`;
  }

  return `${(bytes / (1024 * 1024)).toFixed(1)} MB`;
}

export function UploadPanel({ onUploaded, onError }: UploadPanelProps) {
  const inputRef = useRef<HTMLInputElement | null>(null);
  const [file, setFile] = useState<File | null>(null);
  const [lastUploaded, setLastUploaded] = useState<DocumentRecord | null>(null);
  const [isUploading, setIsUploading] = useState(false);
  const [uploadMessage, setUploadMessage] = useState<string | null>(null);

  function handleGeneratePdf() {
    const demoFile = createTestPdfFile();
    setFile(demoFile);
    setLastUploaded(null);
    setUploadMessage(`${demoFile.name} listo para subir`);
  }

  async function handleUpload() {
    if (!file) {
      onError("Selecciona o genera un PDF antes de subirlo.");
      return;
    }

    try {
      setIsUploading(true);
      setUploadMessage("Subiendo documento...");
      const document = await uploadDocument(file);
      setLastUploaded(document);
      setUploadMessage(`Documento subido correctamente - ID #${document.id}`);
      onUploaded(document);
    } catch (error) {
      const errorMessage = error instanceof Error ? error.message : "No se pudo subir el documento.";
      setUploadMessage(null);
      onError(`No se pudo subir el documento: ${errorMessage}`);
    } finally {
      setIsUploading(false);
    }
  }

  return (
    <section className="card">
      <div className="card-header compact">
        <div>
          <span className="section-kicker">PDF</span>
          <h2>Subida de documento</h2>
        </div>
      </div>

      <button className="drop-zone" type="button" onClick={() => inputRef.current?.click()}>
        <span className="drop-icon">PDF</span>
        <strong>Selecciona un PDF o genera uno de prueba</strong>
        <small>{file ? `${file.name} - ${formatBytes(file.size)}` : "Archivo local, maximo MVP"}</small>
      </button>

      <input
        ref={inputRef}
        accept="application/pdf,.pdf"
        className="sr-only"
        type="file"
        onChange={(event) => {
          const selectedFile = event.target.files?.[0] ?? null;
          setFile(selectedFile);
          setLastUploaded(null);
          setUploadMessage(selectedFile ? `${selectedFile.name} seleccionado` : null);
        }}
      />

      <div className="actions">
        <button className="button button-secondary" onClick={handleGeneratePdf}>
          Generar PDF demo
        </button>
        <button className="button button-primary" disabled={isUploading || !file} onClick={handleUpload}>
          {isUploading ? "Subiendo..." : "Subir PDF"}
        </button>
      </div>

      {uploadMessage ? <div className="mini-result">{uploadMessage}</div> : null}
      {lastUploaded ? (
        <div className="upload-summary">
          <strong>Respuesta resumida</strong>
          <span>ID #{lastUploaded.id}</span>
          <span>{lastUploaded.original_filename}</span>
          <span className={`badge badge-${lastUploaded.status}`}>{lastUploaded.status}</span>
        </div>
      ) : null}
    </section>
  );
}
