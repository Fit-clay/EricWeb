# Git 与成品发布

Git 用于同步源码、配置模板、数据库结构、测试和 HTML 源文件。实际配置、SSH 私钥、SQLite、依赖和构建产物不提交。

仓库为 git@github.com:Fit-clay/EricWeb.git，主分支 main。在开发电脑拉取、修改、提交和推送后，双击 deploy-ui.cmd 全量更新，或执行：

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\deploy-vps.ps1 -Mode Full
```

所有依赖安装、Linux 构建和测试在开发电脑完成，512MB 容器运行测试通过后才上传成品。服务器不执行 npm；旧的服务器 Git 拉取源码后构建流程已停用，远程发布入口只接受带平台清单的 Linux 成品。

只更新页面可使用窗口的“仅更新 HTML”，或 deploy-vps.ps1 -Mode Html。它将本地整个 html-pages/ 合并到新快照，不重启网站，保留服务器额外文件，无需 Docker。

生产数据位于 /var/lib/pixiu-library，成品位于 /opt/pixiu-library/releases，current 指向运行版本。HTML 当前链接与 html-releases 目标一起备份。数据库和管理员配置不被覆盖。

脚本发布当前工作目录，包括未提交修改，建议发布前提交 Git。健康检查失败会恢复旧版本及启动配置。

前提和参数见 [SCRIPT_GUIDE.md](./SCRIPT_GUIDE.md)，Nginx 与运行设置见 [VPS_DEPLOY.md](./VPS_DEPLOY.md)。
