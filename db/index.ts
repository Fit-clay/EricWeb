import { mkdirSync } from "node:fs";
import path from "node:path";
import Database from "better-sqlite3";
import { drizzle } from "drizzle-orm/better-sqlite3";
import * as schema from "./schema";

type DatabaseGlobals = typeof globalThis & {
  pixiuSqlite?: Database.Database;
};

const databaseGlobals = globalThis as DatabaseGlobals;

function resolveDatabasePath() {
  const configuredPath = process.env.DATABASE_PATH?.trim();
  return path.resolve(configuredPath || path.join(process.cwd(), "data", "pixiu.sqlite"));
}

export function getSqliteConnection() {
  if (!databaseGlobals.pixiuSqlite) {
    const databasePath = resolveDatabasePath();
    mkdirSync(path.dirname(databasePath), { recursive: true });

    const sqlite = new Database(databasePath, {
      timeout: 5_000,
    });
    sqlite.pragma("journal_mode = WAL");
    sqlite.pragma("foreign_keys = ON");
    sqlite.pragma("busy_timeout = 5000");
    databaseGlobals.pixiuSqlite = sqlite;
  }

  return databaseGlobals.pixiuSqlite;
}

export function getDb() {
  return drizzle(getSqliteConnection(), { schema });
}
