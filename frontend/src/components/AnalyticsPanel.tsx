import { useState } from "react";
import { UsageAnalytics, getUsageAnalytics } from "../api/client";

type AnalyticsPanelProps = {
  onError: (message: string) => void;
};

export function AnalyticsPanel({ onError }: AnalyticsPanelProps) {
  const [analytics, setAnalytics] = useState<UsageAnalytics | null>(null);
  const [isLoading, setIsLoading] = useState(false);

  async function handleLoad() {
    try {
      setIsLoading(true);
      setAnalytics(await getUsageAnalytics());
    } catch (error) {
      onError(error instanceof Error ? error.message : "No se pudieron cargar las métricas.");
    } finally {
      setIsLoading(false);
    }
  }

  return (
    <section className="panel">
      <div className="panel-header">
        <h2>Analytics</h2>
        <button onClick={handleLoad}>Ver analytics</button>
      </div>
      {isLoading ? <p className="loading-text">Cargando...</p> : null}
      {analytics ? (
        <>
          <div className="metric-grid">
            <div>
              <span>Subidos</span>
              <strong>{analytics.documents_uploaded}</strong>
            </div>
            <div>
              <span>Procesados</span>
              <strong>{analytics.documents_processed}</strong>
            </div>
            <div>
              <span>Fallidos</span>
              <strong>{analytics.documents_failed}</strong>
            </div>
            <div>
              <span>Tokens</span>
              <strong>{analytics.total_tokens}</strong>
            </div>
            <div>
              <span>Coste</span>
              <strong>{analytics.estimated_cost}</strong>
            </div>
          </div>
          <pre>{JSON.stringify(analytics, null, 2)}</pre>
        </>
      ) : null}
    </section>
  );
}
