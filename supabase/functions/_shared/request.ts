export type BoundedJsonResult =
  | { ok: true; value: Record<string, unknown> }
  | { ok: false; reason: "invalid" | "too_large" | "unsupported_media_type" };

export async function readBoundedJsonObject(
  request: Request,
  maxBytes: number,
): Promise<BoundedJsonResult> {
  const mediaType = request.headers.get("content-type")?.split(";", 1)[0]
    .trim().toLowerCase();
  if (mediaType != null && mediaType !== "application/json") {
    return { ok: false, reason: "unsupported_media_type" };
  }
  const declaredLength = request.headers.get("content-length");
  if (declaredLength != null) {
    const length = Number(declaredLength);
    if (!Number.isSafeInteger(length) || length < 0) {
      return { ok: false, reason: "invalid" };
    }
    if (length > maxBytes) return { ok: false, reason: "too_large" };
  }
  if (request.body == null) return { ok: false, reason: "invalid" };

  const reader = request.body.getReader();
  const chunks: Uint8Array[] = [];
  let length = 0;
  try {
    while (true) {
      const result = await reader.read();
      if (result.done) break;
      length += result.value.length;
      if (length > maxBytes) {
        await reader.cancel("request_too_large");
        return { ok: false, reason: "too_large" };
      }
      chunks.push(result.value);
    }
  } catch {
    return { ok: false, reason: "invalid" };
  }

  const bytes = new Uint8Array(length);
  let offset = 0;
  for (const chunk of chunks) {
    bytes.set(chunk, offset);
    offset += chunk.length;
  }
  try {
    const parsed: unknown = JSON.parse(
      new TextDecoder("utf-8", { fatal: true }).decode(bytes),
    );
    return isRecord(parsed)
      ? { ok: true, value: parsed }
      : { ok: false, reason: "invalid" };
  } catch {
    return { ok: false, reason: "invalid" };
  }
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value != null && !Array.isArray(value);
}
