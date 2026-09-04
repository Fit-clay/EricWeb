import { open, readdir, realpath, stat } from "node:fs/promises";
import path from "node:path";

export type HtmlPageEntry = {
  title: string;
  relativePath: string;
  href: string;
};

const htmlExtensions = new Set([".html", ".htm"]);

export function getHtmlPagesRoot() {
  const configuredPath = process.env.HTML_PAGES_PATH?.trim();
  const defaultPath = path.join(/* turbopackIgnore: true */ process.cwd(), "html-pages");
  return path.resolve(configuredPath || defaultPath);
}

function isWithinRoot(root: string, candidate: string) {
  const relative = path.relative(root, candidate);
  return relative === "" || (!relative.startsWith("..") && !path.isAbsolute(relative));
}

function toPageHref(relativePath: string) {
  const encodedPath = relativePath
    .split(path.sep)
    .map((segment) => encodeURIComponent(segment))
    .join("/");
  return `/html/${encodedPath}`;
}

function fallbackTitle(relativePath: string) {
  return path
    .basename(relativePath, path.extname(relativePath))
    .replace(/[-_]+/g, " ")
    .trim();
}

async function readDocumentTitle(filePath: string, fallback: string) {
  const handle = await open(filePath, "r");
  try {
    const buffer = Buffer.alloc(32 * 1024);
    const { bytesRead } = await handle.read(buffer, 0, buffer.length, 0);
    const source = buffer.subarray(0, bytesRead).toString("utf8");
    const title = source.match(/<title(?:\s[^>]*)?>([\s\S]*?)<\/title>/i)?.[1]
      ?.replace(/<[^>]+>/g, "")
      .replace(/\s+/g, " ")
      .trim();
    return title || fallback;
  } finally {
    await handle.close();
  }
}

async function scanHtmlPages(root: string, directory: string): Promise<HtmlPageEntry[]> {
  const entries = await readdir(directory, { withFileTypes: true });
  const pages: HtmlPageEntry[] = [];

  for (const entry of entries) {
    if (entry.name.startsWith(".") || entry.isSymbolicLink()) {
      continue;
    }

    const absolutePath = path.join(directory, entry.name);
    if (entry.isDirectory()) {
      pages.push(...(await scanHtmlPages(root, absolutePath)));
      continue;
    }

    if (!entry.isFile() || !htmlExtensions.has(path.extname(entry.name).toLowerCase())) {
      continue;
    }

    const relativePath = path.relative(root, absolutePath);
    const title = await readDocumentTitle(absolutePath, fallbackTitle(relativePath));
    pages.push({ title, relativePath, href: toPageHref(relativePath) });
  }

  return pages;
}

export async function listHtmlPages() {
  const root = getHtmlPagesRoot();
  try {
    const pages = await scanHtmlPages(root, root);
    return pages.sort((left, right) => left.title.localeCompare(right.title, "zh-CN"));
  } catch (error) {
    if ((error as NodeJS.ErrnoException).code === "ENOENT") {
      return [];
    }
    throw error;
  }
}

export async function resolveHtmlAsset(segments: string[]) {
  if (
    !segments.length ||
    segments.some(
      (segment) => !segment || segment === "." || segment === ".." || segment.includes("\0"),
    )
  ) {
    return null;
  }

  try {
    const root = await realpath(getHtmlPagesRoot());
    const candidate = path.resolve(root, ...segments);
    if (!isWithinRoot(root, candidate)) {
      return null;
    }

    const resolvedCandidate = await realpath(candidate);
    if (!isWithinRoot(root, resolvedCandidate) || !(await stat(resolvedCandidate)).isFile()) {
      return null;
    }

    return resolvedCandidate;
  } catch (error) {
    if ((error as NodeJS.ErrnoException).code === "ENOENT") {
      return null;
    }
    throw error;
  }
}
