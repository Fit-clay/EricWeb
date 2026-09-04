# Service 服务端说明

`Service/` 是貔貅小库的 Node.js 服务端业务层。`app/api` 只负责 HTTP 请求，文章、认证和 HTML 页面逻辑由这里提供。

## 数据存储

- 数据库：服务器本地 SQLite 文件
- 驱动：`better-sqlite3`
- ORM：Drizzle ORM
- 默认路径：`data/pixiu.sqlite`
- 生产路径：通过 `DATABASE_PATH` 指定持久目录

数据库首次访问时自动创建 `articles` 表。SQLite 使用 WAL 模式和 5 秒 busy timeout，适合单台 VPS 上的个人站点。

## HTML 页面

`Service/html/pages.ts` 扫描 `HTML_PAGES_PATH`，本地默认目录为 `html-pages/`。`/preview` 自动展示其中的 `.html`、`.htm` 页面，`/html/*` 负责安全解析路径并返回页面及相对资源。

## 管理员认证

生产环境必须提供：

- `ADMIN_USER`
- `ADMIN_PASSWORD`
- `ADMIN_SESSION_SECRET`

登录状态通过带 `HttpOnly`、`SameSite=Lax`、生产环境 `Secure` 属性的 Cookie 保存。
