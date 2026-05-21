const DEFAULT_PYTHON_BASE_URL = "https://nutrikidneyocrpythonservice.onrender.com";

const pythonBaseUrl =
  process.env.PRESCRIPTION_OCR_PYTHON_BASE_URL || DEFAULT_PYTHON_BASE_URL;

function buildPythonUrl(path) {
  return new URL(path, pythonBaseUrl);
}

async function callPythonService(path, options = {}) {
  const { method = "GET", body } = options;
  const url = buildPythonUrl(path);

  let response;
  try {
    response = await fetch(url, {
      method,
      headers: body ? { "Content-Type": "application/json" } : undefined,
      body: body ? JSON.stringify(body) : undefined,
    });
  } catch (error) {
    const wrapped = new Error(
      `Prescription OCR Python service unavailable at ${pythonBaseUrl}`,
    );
    wrapped.cause = error;
    wrapped.statusCode = 503;
    throw wrapped;
  }

  const text = await response.text();
  let data = {};
  if (text) {
    try {
      data = JSON.parse(text);
    } catch (_) {
      data = { raw: text };
    }
  }

  if (!response.ok) {
    const detail = data?.detail;
    const error = new Error(
      detail?.message ||
        detail?.error ||
        data?.error ||
        data?.message ||
        "Prescription OCR service request failed",
    );
    error.statusCode = response.status;
    error.data = data;
    throw error;
  }

  return data;
}

async function scanMedicationPrescription(payload) {
  return callPythonService("/api/v1/medications/scan", {
    method: "POST",
    body: payload,
  });
}

module.exports = {
  scanMedicationPrescription,
  extractPrescription: scanMedicationPrescription,
};
