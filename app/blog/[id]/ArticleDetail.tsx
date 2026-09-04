"use client";

import { useEffect, useState } from "react";
import Link from "next/link";
import type { Article } from "../article-store";

type ArticleDetailProps = {
  articleId: string;
};

export function ArticleDetail({ articleId }: ArticleDetailProps) {
  const [article, setArticle] = useState<Article | null>(null);
  const [missing, setMissing] = useState(false);

  useEffect(() => {
    let active = true;

    async function loadArticle() {
      const response = await fetch(`/api/articles/${articleId}`, { cache: "no-store" });

      if (!active) {
        return;
      }

      if (!response.ok) {
        setMissing(true);
        return;
      }

      const payload = (await response.json()) as { article: Article };
      setArticle(payload.article);
    }

    void loadArticle();
    return () => {
      active = false;
    };
  }, [articleId]);

  async function vote(type: "likes" | "dislikes") {
    const response = await fetch(`/api/articles/${articleId}`, {
      method: "PATCH",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ vote: type }),
    });

    if (!response.ok) {
      return;
    }

    const payload = (await response.json()) as { article: Article };
    setArticle(payload.article);
  }

  return (
    <main className="sub-page blog-page">
      <div className="paper-grain" />
      <div className="ink-wash ink-wash-one" />
      <div className="ink-wash ink-wash-two" />
      <div className="ink-wash ink-wash-three" />

      <Link className="back-link" href="/blog">
        归文
      </Link>

      {article ? (
        <article className="detail-shell">
          {article.coverUrl ? (
            <img className="detail-cover image-cover" src={article.coverUrl} alt="" />
          ) : (
            <div className={`detail-cover cover-${article.cover}`} role="img" aria-label="封面图" />
          )}

          <header className="detail-header">
            <p className="article-category">{article.category}</p>
            <h1 className="detail-title">{article.title}</h1>
            <div className="tag-row">
              {article.tags.map((tag) => (
                <span key={tag}>{tag}</span>
              ))}
            </div>
          </header>

          <div className="vote-panel" aria-label="赞踩">
            <button onClick={() => vote("likes")} type="button">
              赞 <strong>{article.likes}</strong>
            </button>
            <button onClick={() => vote("dislikes")} type="button">
              踩 <strong>{article.dislikes}</strong>
            </button>
          </div>

          <MarkdownContent content={article.content || "这篇文章还没有正文。"} />
        </article>
      ) : (
        <section className="detail-shell">
          <p className="article-category">{missing ? "未找到" : "读取中"}</p>
          <h1 className="detail-title">{missing ? "文章不在库中" : "正在取文"}</h1>
          <p className="sub-note">
            {missing ? "它可能已被删除，或数据库中没有这篇文章。" : "正在读取数据库文章内容。"}
          </p>
        </section>
      )}
    </main>
  );
}

function MarkdownContent({ content }: { content: string }) {
  const blocks = content.split("\n");

  return (
    <section className="markdown-article" aria-label="正文">
      {blocks.map((line, index) => {
        const key = `${index}-${line}`;
        if (!line.trim()) {
          return <div className="markdown-gap" key={key} />;
        }
        if (line.startsWith("# ")) {
          return <h2 key={key}>{line.slice(2)}</h2>;
        }
        if (line.startsWith("## ")) {
          return <h3 key={key}>{line.slice(3)}</h3>;
        }
        if (line.startsWith("> ")) {
          return <blockquote key={key}>{line.slice(2)}</blockquote>;
        }
        if (line.startsWith("- ")) {
          return (
            <p className="markdown-list-item" key={key}>
              {line.slice(2)}
            </p>
          );
        }
        return <p key={key}>{line}</p>;
      })}
    </section>
  );
}
