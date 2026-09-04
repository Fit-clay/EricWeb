import { ServiceError } from "../lib/errors";
import { createId } from "../lib/ids";
import {
  deleteArticleById,
  findArticleById,
  findArticles,
  incrementArticleVote,
  insertArticle,
} from "./repository";
import type { Article, ArticleInput, ArticleListOptions, SortMode, VoteType } from "./types";

function sanitizeTags(value: unknown) {
  if (!Array.isArray(value)) {
    return [];
  }

  return value
    .map((tag) => (typeof tag === "string" ? tag.trim() : ""))
    .filter(Boolean)
    .slice(0, 12);
}

function normalizeArticleInput(input: Partial<ArticleInput>) {
  const title = input.title?.trim() ?? "";

  if (!title) {
    throw new ServiceError("标题不能为空", 400);
  }

  return {
    title,
    category: input.category?.trim() || "随笔",
    tags: sanitizeTags(input.tags),
    coverUrl: input.coverUrl?.trim() || undefined,
    content: input.content?.trim() ?? "",
  };
}

function sortArticles(articles: Article[], sort: SortMode = "latest") {
  return [...articles].sort((left, right) => {
    if (sort === "likes") {
      return right.likes - left.likes;
    }
    if (sort === "dislikes") {
      return right.dislikes - left.dislikes;
    }
    if (sort === "score") {
      return right.likes - right.dislikes - (left.likes - left.dislikes);
    }

    return (right.createdAt ?? "").localeCompare(left.createdAt ?? "");
  });
}

export async function listArticles(options: ArticleListOptions = {}) {
  const search = options.search?.trim().toLowerCase() ?? "";
  const category = options.category?.trim() ?? "";
  const rows = await findArticles();

  const filtered = rows.filter((article) => {
    const text = [article.title, article.category, article.content, ...article.tags]
      .join(" ")
      .toLowerCase();
    const matchesSearch = !search || text.includes(search);
    const matchesCategory = !category || category === "全部" || article.category === category;
    return matchesSearch && matchesCategory;
  });

  return sortArticles(filtered, options.sort);
}

export async function getArticle(id: string) {
  const article = await findArticleById(id);

  if (!article) {
    throw new ServiceError("文章不存在", 404);
  }

  return article;
}

export async function createArticle(input: Partial<ArticleInput>) {
  const articleInput = normalizeArticleInput(input);
  const currentArticles = await findArticles();
  return insertArticle(createId(), articleInput, currentArticles.length);
}

export async function removeArticle(id: string) {
  const removed = await deleteArticleById(id);

  if (!removed) {
    throw new ServiceError("文章不存在", 404);
  }
}

export async function voteArticle(id: string, vote: VoteType) {
  const article = await incrementArticleVote(id, vote);

  if (!article) {
    throw new ServiceError("文章不存在", 404);
  }

  return article;
}
