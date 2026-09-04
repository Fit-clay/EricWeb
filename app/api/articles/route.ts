import { requireAdmin } from "../../../Service/auth/session";
import { createArticle, listArticles } from "../../../Service/articles/service";
import { toErrorResponse } from "../../../Service/lib/errors";
import type { ArticleInput, SortMode } from "../../../Service/articles/types";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";

function toSortMode(value: string | null): SortMode {
  if (value === "likes" || value === "dislikes" || value === "score") {
    return value;
  }

  return "latest";
}

export async function GET(request: Request) {
  try {
    const url = new URL(request.url);
    const articles = await listArticles({
      search: url.searchParams.get("search") ?? "",
      category: url.searchParams.get("category") ?? "",
      sort: toSortMode(url.searchParams.get("sort")),
    });
    return Response.json({ articles });
  } catch (error) {
    return toErrorResponse(error);
  }
}

export async function POST(request: Request) {
  try {
    await requireAdmin(request);
    const payload = (await request.json()) as Partial<ArticleInput>;
    const article = await createArticle(payload);
    const articles = await listArticles();
    return Response.json({ article, articles }, { status: 201 });
  } catch (error) {
    return toErrorResponse(error);
  }
}
