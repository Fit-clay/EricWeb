import type { Metadata } from "next";
import Link from "next/link";
import { listHtmlPages } from "../../Service/html/pages";

export const metadata: Metadata = {
  title: "观景启窗 | 貔貅",
};

export const runtime = "nodejs";
export const dynamic = "force-dynamic";

export default async function PreviewPage() {
  const pages = await listHtmlPages();

  return (
    <main className="sub-page">
      <div className="paper-grain" />
      <div className="ink-wash ink-wash-one" />
      <div className="ink-wash ink-wash-two" />
      <div className="ink-wash ink-wash-three" />

      <Link className="back-link" href="/">
        归库
      </Link>

      <section className="sub-stage" aria-label="观景启窗">
        <p className="sub-seal">景</p>
        <p className="sub-label">观景启窗</p>
        <p className="sub-note">
          将 HTML 文件及其资源放入页面目录，刷新这里即可打开，无需重新构建。
        </p>

        {pages.length ? (
          <ul className="sub-list html-page-list">
            {pages.map((page) => (
              <li key={page.relativePath}>
                <a className="html-page-link" href={page.href}>
                  <span>{page.title}</span>
                  <small>{page.relativePath} · 启窗</small>
                </a>
              </li>
            ))}
          </ul>
        ) : (
          <p className="html-empty">尚无 HTML 页面，请先向页面目录加入 .html 或 .htm 文件。</p>
        )}
      </section>
    </main>
  );
}
