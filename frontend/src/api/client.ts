const API_BASE_URL = "http://localhost:8000";

export type DocumentRecord = {
  id: number;
  original_filename: string;
  stored_filename: string;
  storage_path: string;
  content_type: string;
  size_bytes: number;
  status: string;
  created_at: string;
  processed_at: string | null;
};

export type DocumentListResponse = {
  documents: DocumentRecord[];
  total: number;
};

export type AnalysisRecord = {
  id: number;
  document_id: number;
  document_type: string;
  language: string;
  summary: string;
  risk_level: string;
  structured_data_json: string;
  tags_json: string;
  created_at: string;
};

export type AnalyzeDocumentResponse = {
  document_id: number;
  status: string;
  analysis: AnalysisRecord;
  usage: Record<string, unknown>;
};

export type UsageAnalytics = {
  documents_uploaded: number;
  documents_processed: number;
  documents_failed: number;
  total_tokens: number;
  estimated_cost: number;
};

async function handleResponse<T>(response: Response): Promise<T> {
  const data = await response.json().catch(() => null);

  if (!response.ok) {
    const message =
      data?.detail ||
      data?.message ||
      `Request failed with status ${response.status}`;

    throw new Error(message);
  }

  return data as T;
}

export async function checkHealth(): Promise<Record<string, unknown>> {
  return handleResponse(await fetch(`${API_BASE_URL}/health`));
}

export async function checkReady(): Promise<Record<string, unknown>> {
  return handleResponse(await fetch(`${API_BASE_URL}/ready`));
}

export async function uploadDocument(file: File): Promise<DocumentRecord> {
  const formData = new FormData();
  formData.append("file", file);

  return handleResponse(
    await fetch(`${API_BASE_URL}/documents/upload`, {
      method: "POST",
      body: formData
    })
  );
}

export async function listDocuments(): Promise<DocumentListResponse> {
  return handleResponse(await fetch(`${API_BASE_URL}/documents`));
}

export async function getDocument(documentId: number): Promise<DocumentRecord> {
  return handleResponse(await fetch(`${API_BASE_URL}/documents/${documentId}`));
}

export async function deleteDocument(documentId: number): Promise<DocumentRecord> {
  return handleResponse(
    await fetch(`${API_BASE_URL}/documents/${documentId}`, {
      method: "DELETE"
    })
  );
}

export async function analyzeDocument(documentId: number): Promise<AnalyzeDocumentResponse> {
  return handleResponse(
    await fetch(`${API_BASE_URL}/documents/${documentId}/analyze`, {
      method: "POST"
    })
  );
}

export async function getDocumentAnalysis(documentId: number): Promise<AnalysisRecord> {
  return handleResponse(await fetch(`${API_BASE_URL}/documents/${documentId}/analysis`));
}

export async function reprocessDocument(documentId: number): Promise<AnalyzeDocumentResponse> {
  return handleResponse(
    await fetch(`${API_BASE_URL}/documents/${documentId}/reprocess`, {
      method: "POST"
    })
  );
}

export async function getUsageAnalytics(): Promise<UsageAnalytics> {
  return handleResponse(await fetch(`${API_BASE_URL}/analytics/usage`));
}
