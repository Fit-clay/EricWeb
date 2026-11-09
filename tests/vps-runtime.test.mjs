import assert from "node:assert/strict";
import { createServer } from "node:net";
import { cp, mkdtemp, rm } from "node:fs/promises";
import { spawn } from "node:child_process";
import os from "node:os";
import path from "node:path";
import test from "node:test";

const projectRoot = path.resolve(import.meta.dirname, "..");
const standaloneRoot = process.env.STANDALONE_ROOT || path.join(projectRoot, ".next", "standalone");
const runtimeNode = process.env.STANDALONE_NODE || process.execPath;

async function getFreePort() {
  const server = createServer();
  await new Promise((resolve, reject) => {
    server.once("error", reject);
    server.listen(0, "127.0.0.1", resolve);
  });
  const address = server.address();
  const port = typeof address === "object" && address ? address.port : 0;
  await new Promise((resolve) => server.close(resolve));
  return port;
}

async function waitForServer(url, child, logs) {
  const deadline = Date.now() + 30_000;
  while (Date.now() < deadline) {
    if (child.exitCode !== null) {
      throw new Error(`standalone 服务提前退出\n${logs.join("")}`);
    }
    try {
      const response = await fetch(url);
      if (response.ok) {
        return;
      }
    } catch {
      // 服务仍在启动。
    }
    await new Promise((resolve) => setTimeout(resolve, 200));
  }
  throw new Error(`standalone 服务启动超时\n${logs.join("")}`);
}

test("standalone VPS 构建可提供页面、HTML 文件和 SQLite API", async () => {
  const temporaryRoot = await mkdtemp(path.join(os.tmpdir(), "pixiu-vps-test-"));
  const htmlRoot = path.join(temporaryRoot, "html");
  const databasePath = path.join(temporaryRoot, "pixiu.sqlite");
  await cp(process.env.HTML_SOURCE_ROOT || path.join(projectRoot, "html-pages"), htmlRoot, { recursive: true });

  const port = await getFreePort();
  const baseUrl = `http://127.0.0.1:${port}`;
  const logs = [];
  const child = spawn(runtimeNode, [path.join(standaloneRoot, "server.js")], {
    cwd: projectRoot,
    env: {
      ...process.env,
      NODE_ENV: "production",
      HOSTNAME: "127.0.0.1",
      PORT: String(port),
      DATABASE_PATH: databasePath,
      HTML_PAGES_PATH: htmlRoot,
      ADMIN_USER: "test-admin",
      ADMIN_PASSWORD: "test-password",
      ADMIN_SESSION_SECRET: "test-session-secret-with-at-least-32-characters",
    },
    stdio: ["ignore", "pipe", "pipe"],
  });
  child.stdout.on("data", (chunk) => logs.push(chunk.toString()));
  child.stderr.on("data", (chunk) => logs.push(chunk.toString()));

  try {
    await waitForServer(`${baseUrl}/`, child, logs);

    const home = await fetch(`${baseUrl}/`);
    assert.equal(home.status, 200);
    assert.match(await home.text(), /貔貅/);

    const preview = await fetch(`${baseUrl}/preview`);
    assert.equal(preview.status, 200);
    assert.match(await preview.text(), /示例 HTML 页面/);

    const htmlPage = await fetch(`${baseUrl}/html/example.html`);
    assert.equal(htmlPage.status, 200);
    assert.match(htmlPage.headers.get("content-type") || "", /^text\/html/);
    assert.match(await htmlPage.text(), /独立 HTML 文件/);

    const articles = await fetch(`${baseUrl}/api/articles`);
    assert.equal(articles.status, 200);
    assert.deepEqual(await articles.json(), { articles: [] });
  } finally {
    child.kill("SIGTERM");
    await new Promise((resolve) => child.once("exit", resolve));
    await rm(temporaryRoot, { recursive: true, force: true });
  }
});
