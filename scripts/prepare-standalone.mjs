import { access, cp, mkdir } from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";

const projectRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const standaloneRoot = path.join(projectRoot, ".next", "standalone");

async function exists(target) {
  try {
    await access(target);
    return true;
  } catch {
    return false;
  }
}

if (!(await exists(path.join(standaloneRoot, "server.js")))) {
  throw new Error("未找到 standalone 构建，请先运行 next build");
}

const publicSource = path.join(projectRoot, "public");
const staticSource = path.join(projectRoot, ".next", "static");
const htmlPagesSource = path.join(projectRoot, "html-pages");

if (await exists(publicSource)) {
  await cp(publicSource, path.join(standaloneRoot, "public"), {
    recursive: true,
    force: true,
  });
}

await mkdir(path.join(standaloneRoot, ".next"), { recursive: true });
await cp(staticSource, path.join(standaloneRoot, ".next", "static"), {
  recursive: true,
  force: true,
});

if (await exists(htmlPagesSource)) {
  await cp(htmlPagesSource, path.join(standaloneRoot, "html-pages"), {
    recursive: true,
    force: true,
  });
}

console.log("standalone 生产目录已准备完成：.next/standalone");
