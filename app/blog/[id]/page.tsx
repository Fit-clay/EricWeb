import type { Metadata } from "next";
import { ArticleDetail } from "./ArticleDetail";

export const metadata: Metadata = {
  title: "文章详情 | 貔貅",
};

export default async function ArticlePage({
  params,
}: {
  params: Promise<{ id: string }>;
}) {
  const { id } = await params;
  return <ArticleDetail articleId={id} />;
}
