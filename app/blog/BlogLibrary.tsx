"use client";

import { FormEvent, useEffect, useMemo, useRef, useState } from "react";
import Link from "next/link";
import { defaultArticles, splitTags } from "./article-store";
import type { Article, ArticleInput, SortMode } from "./article-store";

type AuthPayload = {
  authenticated: boolean;
};

type ArticlesPayload = {
  articles: Article[];
};

export function BlogLibrary() {
  const [articles, setArticles] = useState<Article[]>(defaultArticles);
  const [query, setQuery] = useState("");
  const [category, setCategory] = useState("全部");
  const [sortMode, setSortMode] = useState<SortMode>("latest");
  const [loggedIn, setLoggedIn] = useState(false);
  const [loginVisible, setLoginVisible] = useState(false);
  const titleClicks = useRef(0);
  const [loginName, setLoginName] = useState("");
  const [loginPass, setLoginPass] = useState("");
  const [loginError, setLoginError] = useState("");
  const [editing, setEditing] = useState(false);
  const [draftTitle, setDraftTitle] = useState("");
  const [draftCategory, setDraftCategory] = useState("随笔");
  const [draftTags, setDraftTags] = useState("");
  const [draftCoverUrl, setDraftCoverUrl] = useState("");
  const [draftContent, setDraftContent] = useState("");
  const [statusText, setStatusText] = useState("");

  useEffect(() => {
    let active = true;

    async function initialize() {
      const [articlesResponse, authResponse] = await Promise.all([
        fetch("/api/articles", { cache: "no-store" }),
        fetch("/api/auth/me", { cache: "no-store" }),
      ]);

      if (!active) {
        return;
      }

      if (articlesResponse.ok) {
        const payload = (await articlesResponse.json()) as ArticlesPayload;
        setArticles(payload.articles);
      } else {
        setStatusText("文章数据库暂时不可用，请稍后再试。");
      }

      if (authResponse.ok) {
        const payload = (await authResponse.json()) as AuthPayload;
        setLoggedIn(payload.authenticated);
      } else {
        setLoggedIn(false);
      }
    }

    void initialize();
    return () => {
      active = false;
    };
  }, []);

  const categories = useMemo(() => {
    return ["全部", ...Array.from(new Set(articles.map((article) => article.category)))];
  }, [articles]);

  const filteredArticles = useMemo(() => {
    const filtered = articles.filter((article) => {
      const text = [article.title, article.category, article.content, ...article.tags]
        .join(" ")
        .toLowerCase();
      const matchesQuery = text.includes(query.trim().toLowerCase());
      const matchesCategory = category === "全部" || article.category === category;
      return matchesQuery && matchesCategory;
    });

    return [...filtered].sort((left, right) => {
      if (sortMode === "likes") {
        return right.likes - left.likes;
      }
      if (sortMode === "dislikes") {
        return right.dislikes - left.dislikes;
      }
      if (sortMode === "score") {
        return right.likes - right.dislikes - (left.likes - left.dislikes);
      }
      return (right.createdAt ?? "").localeCompare(left.createdAt ?? "");
    });
  }, [articles, category, query, sortMode]);

  function revealLogin() {
    if (loggedIn || loginVisible) {
      return;
    }

    titleClicks.current += 1;
    if (titleClicks.current >= 3) {
      setLoginVisible(true);
    }
  }

  async function login(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();

    const response = await fetch("/api/auth/login", {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ name: loginName, password: loginPass }),
    });

    if (!response.ok) {
      setLoginError("账号或密码不正确");
      return;
    }

    setLoginError("");
    setLoggedIn(true);
    setLoginName("");
    setLoginPass("");
  }

  async function logout() {
    await fetch("/api/auth/logout", { method: "POST" });
    setLoggedIn(false);
    setLoginVisible(false);
    setEditing(false);
    titleClicks.current = 0;
    setLoginName("");
    setLoginPass("");
    setLoginError("");
  }

  function resetDraft() {
    setDraftTitle("");
    setDraftCategory("随笔");
    setDraftTags("");
    setDraftCoverUrl("");
    setDraftContent("");
  }

  function openEditor() {
    resetDraft();
    setStatusText("");
    setEditing(true);
  }

  function closeEditor() {
    resetDraft();
    setEditing(false);
  }

  function insertMarkdown(prefix: string, suffix = "", placeholder = "文字") {
    const separator = draftContent.endsWith("\n") || !draftContent ? "" : "\n";
    setDraftContent(`${draftContent}${separator}${prefix}${placeholder}${suffix}`);
  }

  async function saveArticle(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    const title = draftTitle.trim();

    if (!title) {
      setStatusText("请先填写标题");
      return;
    }

    const input: ArticleInput = {
      title,
      category: draftCategory.trim() || "随笔",
      tags: splitTags(draftTags),
      coverUrl: draftCoverUrl.trim() || undefined,
      content: draftContent.trim(),
    };

    const response = await fetch("/api/articles", {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify(input),
    });

    if (response.status === 401) {
      setStatusText("登录已失效，请重新登录。");
      setLoggedIn(false);
      setLoginVisible(true);
      return;
    }

    if (!response.ok) {
      setStatusText("保存失败，请稍后再试。");
      return;
    }

    const payload = (await response.json()) as ArticlesPayload;
    setArticles(payload.articles);
    setStatusText("文章已保存到数据库。");
    closeEditor();
  }

  async function deleteArticle(id: string) {
    const response = await fetch(`/api/articles/${id}`, { method: "DELETE" });

    if (response.status === 401) {
      setLoggedIn(false);
      setLoginVisible(true);
      return;
    }

    if (!response.ok) {
      return;
    }

    const payload = (await response.json()) as ArticlesPayload;
    setArticles(payload.articles);
  }

  return (
    <main className="sub-page blog-page">
      <div className="paper-grain" />
      <div className="ink-wash ink-wash-one" />
      <div className="ink-wash ink-wash-two" />
      <div className="ink-wash ink-wash-three" />

      <Link className="back-link" href="/">
        归库
      </Link>

      <section className="blog-shell" aria-label="藏文入库">
        <header className="blog-header">
          <p className="sub-seal">文</p>
          <div>
            <button
              className="sub-label title-trigger"
              onClick={revealLogin}
              type="button"
              aria-label="藏文入库"
            >
              藏文入库
            </button>
            <p className="sub-note">收些念头、笔记与长久回响。</p>
          </div>
        </header>

        <div className="blog-toolbar">
          <label className="field">
            <span>搜索</span>
            <input
              value={query}
              onChange={(event) => setQuery(event.target.value)}
              placeholder="标题、标签、分类"
              type="search"
            />
          </label>

          <label className="field">
            <span>排序</span>
            <select value={sortMode} onChange={(event) => setSortMode(event.target.value as SortMode)}>
              <option value="latest">最新</option>
              <option value="likes">赞最多</option>
              <option value="dislikes">踩最多</option>
              <option value="score">净赞最高</option>
            </select>
          </label>

          <div className="category-strip" aria-label="分类">
            {categories.map((item) => (
              <button
                className={category === item ? "is-active" : ""}
                key={item}
                onClick={() => setCategory(item)}
                type="button"
              >
                {item}
              </button>
            ))}
          </div>
        </div>

        {loginVisible || loggedIn ? (
          <section className="login-panel" aria-label="登录">
            {loggedIn ? (
              <div className="logged-row">
                <span>已登录</span>
                <div className="admin-actions">
                  <button onClick={openEditor} type="button">
                    新增
                  </button>
                  <button onClick={logout} type="button">
                    退出
                  </button>
                </div>
              </div>
            ) : (
              <form className="login-form" onSubmit={login}>
                <label className="field">
                  <span>账号</span>
                  <input
                    autoComplete="username"
                    value={loginName}
                    onChange={(event) => setLoginName(event.target.value)}
                    type="text"
                  />
                </label>
                <label className="field">
                  <span>密码</span>
                  <input
                    autoComplete="current-password"
                    value={loginPass}
                    onChange={(event) => setLoginPass(event.target.value)}
                    type="password"
                  />
                </label>
                <button className="ink-button" type="submit">
                  登录
                </button>
                {loginError ? <p className="login-error">{loginError}</p> : null}
              </form>
            )}
          </section>
        ) : null}

        {statusText ? <p className="status-text">{statusText}</p> : null}

        {loggedIn && editing ? (
          <section className="editor-page" aria-label="新增文章编辑页面">
            <div className="editor-head">
              <div>
                <p className="editor-kicker">新增文章</p>
                <p className="sub-note">使用 Markdown 编写，可用工具栏快速加入富文本格式。</p>
              </div>
              <button className="ink-button" onClick={closeEditor} type="button">
                返回列表
              </button>
            </div>

            <form className="editor-form" onSubmit={saveArticle}>
              <label className="field">
                <span>标题</span>
                <input
                  value={draftTitle}
                  onChange={(event) => setDraftTitle(event.target.value)}
                  type="text"
                />
              </label>
              <label className="field">
                <span>分类</span>
                <input
                  value={draftCategory}
                  onChange={(event) => setDraftCategory(event.target.value)}
                  type="text"
                />
              </label>
              <label className="field">
                <span>标签</span>
                <input
                  value={draftTags}
                  onChange={(event) => setDraftTags(event.target.value)}
                  placeholder="用空格或逗号分隔"
                  type="text"
                />
              </label>
              <label className="field editor-cover-field">
                <span>封面图 URL</span>
                <input
                  value={draftCoverUrl}
                  onChange={(event) => setDraftCoverUrl(event.target.value)}
                  placeholder="https://example.com/cover.jpg"
                  type="url"
                />
              </label>

              <div className="rich-toolbar" aria-label="富文本工具">
                <button onClick={() => insertMarkdown("# ", "", "一级标题")} type="button">
                  H1
                </button>
                <button onClick={() => insertMarkdown("## ", "", "二级标题")} type="button">
                  H2
                </button>
                <button onClick={() => insertMarkdown("**", "**", "加粗文字")} type="button">
                  B
                </button>
                <button onClick={() => insertMarkdown("*", "*", "斜体文字")} type="button">
                  I
                </button>
                <button onClick={() => insertMarkdown("> ", "", "引用内容")} type="button">
                  引用
                </button>
                <button onClick={() => insertMarkdown("- ", "", "列表项")} type="button">
                  列表
                </button>
                <button onClick={() => insertMarkdown("[", "](https://example.com)", "链接文字")} type="button">
                  链接
                </button>
                <button onClick={() => insertMarkdown("![", "](https://example.com/image.jpg)", "图片说明")} type="button">
                  图片
                </button>
              </div>

              <label className="field editor-content">
                <span>文章内容（Markdown）</span>
                <textarea
                  value={draftContent}
                  onChange={(event) => setDraftContent(event.target.value)}
                  placeholder={"## 小标题\n\n在这里写正文，可使用 **加粗**、*斜体*、列表、链接和图片。"}
                />
              </label>

              <div className="editor-preview">
                <p className="editor-kicker">预览</p>
                <div className="markdown-preview">
                  {draftContent || "Markdown 内容会在这里预览。"}
                </div>
              </div>

              <button className="ink-button editor-submit" type="submit">
                保存文章
              </button>
            </form>
          </section>
        ) : (
          <section className="article-grid" aria-label="文章">
            {filteredArticles.map((article) => (
              <article className="article-card" key={article.id}>
                <Link className="article-link" href={`/blog/${article.id}`}>
                  {article.coverUrl ? (
                    <img className="article-cover image-cover" src={article.coverUrl} alt="" />
                  ) : (
                    <div className={`article-cover cover-${article.cover}`} role="img" aria-label="封面图" />
                  )}
                  <div className="article-body">
                    <p className="article-category">{article.category}</p>
                    <h2>{article.title}</h2>
                    <div className="tag-row">
                      {article.tags.map((tag) => (
                        <span key={tag}>{tag}</span>
                      ))}
                    </div>
                    <p className="vote-line">
                      赞 {article.likes} · 踩 {article.dislikes}
                    </p>
                  </div>
                </Link>
                {loggedIn ? (
                  <button className="delete-button" onClick={() => deleteArticle(article.id)} type="button">
                    删除
                  </button>
                ) : null}
              </article>
            ))}
          </section>
        )}
      </section>
    </main>
  );
}
