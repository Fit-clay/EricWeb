import { getDb, getSqliteConnection } from "../../db";

let schemaReady = false;

export async function ensureServiceSchema() {
  if (schemaReady) {
    return;
  }

  getSqliteConnection().exec(`
    CREATE TABLE IF NOT EXISTS articles (
      id text PRIMARY KEY NOT NULL,
      title text NOT NULL,
      category text DEFAULT '随笔' NOT NULL,
      tags text DEFAULT '[]' NOT NULL,
      cover text DEFAULT 'mountain' NOT NULL,
      cover_url text,
      content text DEFAULT '' NOT NULL,
      likes integer DEFAULT 0 NOT NULL,
      dislikes integer DEFAULT 0 NOT NULL,
      created_at text DEFAULT CURRENT_TIMESTAMP NOT NULL,
      updated_at text DEFAULT CURRENT_TIMESTAMP NOT NULL
    );
  `);
  schemaReady = true;
}

export function getServiceDb() {
  return getDb();
}
