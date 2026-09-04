import { readFile } from "node:fs/promises";
import path from "node:path";
import { resolveHtmlAsset } from "../../../Service/html/pages";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";

const contentTypes: Record<string, string> = {
  ".html": "text/html; charset=utf-8",
  ".htm": "text/html; charset=utf-8",
  ".css": "text/css; charset=utf-8",
  ".js": "text/javascript; charset=utf-8",
  ".mjs": "text/javascript; charset=utf-8",
  ".json": "application/json; charset=utf-8",
  ".txt": "text/plain; charset=utf-8",
  ".svg": "image/svg+xml",
  ".png": "image/png",
  ".jpg": "image/jpeg",
  ".jpeg": "image/jpeg",
  ".gif": "image/gif",
  ".webp": "image/webp",
  ".ico": "image/x-icon",
  ".pdf": "application/pdf",
  ".woff": "font/woff",
  ".woff2": "font/woff2",
  ".ttf": "font/ttf",
  ".otf": "font/otf",
  ".mp3": "audio/mpeg",
  ".mp4": "video/mp4",
  ".webm": "video/webm",
};

export async function GET(
  _request: Request,
  { params }: { params: Promise<{ path: string[] }> },
) {
  const { path: pathSegments } = await params;
  const filePath = await resolveHtmlAsset(pathSegments);

  if (!filePath) {
    return new Response("HTML 页面不存在", { status: 404 });
  }

  const extension = path.extname(filePath).toLowerCase();
  const body = await readFile(filePath);
  const isHtml = extension === ".html" || extension === ".htm";

  return new Response(new Uint8Array(body), {
    headers: {
      "content-type": contentTypes[extension] || "application/octet-stream",
      "cache-control": isHtml ? "no-cache" : "public, max-age=3600",
      "x-content-type-options": "nosniff",
    },
  });
}
