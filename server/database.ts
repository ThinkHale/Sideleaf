import { PGlite } from '@electric-sql/pglite';
import { drizzle, type PgliteDatabase } from 'drizzle-orm/pglite';
import { drizzle as postgresDrizzle } from 'drizzle-orm/node-postgres';
import pg from 'pg';
import { readFile, mkdir, rm } from 'node:fs/promises';
import { resolve, join } from 'node:path';
import lockfile from 'proper-lockfile';
import * as schema from './schema';
import { appDataDirectory } from './paths';

export type Database = PgliteDatabase<typeof schema>;
export async function openDatabase(
  connection?: string,
  directory = join(appDataDirectory, 'database'),
) {
  const migration = await readFile(
    new URL('./migrations/001_notebook.sql', import.meta.url),
    'utf8',
  );
  if (connection) {
    const pool = new pg.Pool({ connectionString: connection, max: 10 });
    await pool.query(migration);
    // Both adapters expose the same PostgreSQL relational/transaction API used here.
    return {
      db: postgresDrizzle(pool, { schema }) as unknown as Database,
      close: () => pool.end(),
    };
  }
  let release: (() => Promise<void>) | undefined;
  if (directory !== ':memory:') {
    const target = resolve(directory);
    await mkdir(target, { recursive: true });
    release = await lockfile.lock(target, {
      retries: { retries: 6, minTimeout: 2000 },
      stale: 10000,
    });
    // PGlite uses a synthetic process id. Its stale Postgres marker cannot be
    // unlinked by the WASM filesystem on Windows after a forced process exit.
    // Only remove this marker after acquiring our exclusive application lock.
    await rm(join(target, 'postmaster.pid'), { force: true });
  }
  const client = new PGlite(directory === ':memory:' ? undefined : directory);
  try {
    await client.exec(migration);
  } catch (error) {
    await release?.();
    throw error;
  }
  return {
    db: drizzle(client, { schema }),
    close: async () => {
      await client.close();
      await release?.();
    },
  };
}
