# 发布与更新指南

## Windows 发布窗口

双击根目录 `deploy-ui.cmd`。填写服务器地址、SSH 用户和端口，选择服务器架构，可选 SSH 私钥。密码和详细日志在独立终端处理，不保存到窗口配置。执行期间按钮禁用，失败后终端保留错误，按回车返回窗口。

- **全量更新**：本机 Linux 容器安装依赖、编译、测试；上传网站成品、Linux Node.js 运行时和全部 HTML。服务器只验证、切换和运行。
- **仅更新 HTML**：上传整个 `html-pages/` 和资源，不需要 Docker、不编译、不重启网站。

连接信息保存于 `.deploy.env`，首次使用复制 `.deploy.env.example`。实际配置和私钥不要提交 Git。

## 环境要求

Windows 命令行支持 PowerShell 5.1/7，窗口使用 Windows PowerShell。需要 OpenSSH 的 ssh.exe、scp.exe。

全量发布需在**本机安装并启动 Docker Desktop，使用 Linux 容器模式**，采用 Node.js 24 / Debian Bookworm。服务器不需要 Docker、npm、make 或 g++，不能直接把 Windows 原生依赖上传到 Linux。

服务器预先具备 Python 3、curl、tar、sha256sum、flock、systemd，SSH 用户为 root 或具有 sudo 权限。推荐 Ubuntu 24.04+/Debian 12+；旧系统须满足成品运行时和 SQLite 动态库要求，不兼容时停止，不回退到服务器编译。

## 命令行

```powershell
cd C:\AI\Website
powershell -ExecutionPolicy Bypass -File .\scripts\deploy-vps.ps1 -Mode Full
powershell -ExecutionPolicy Bypass -File .\scripts\deploy-vps.ps1 -Mode Html
# 仅本地生成成品，不上传；Full 仍需 Docker
powershell -ExecutionPolicy Bypass -File .\scripts\deploy-vps.ps1 -Mode Full -PackageOnly
powershell -ExecutionPolicy Bypass -File .\scripts\deploy-vps.ps1 -Mode Html -PackageOnly
# 只读查看服务器资源
powershell -ExecutionPolicy Bypass -File .\scripts\deploy-vps.ps1 -DiagnoseOnly
```

其他参数：`-ConfigFile` 指定配置，`-IdentityFile` 指定私钥，`-Architecture arm64` 用于 ARM（默认 amd64），`-OutputPath` 指定成品。项目内部只能写入 outputs/。默认成品为 outputs/release.tar.gz 和 outputs/html-pages.zip。

macOS/Linux 入口 `./scripts/deploy-vps.sh` 同样使用本机 Docker，另需本机 rsync；ARM 可设置 DEPLOY_ARCH=arm64。不要在运行网站的 512MB 服务器上执行本机构建入口。

## 发布流程

1. 复制源码到本机临时目录，排除实际配置、密钥、数据库、依赖和缓存；副本 Shell 文件转为 LF。
2. 本机 Linux 容器安装依赖、生产构建和测试；打包 standalone、Node 运行时、HTML、平台清单，移除重复页面及其他平台 SQLite 二进制。
3. 在本机 **512MB 内存、无 Swap、1 CPU** 的独立容器内测试最终成品的首页、HTML、SQLite 接口；失败不上传。
4. 上传成品与 SHA-256 文件。服务器核验架构、运行时、SQLite，配置或沿用管理员环境，不执行 npm 或编译器。
5. 应用独立 systemd drop-in，切换成品、重启并健康检查；失败恢复旧版本与旧启动配置。通过后发布 HTML；HTML 失败也回退网站版本。

Node 老生代堆上限为 192MB，systemd MemoryHigh=256M、MemoryMax=320M。它不保证任意负载、其他程序大量占用或宿主机限制下 512MB 都稳定。HTML 大文件使用流式响应，降低峰值。

## HTML 与数据

Full 和 Html 均合并本地页面到新快照，**保留服务器额外页面**；本地删除不自动删除线上文件。数据库和管理员配置不会覆盖。HTML_PAGES_PATH 应对应 VPS_DATA_DIR/html。

首次更新把 html 目录迁移为指向 html-releases/<版本>/ 的链接，后续切换快照，失败保留当前页面。旧快照占用磁盘，备份时包含链接目标，按需清理确认不再使用的旧版本。

旧 update-travel-pages.sh --local-only 可刷新仓库副本，--deploy-only 上传现有 travel 副本；服务器也改为快照合并，不再删除额外页面。新窗口可直接更新所有分类。

install-ubuntu-system-node-* 是保留的独立环境工具，发布不再调用。npm run db:import 是本地数据导入工具，不随发布自动执行。发布包含未提交的工作目录改动，建议发布前提交 Git。

## 离线验证

```powershell
powershell -ExecutionPolicy Bypass -File .\tests\windows-deploy.test.ps1
python tests/html-publish.test.py
npm test
```

Python 快照切换测试需要 Linux 文件系统，在 Windows 会明确跳过；全量发布仍须通过本机 Docker Linux 测试。脚本自测不连接服务器。
