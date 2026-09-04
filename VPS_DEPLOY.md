# Linux/VPS 部署指南

当前项目使用标准 Next.js Node Runtime、SQLite 文件数据库和 standalone 构建，适合单台 Linux/VPS 部署。建议使用 Node.js 22 或 24，并让 Nginx 位于 Node 服务之前。

## 1. 准备服务器目录

```bash
sudo useradd --system --home /opt/pixiu-library --shell /usr/sbin/nologin pixiu
sudo mkdir -p /opt/pixiu-library/current /var/lib/pixiu-library/html
sudo chown -R pixiu:pixiu /opt/pixiu-library /var/lib/pixiu-library
```

将项目代码上传到 `/opt/pixiu-library/current`。`better-sqlite3` 包含平台相关二进制文件，因此最稳妥的方式是在目标 Linux 服务器上安装和构建：

```bash
cd /opt/pixiu-library/current
npm ci
npm run build
```

构建完成后，`.next/standalone` 已包含服务器运行所需文件、静态资源和初始 HTML 示例。

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

如需导入仓库内的示例文章，可在启动服务前执行：

```bash
sudo -u pixiu env DATABASE_PATH=/var/lib/pixiu-library/pixiu.sqlite npm run db:import
```

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

## 6. 更新和备份

### 一键发布（推荐）

首次初始化并安装 systemd 服务后，在本机项目目录执行：

```bash
cp .deploy.env.example .deploy.env
```

编辑 `.deploy.env`，填写服务器地址和 SSH 用户。若首次部署时修改过应用目录、数据目录或环境文件路径，也应同步修改对应配置。然后执行：

```bash
./scripts/deploy-vps.sh
```

脚本会上传当前源码，在服务器的新版本目录中执行 `npm ci` 和 `npm test`，测试通过后原子切换 `current` 软链接并重启服务。健康检查失败时会自动恢复旧版本。服务器密码和会话密钥仍保存在 `/etc/pixiu-library.env`，不会上传到源码目录。

### 手动更新

每次更新代码后重新执行：

```bash
npm ci
npm run test
sudo systemctl restart pixiu-library
```

需要备份以下内容：

```text
/var/lib/pixiu-library/pixiu.sqlite
/var/lib/pixiu-library/html
/etc/pixiu-library.env
```

复制 SQLite 数据库前建议短暂停止服务，或使用 SQLite 的在线备份命令，避免只复制数据库主文件而漏掉 WAL 数据。
