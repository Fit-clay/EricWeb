import { mkdir, readFile } from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";
import Database from "better-sqlite3";

const projectRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const sourcePath = path.resolve(process.argv[2] || path.join(projectRoot, "data", "articles.json"));
const databasePath = path.resolve(
  process.env.DATABASE_PATH || path.join(projectRoot, "data", "pixiu.sqlite"),
);

await mkdir(path.dirname(databasePath), { recursive: true });
const articles = JSON.parse(await readFile(sourcePath, "utf8"));

if (!Array.isArray(articles)) {
  throw new Error("文章导入文件必须是 JSON 数组");
}

const database = new Database(databasePath);
database.pragma("journal_mode = WAL");
database.exec(`
  CREATE TABLE IF NOT EXISTS articles (
    id text PRIMARY KEY NOT NULL,
    title text NOT NULL,
    category text DEFAULT '随笔' NOT NULL,
    tags text DEFAULT '[]' NOT NULL,
    cover text DEFAULT 'mountain' NOT NULL,
    cover_url text,
    content text DEFAULT '' NOT NULL,
    likes integer DEFAULT 0 NOT NULL,
    dislikes integer DEFAULT 0 NOT NULL,
    created_at text DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at text DEFAULT CURRENT_TIMESTAMP NOT NULL
  );
`);

const upsert = database.prepare(`
  INSERT INTO articles (
    id, title, category, tags, cover, cover_url, content,
    likes, dislikes, created_at, updated_at
  ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
  ON CONFLICT(id) DO UPDATE SET
    title = excluded.title,
    category = excluded.category,
    tags = excluded.tags,
    cover = excluded.cover,
    cover_url = excluded.cover_url,
    content = excluded.content,
    likes = excluded.likes,
    dislikes = excluded.dislikes,
    updated_at = excluded.updated_at
`);

const importArticles = database.transaction((rows) => {
  for (const article of rows) {
    const now = new Date().toISOString();
    upsert.run(
      String(article.id),
      String(article.title),
      String(article.category || "随笔"),
      JSON.stringify(Array.isArray(article.tags) ? article.tags : []),
      String(article.cover || "mountain"),
      article.coverUrl ? String(article.coverUrl) : null,
      String(article.content || ""),
      Number(article.likes || 0),
      Number(article.dislikes || 0),
      String(article.createdAt || now),
      String(article.updatedAt || now),
    );
  }
});

try {
  importArticles(articles);
  console.log(`已向 ${databasePath} 导入 ${articles.length} 篇文章`);
} finally {
  database.close();
}
