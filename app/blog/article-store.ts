import type { Article, ArticleInput, CoverStyle, SortMode } from "../../Service/articles/types";

export type { Article, ArticleInput, CoverStyle, SortMode };

export const defaultArticles: Article[] = [];

export function splitTags(value: string) {
  return value
    .split(/[,，\s]+/)
    .map((tag) => tag.trim())
    .filter(Boolean);
}
