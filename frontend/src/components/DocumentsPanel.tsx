import { DocumentRecord, deleteDocument } from "../api/client";

type DocumentsPanelProps = {
  documents: DocumentRecord[];
  selectedDocument: DocumentRecord | null;
  onRefresh: () => void;
  onSelect: (document: DocumentRecord) => void;
  onDeleted: () => void;
  onError: (message: string) => void;
};

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
    <section className="panel panel-wide">
      <div className="panel-header">
        <h2>Documentos</h2>
        <button onClick={onRefresh}>Actualizar lista</button>
      </div>
      <div className="table-wrap">
        <table>
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
                <td>{document.id}</td>
                <td>{document.original_filename}</td>
                <td>
                  <span className={`status status-${document.status}`}>{document.status}</span>
                </td>
                <td>{new Date(document.created_at).toLocaleString()}</td>
                <td className="table-actions">
                  <button onClick={() => onSelect(document)}>Seleccionar</button>
                  <button className="button-secondary" onClick={() => handleDelete(document.id)}>
                    Eliminar
                  </button>
                </td>
              </tr>
            ))}
            {documents.length === 0 ? (
              <tr>
                <td colSpan={5}>No hay documentos.</td>
              </tr>
            ) : null}
          </tbody>
        </table>
      </div>
    </section>
  );
}
