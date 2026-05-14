import { jsPDF } from "jspdf";

export function createTestPdfFile(): File {
  const doc = new jsPDF();
  const lines = [
    "Factura de prueba",
    "Contrato de servicios",
    "Este documento contiene un posible riesgo operativo.",
    "Importe total: 100 euros.",
    "Cliente: Empresa Demo SL.",
    "Proveedor: SecOps Demo Provider.",
    "Fecha: 14/05/2026."
  ];

  doc.setFont("helvetica", "normal");
  doc.setFontSize(14);
  doc.text(lines, 20, 25);

  const blob = doc.output("blob");
  return new File([blob], "factura_riesgo_prueba.pdf", {
    type: "application/pdf"
  });
}
