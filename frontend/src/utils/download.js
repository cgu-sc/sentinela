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

function getDesktopApi() {
  return window?.pywebview?.api ?? null;
}

function blobToBase64(blob) {
  return new Promise((resolve, reject) => {
    const reader = new FileReader();
    reader.onload = () => {
      const result = String(reader.result || "");
      const [, base64] = result.split(",");
      if (!base64) {
        reject(new Error("Conteudo do arquivo invalido para salvamento."));
        return;
      }
      resolve(base64);
    };
    reader.onerror = () => reject(reader.error || new Error("Erro ao ler arquivo."));
    reader.readAsDataURL(blob);
  });
}

function base64ToBlob(base64, mimeType) {
  const binary = atob(String(base64 || ""));
  const bytes = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i += 1) {
    bytes[i] = binary.charCodeAt(i);
  }
  return new Blob([bytes], { type: mimeType });
}

export async function openDownloadedFile(path) {
  const desktopApi = getDesktopApi();
  if (!desktopApi?.open_file) {
    throw new Error("Abertura nativa de arquivo indisponivel.");
  }
  const result = await desktopApi.open_file(path);
  if (!result?.ok) {
    throw new Error(result?.error || "Nao foi possivel abrir o arquivo.");
  }
  return result;
}

export async function convertDocxToPdf(path) {
  const desktopApi = getDesktopApi();
  if (!desktopApi?.convert_docx_to_pdf) {
    throw new Error("Conversao DOCX/PDF indisponivel no modo atual.");
  }
  const result = await desktopApi.convert_docx_to_pdf(path);
  if (!result?.ok) {
    throw new Error(result?.error || "Nao foi possivel converter o DOCX para PDF.");
  }
  return result;
}

export async function createPdfObjectUrlFromDesktopFile(path) {
  const desktopApi = getDesktopApi();
  if (!desktopApi?.read_pdf_base64) {
    throw new Error("Visualizacao nativa de PDF indisponivel.");
  }
  const result = await desktopApi.read_pdf_base64(path);
  if (!result?.ok) {
    throw new Error(result?.error || "Nao foi possivel ler o PDF salvo.");
  }
  const blob = base64ToBlob(result.base64, "application/pdf");
  return {
    ...result,
    url: window.URL.createObjectURL(blob),
  };
}

export async function saveBlobOrDownload(blob, filename) {
  const safeFilename = sanitizeFilename(filename) || "download";

  const desktopApi = getDesktopApi();
  if (desktopApi?.save_file) {
    const base64 = await blobToBase64(blob);
    const result = await desktopApi.save_file(safeFilename, base64);
    if (!result?.ok) {
      throw new Error(result?.error || "Nao foi possivel salvar o arquivo.");
    }
    return { ...result, desktop: true };
  }

  const blobUrl = window.URL.createObjectURL(blob);
  const link = document.createElement("a");
  link.href = blobUrl;
  link.setAttribute("download", safeFilename);
  document.body.appendChild(link);
  link.click();
  document.body.removeChild(link);
  window.URL.revokeObjectURL(blobUrl);
  return { ok: true, filename: safeFilename, desktop: false };
}

export async function downloadBlobFromResponse(response, fallbackFilename) {
  const blob = await response.blob();
  const filename =
    getFilenameFromContentDisposition(response.headers.get("Content-Disposition")) ||
    fallbackFilename;

  return saveBlobOrDownload(blob, filename);
}
