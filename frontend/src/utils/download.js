function sanitizeFilename(filename) {
  return String(filename || "").replace(/[\\/:*?"<>|]+/g, "_").trim();
}

function decodeFilename(value) {
  const cleaned = String(value || "").trim().replace(/^"(.*)"$/, "$1");
  const encoded = cleaned.includes("''") ? cleaned.split("''").slice(1).join("''") : cleaned;

  try {
    return decodeURIComponent(encoded);
  } catch {
    return encoded;
  }
}

export function getFilenameFromContentDisposition(header) {
  if (!header) return null;

  const utf8Match = header.match(/filename\*=([^;]+)/i);
  if (utf8Match?.[1]) {
    const filename = sanitizeFilename(decodeFilename(utf8Match[1]));
    if (filename) return filename;
  }

  const plainMatch = header.match(/filename=([^;]+)/i);
  if (plainMatch?.[1]) {
    const filename = sanitizeFilename(decodeFilename(plainMatch[1]));
    if (filename) return filename;
  }

  return null;
}

export async function downloadBlobFromResponse(response, fallbackFilename) {
  const blob = await response.blob();
  const blobUrl = window.URL.createObjectURL(blob);
  const filename =
    getFilenameFromContentDisposition(response.headers.get("Content-Disposition")) ||
    fallbackFilename;

  const link = document.createElement("a");
  link.href = blobUrl;
  link.setAttribute("download", sanitizeFilename(filename) || "download");
  document.body.appendChild(link);
  link.click();
  document.body.removeChild(link);
  window.URL.revokeObjectURL(blobUrl);
}
