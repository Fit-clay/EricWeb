import { ServiceError } from "../lib/errors";

const sessionCookieName = "pixiu_admin_session";
const sessionMaxAgeSeconds = 60 * 60 * 24 * 7;
const defaultAdminName = "Eric";
const defaultAdminPassword = "Pw-admin";
const defaultSessionSecret = "pixiu-library-dev-session-secret";

function runtimeValue(name: "ADMIN_USER" | "ADMIN_PASSWORD" | "ADMIN_SESSION_SECRET", fallback: string) {
  const value = process.env[name]?.trim();
  if (value) {
    return value;
  }

  if (process.env.NODE_ENV === "production") {
    throw new Error(`生产环境缺少 ${name} 配置`);
  }

  return fallback;
}

function adminName() {
  return runtimeValue("ADMIN_USER", defaultAdminName);
}

function adminPassword() {
  return runtimeValue("ADMIN_PASSWORD", defaultAdminPassword);
}

function sessionSecret() {
  return runtimeValue("ADMIN_SESSION_SECRET", defaultSessionSecret);
}

function parseCookies(header: string | null) {
  const cookies = new Map<string, string>();

  if (!header) {
    return cookies;
  }

  for (const part of header.split(";")) {
    const [rawName, ...rawValue] = part.trim().split("=");
    if (!rawName) {
      continue;
    }
    cookies.set(rawName, rawValue.join("="));
  }

  return cookies;
}

async function hmac(value: string) {
  const key = await crypto.subtle.importKey(
    "raw",
    new TextEncoder().encode(sessionSecret()),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"]
  );
  const signature = await crypto.subtle.sign("HMAC", key, new TextEncoder().encode(value));
  return Array.from(new Uint8Array(signature))
    .map((byte) => byte.toString(16).padStart(2, "0"))
    .join("");
}

function equalSignature(left: string, right: string) {
  if (left.length !== right.length) {
    return false;
  }

  let mismatch = 0;
  for (let index = 0; index < left.length; index += 1) {
    mismatch |= left.charCodeAt(index) ^ right.charCodeAt(index);
  }
  return mismatch === 0;
}

async function createSessionToken(user: string) {
  const expiresAt = Date.now() + sessionMaxAgeSeconds * 1000;
  const body = `${encodeURIComponent(user)}.${expiresAt}`;
  const signature = await hmac(body);
  return `${body}.${signature}`;
}

async function verifySessionToken(token?: string) {
  if (!token) {
    return false;
  }

  const parts = token.split(".");
  if (parts.length !== 3) {
    return false;
  }

  const [encodedUser, expiresAt, signature] = parts;
  const expiry = Number(expiresAt);
  if (!Number.isFinite(expiry) || expiry < Date.now()) {
    return false;
  }

  const expected = await hmac(`${encodedUser}.${expiresAt}`);
  if (!equalSignature(signature, expected)) {
    return false;
  }

  return decodeURIComponent(encodedUser) === adminName();
}

export async function loginAdmin(name: string, password: string) {
  if (name.trim() !== adminName() || password !== adminPassword()) {
    throw new ServiceError("账号或密码不正确", 401);
  }

  return createSessionToken(adminName());
}

export function createLoginCookie(token: string) {
  const secure = process.env.NODE_ENV === "production" ? "; Secure" : "";
  return `${sessionCookieName}=${token}; Path=/; Max-Age=${sessionMaxAgeSeconds}; HttpOnly; SameSite=Lax${secure}`;
}

export function createLogoutCookie() {
  const secure = process.env.NODE_ENV === "production" ? "; Secure" : "";
  return `${sessionCookieName}=; Path=/; Max-Age=0; HttpOnly; SameSite=Lax${secure}`;
}

export async function isAdminRequest(request: Request) {
  const cookies = parseCookies(request.headers.get("cookie"));
  return verifySessionToken(cookies.get(sessionCookieName));
}

export async function requireAdmin(request: Request) {
  if (!(await isAdminRequest(request))) {
    throw new ServiceError("请先登录管理员账号", 401);
  }
}
