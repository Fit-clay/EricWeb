import { requireAdmin } from "../../../../Service/auth/session";
import { getArticle, listArticles, removeArticle, voteArticle } from "../../../../Service/articles/service";
import { toErrorResponse } from "../../../../Service/lib/errors";
import type { VoteType } from "../../../../Service/articles/types";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";

export async function GET(
  _request: Request,
  { params }: { params: Promise<{ id: string }> }
) {
  try {
    const { id } = await params;
    const article = await getArticle(id);
    return Response.json({ article });
  } catch (error) {
    return toErrorResponse(error);
  }
}

export async function PATCH(
  request: Request,
  { params }: { params: Promise<{ id: string }> }
) {
  try {
    const { id } = await params;
    const payload = (await request.json()) as { vote?: VoteType };

    if (payload.vote !== "likes" && payload.vote !== "dislikes") {
      return Response.json({ error: "投票类型不正确" }, { status: 400 });
    }

    const article = await voteArticle(id, payload.vote);
    return Response.json({ article });
  } catch (error) {
    return toErrorResponse(error);
  }
}

export async function DELETE(
  request: Request,
  { params }: { params: Promise<{ id: string }> }
) {
  try {
    await requireAdmin(request);
    const { id } = await params;
    await removeArticle(id);
    const articles = await listArticles();
    return Response.json({ articles });
  } catch (error) {
    return toErrorResponse(error);
  }
}
