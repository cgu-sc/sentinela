export async function getApiErrorMessage(response, fallbackMessage) {
  try {
    const text = await response.text();
    if (!text.trim()) return fallbackMessage;

    let payload = null;
    try {
      payload = JSON.parse(text);
    } catch {
      return text;
    }

    if (typeof payload?.detail === "string" && payload.detail.trim()) {
      return payload.detail;
    }
    if (Array.isArray(payload?.detail) && payload.detail.length) {
      return payload.detail.map((item) => item.msg || String(item)).join("; ");
    }
    if (typeof payload?.message === "string" && payload.message.trim()) {
      return payload.message;
    }
  } catch {
    // Mantem o fallback abaixo.
  }

  return fallbackMessage;
}
