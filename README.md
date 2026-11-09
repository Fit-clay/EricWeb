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

安装部署、数据更新和内部辅助脚本的完整分类见 [SCRIPT_GUIDE.md](./SCRIPT_GUIDE.md)。名称包含 `remote` 的脚本由入口脚本自动调用，不应单独运行。

- `npm run dev`：启动开发服务。
- `npm run build`：生成并整理 standalone 生产构建。
- `npm run start`：使用完整项目目录启动生产服务。
- `npm run start:standalone`：运行 `.next/standalone/server.js`。
- `npm test`：构建并验证首页、HTML 页面和 SQLite API。
- `npm run db:import`：将 `data/articles.json` 导入 SQLite。
- Windows 发布界面：双击根目录 `deploy-ui.cmd`，提供全量更新和仅更新 HTML 两个入口。
- Windows 命令行：`powershell -ExecutionPolicy Bypass -File .\scripts\deploy-vps.ps1 -Mode Full`；所有依赖安装、Linux 构建和测试都在本机 Docker 中完成，服务器只运行成品。
- 仅更新页面：`powershell -ExecutionPolicy Bypass -File .\scripts\deploy-vps.ps1 -Mode Html`，上传整个 `html-pages/`，无需 Docker、无需编译或重启。
- macOS/Linux：`./scripts/deploy-vps.sh`，同样使用本机 Docker 构建。详见 [SCRIPT_GUIDE.md](./SCRIPT_GUIDE.md)。

## HTML 页面

本地开发时，将 HTML 页面放入 `html-pages/`。服务器上通过 `HTML_PAGES_PATH` 指定持久目录。页面及其相对资源由 `/html/*` 提供，并自动出现在 `/preview`。

从 `travel` 源目录更新两个训练页面并同步到 VPS：

```bash
./scripts/update-travel-pages.sh
```

只更新仓库副本可添加 `--local-only`，只上传当前仓库副本可添加 `--deploy-only`。页面存放在 `html-pages/travel/`，服务器端对应 `/var/lib/pixiu-library/html/travel/`，更新后无需重新构建或重启服务。

## 生产配置

复制 `.env.example` 中的配置，并务必替换管理员密码和会话密钥。完整步骤见 [VPS_DEPLOY.md](./VPS_DEPLOY.md)。

如需通过 GitHub 同步源码并部署到 Ubuntu VPS，请参阅 [GIT_DEPLOY.md](./GIT_DEPLOY.md)。

复制 `.deploy.env.example` 为 `.deploy.env`，填写 SSH 信息。全量发布前需在本机安装并启动 Docker Desktop（Linux 容器）；Linux Node.js 运行时随成品上传。服务器需要预先提供 Python 3、curl、tar、flock 和 systemd，不执行 npm 或编译器。首次运行会交互创建生产管理员配置；`.deploy.env` 已被 Git 忽略。

512MB 运行配置使用 192MB Node 堆上限、256MB 内存软限制和 320MB 服务硬限制；本地全量发布在上传前执行 512MB 无 Swap 容器内的运行测试。这是低访问量个人站点的资源配置，不能保证任意负载或已有其他高占用服务时都稳定。HTML 大文件使用流式响应，降低并发请求的内存峰值。
