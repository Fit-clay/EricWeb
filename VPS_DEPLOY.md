# Linux/VPS 部署指南

当前项目使用标准 Next.js Node Runtime、SQLite 文件数据库和 standalone 构建。发布包自带 Node.js 24，适合单台 Linux/VPS，建议让 Nginx 位于 Node 服务之前。

所有依赖安装、编译和测试在本机 Docker Linux 环境完成，服务器只负责运行。Windows 双击 deploy-ui.cmd；详细参数见 [SCRIPT_GUIDE.md](./SCRIPT_GUIDE.md)。

## 1. 准备服务器

推荐 Ubuntu 24.04+/Debian 12+，使用 root 或 sudo 用户。预先安装运行和解包工具：

```bash
sudo apt-get update
sudo apt-get install -y python3 curl tar util-linux libstdc++6 ca-certificates
```

服务器不需要 Docker、npm、make 或 g++。成品包含 Node.js 24、standalone 网站及原生 SQLite。脚本先检查架构和运行时兼容性，验证失败停止，不在服务器重新编译。

本机安装并启动 Docker Desktop（Linux 容器模式），填写 .deploy.env 后通过发布窗口更新，不要直接上传 Windows 构建。

## 2. 设置生产环境

创建 `/etc/pixiu-library.env`：

```dotenv
HOSTNAME=127.0.0.1
PORT=3000
DATABASE_PATH=/var/lib/pixiu-library/pixiu.sqlite
HTML_PAGES_PATH=/var/lib/pixiu-library/html
ADMIN_USER=Eric
ADMIN_PASSWORD=替换为高强度密码
ADMIN_SESSION_SECRET=替换为至少32字节的随机字符串
```

保护配置文件：

```bash
sudo chown root:pixiu /etc/pixiu-library.env
sudo chmod 640 /etc/pixiu-library.env
```

发布不自动导入示例数据，数据库持续保存在 DATABASE_PATH；可通过管理员入口新增文章。

## 3. 使用 systemd 运行

复制 `deploy/systemd/pixiu-library.service.example` 到 `/etc/systemd/system/pixiu-library.service`，然后执行：

```bash
sudo systemctl daemon-reload
sudo systemctl enable --now pixiu-library
sudo systemctl status pixiu-library
```

查看运行日志：

```bash
sudo journalctl -u pixiu-library -f
```

## 4. 配置 Nginx 和 HTTPS

复制 `deploy/nginx/pixiu-library.conf.example` 到 Nginx 站点目录，将 `example.com` 改成真实域名，启用配置后重载 Nginx：

```bash
sudo nginx -t
sudo systemctl reload nginx
```

随后使用 Certbot 或服务器现有证书方案启用 HTTPS。生产登录 Cookie 带有 `Secure` 属性，因此生产环境必须通过 HTTPS 访问。

## 5. 后续加入 HTML 页面

将可信的 `.html`、`.htm` 文件及其 CSS、JavaScript、图片等资源复制到：

```text
/var/lib/pixiu-library/html
```

支持子目录和相对资源，例如：

```text
/var/lib/pixiu-library/html/product/index.html
/var/lib/pixiu-library/html/product/style.css
/var/lib/pixiu-library/html/product/images/cover.jpg
```

页面地址为 `/html/product/index.html`，并会自动出现在 `/preview`。加入或替换文件不需要重新构建，也不需要重启服务。

HTML 文件与主站同源，只应放入自己信任的页面；不要允许不受信任的用户直接上传任意 HTML 或 JavaScript。

项目内置的两个 travel 训练页面可通过以下脚本从源目录刷新并上传服务器：

```bash
./scripts/update-travel-pages.sh
```

默认源目录为 `/Users/eric/Desktop/AI/travel`，服务器目标目录为 `/var/lib/pixiu-library/html/travel`。只更新仓库副本时使用 `--local-only`，只上传仓库内现有副本时使用 `--deploy-only`。更新完成后刷新 `/preview` 即可，无需重新构建或重启服务。

## 6. 更新和备份

### 一键发布（推荐）

Windows 双击 deploy-ui.cmd，或在开发电脑执行：

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\deploy-vps.ps1 -Mode Full
powershell -ExecutionPolicy Bypass -File .\scripts\deploy-vps.ps1 -Mode Html
```

Full 在本机完成 Linux 构建和 512MB 无 Swap 容器测试后上传，服务器仅验证、切换并运行。已有环境配置保留，健康检查失败恢复旧版本和启动配置。Html 模式不重启网站。

低内存 drop-in 设置 192MB Node 堆上限、256MB MemoryHigh、320MB MemoryMax。512MB 主机仍需给系统和其他进程预留内存，不能保证任意负载下不 OOM。

HTML 使用 html-releases 快照和 html 链接切换，保留服务器额外页面与旧版本；备份需包含链接目标，旧版本按需清理。

macOS/Linux 使用 ./scripts/deploy-vps.sh，同样依赖本机 Docker；不能在 512MB 网站服务器上执行本机构建入口。

需要备份以下内容：

```text
/var/lib/pixiu-library/pixiu.sqlite
/var/lib/pixiu-library/html
/var/lib/pixiu-library/html-releases
/etc/pixiu-library.env
```

复制 SQLite 数据库前建议短暂停止服务，或使用 SQLite 的在线备份命令，避免只复制数据库主文件而漏掉 WAL 数据。
