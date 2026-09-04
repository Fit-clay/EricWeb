# 貔貅小库

一个水墨风个人文章与页面收藏站。项目使用标准 Next.js App Router，可直接部署到普通 Linux/VPS。

## 运行环境

- Node.js `>=22.13.0`
- SQLite 文件数据库（`better-sqlite3` + Drizzle ORM）
- 生产环境建议使用 Nginx + systemd + HTTPS

## 本地运行

```bash
npm install
npm run dev
```

默认访问地址为 `http://localhost:3000`，本地数据库默认写入 `data/pixiu.sqlite`。

## 常用命令

- `npm run dev`：启动开发服务。
- `npm run build`：生成并整理 standalone 生产构建。
- `npm run start`：使用完整项目目录启动生产服务。
- `npm run start:standalone`：运行 `.next/standalone/server.js`。
- `npm test`：构建并验证首页、HTML 页面和 SQLite API。
- `npm run db:import`：将 `data/articles.json` 导入 SQLite。
- `./scripts/deploy-vps.sh`：上传、构建、测试并切换服务器版本。

## HTML 页面

本地开发时，将 HTML 页面放入 `html-pages/`。服务器上通过 `HTML_PAGES_PATH` 指定持久目录。页面及其相对资源由 `/html/*` 提供，并自动出现在 `/preview`。

## 生产配置

复制 `.env.example` 中的配置，并务必替换管理员密码和会话密钥。完整步骤见 [VPS_DEPLOY.md](./VPS_DEPLOY.md)。

首次完成服务器初始化后，可复制 `.deploy.env.example` 为 `.deploy.env`，填写 SSH 信息，然后运行一键发布脚本。`.deploy.env` 已被 Git 忽略。
