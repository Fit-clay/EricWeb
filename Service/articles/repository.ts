import { eq } from "drizzle-orm";
import { articles } from "../../db/schema";
import { ensureServiceSchema, getServiceDb } from "../lib/db";
import type { Article, ArticleInput, CoverStyle, VoteType } from "./types";

type ArticleRow = typeof articles.$inferSelect;

const coverStyles: CoverStyle[] = ["mountain", "river", "seal"];

function parseTags(value: string) {
  try {
    const parsed = JSON.parse(value) as unknown;
    return Array.isArray(parsed) ? parsed.filter((item): item is string => typeof item === "string") : [];
  } catch {
    return [];
  }
}

export function toArticle(row: ArticleRow): Article {
  return {
    id: row.id,
    title: row.title,
    category: row.category,
    tags: parseTags(row.tags),
    cover: row.cover as CoverStyle,
    coverUrl: row.coverUrl || undefined,
    content: row.content,
    likes: row.likes,
    dislikes: row.dislikes,
    createdAt: row.createdAt,
    updatedAt: row.updatedAt,
  };
}

export async function findArticles() {
  await ensureServiceSchema();
  const db = getServiceDb();
  const rows = await db.select().from(articles);
  return rows.map(toArticle);
}

export async function findArticleById(id: string) {
  await ensureServiceSchema();
  const db = getServiceDb();
  const [row] = await db.select().from(articles).where(eq(articles.id, id)).limit(1);
  return row ? toArticle(row) : null;
}

export async function insertArticle(id: string, input: ArticleInput, count: number) {
  await ensureServiceSchema();
  const now = new Date().toISOString();
  const db = getServiceDb();
  const [row] = await db
    .insert(articles)
    .values({
      id,
      title: input.title,
      category: input.category,
      tags: JSON.stringify(input.tags),
      cover: coverStyles[count % coverStyles.length],
      coverUrl: input.coverUrl || null,
      content: input.content,
      likes: 0,
      dislikes: 0,
      createdAt: now,
      updatedAt: now,
    })
    .returning();
  return toArticle(row);
}

export async function deleteArticleById(id: string) {
  await ensureServiceSchema();
  const db = getServiceDb();
  const existing = await findArticleById(id);

  if (!existing) {
    return false;
  }

  await db.delete(articles).where(eq(articles.id, id));
  return true;
}

export async function incrementArticleVote(id: string, vote: VoteType) {
  await ensureServiceSchema();
  const existing = await findArticleById(id);

  if (!existing) {
    return null;
  }

  const db = getServiceDb();
  const nextLikes = vote === "likes" ? existing.likes + 1 : existing.likes;
  const nextDislikes = vote === "dislikes" ? existing.dislikes + 1 : existing.dislikes;

  await db
    .update(articles)
    .set({
      likes: nextLikes,
      dislikes: nextDislikes,
      updatedAt: new Date().toISOString(),
    })
    .where(eq(articles.id, id));

  return findArticleById(id);
}
