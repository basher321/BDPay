// Spec 09 CORS for pay-session: headers only when the request Origin equals env PAY_PAGE_ORIGIN exactly.
// An empty or unset PAY_PAGE_ORIGIN allows no origin (fails closed).

export function corsHeaders(
  req: Request,
  allowedOrigin: string | undefined,
): Record<string, string> {
  const origin = req.headers.get("Origin");
  if (!allowedOrigin || origin === null || origin !== allowedOrigin) return {};
  return {
    "Access-Control-Allow-Origin": allowedOrigin,
    "Access-Control-Allow-Methods": "GET, POST, OPTIONS",
    "Access-Control-Allow-Headers": "content-type, x-pay-token",
    "Access-Control-Max-Age": "600",
    Vary: "Origin",
  };
}

/** Adds [headers] to a response (Response headers are mutable for responses we create). */
export function withHeaders(
  res: Response,
  headers: Record<string, string>,
): Response {
  for (const [k, v] of Object.entries(headers)) res.headers.set(k, v);
  return res;
}
