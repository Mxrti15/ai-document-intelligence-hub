import { DocumentRecord, deleteDocument } from "../api/client";

type DocumentsPanelProps = {
  documents: DocumentRecord[];
  selectedDocument: DocumentRecord | null;
  onRefresh: () => void;
  onSelect: (document: DocumentRecord) => void;
  onDeleted: () => void;
  onError: (message: string) => void;
};

function formatDate(value: string) {
  return new Intl.DateTimeFormat("es-ES", {
    dateStyle: "short",
    timeStyle: "short"
  }).format(new Date(value));
}

function formatBytes(bytes: number) {
  if (bytes < 1024) {
    return `${bytes} B`;
  }

  if (bytes < 1024 * 1024) {
    return `${(bytes / 1024).toFixed(1)} KB`;
  }

  return `${(bytes / (1024 * 1024)).toFixed(1)} MB`;
}

export function DocumentsPanel({
  documents,
  selectedDocument,
  onRefresh,
  onSelect,
  onDeleted,
  onError
}: DocumentsPanelProps) {
  async function handleDelete(documentId: number) {
    try {
      await deleteDocument(documentId);
      onDeleted();
    } catch (error) {
      onError(error instanceof Error ? error.message : "No se pudo eliminar el documento.");
    }
  }

  return (
    <section className="card panel-wide">
      <div className="card-header">
        <div>
          <span className="section-kicker">Repositorio local</span>
          <h2>Documentos</h2>
        </div>
        <button className="button button-secondary" onClick={onRefresh}>
          Actualizar lista
        </button>
      </div>

      {documents.length === 0 ? (
        <div className="empty-state">
          <strong>Aun no hay documentos.</strong>
          <p>Genera un PDF de prueba y subelo para empezar.</p>
        </div>
      ) : (
        <div className="documents-layout">
          <div className="table-wrap">
            <table className="table">
              <thead>
                <tr>
                  <th>ID</th>
                  <th>Nombre</th>
                  <th>Estado</th>
                  <th>Fecha</th>
                  <th>Acciones</th>
                </tr>
              </thead>
              <tbody>
                {documents.map((document) => (
                  <tr
                    className={selectedDocument?.id === document.id ? "selected-row" : ""}
                    key={document.id}
                  >
                    <td>#{document.id}</td>
                    <td>
                      <strong className="document-name">{document.original_filename}</strong>
                      <span className="document-path">{document.content_type}</span>
                    </td>
                    <td>
                      <span className={`badge badge-${document.status}`}>{document.status}</span>
                    </td>
                    <td>{formatDate(document.created_at)}</td>
                    <td>
                      <div className="table-actions">
                        <button className="button button-compact" onClick={() => onSelect(document)}>
                          Seleccionar
                        </button>
                        <button
                          className="button button-compact button-danger"
                          onClick={() => handleDelete(document.id)}
                        >
                          Eliminar
                        </button>
                      </div>
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>

          <aside className="document-detail">
            <span className="section-kicker">Seleccionado</span>
            {selectedDocument ? (
              <>
                <h3>Documento #{selectedDocument.id}</h3>
                <dl>
                  <div>
                    <dt>Nombre</dt>
                    <dd>{selectedDocument.original_filename}</dd>
                  </div>
                  <div>
                    <dt>Estado</dt>
                    <dd>
                      <span className={`badge badge-${selectedDocument.status}`}>
                        {selectedDocument.status}
                      </span>
                    </dd>
                  </div>
                  <div>
                    <dt>Storage path</dt>
                    <dd>{selectedDocument.storage_path}</dd>
                  </div>
                  <div>
                    <dt>Tamano</dt>
                    <dd>{formatBytes(selectedDocument.size_bytes)}</dd>
                  </div>
                  <div>
                    <dt>Fecha</dt>
                    <dd>{formatDate(selectedDocument.created_at)}</dd>
                  </div>
                </dl>
              </>
            ) : (
              <p className="muted">Selecciona una fila para ver su detalle operativo.</p>
            )}
          </aside>
        </div>
      )}
    </section>
  );
}
