import { PGlite } from '@electric-sql/pglite';
import { drizzle, type PgliteDatabase } from 'drizzle-orm/pglite';
import { drizzle as postgresDrizzle } from 'drizzle-orm/node-postgres';
import pg from 'pg';
import { readFile, mkdir, rm } from 'node:fs/promises';
import { resolve, join } from 'node:path';
import lockfile from 'proper-lockfile';
import * as schema from './schema.js';
import { appDataDirectory } from './paths.js';

export type Database = PgliteDatabase<typeof schema>;
export async function openDatabase(
  connection?: string,
  directory = join(appDataDirectory, 'database'),
  options: { migrate?: boolean } = {},
) {
  const production = process.env.NODE_ENV === 'production';
  if (production && !connection)
    throw new Error('Production requires an external PostgreSQL connection.');
  const migrate = options.migrate ?? !production;
  const migration = () =>
    readFile(new URL('./migrations/001_notebook.sql', import.meta.url), 'utf8');
  if (connection) {
    if (production) {
      let address: URL;
      try {
        address = new URL(connection);
      } catch {
        throw new Error('The PostgreSQL connection URL is invalid.');
      }
      if (
        !['postgres:', 'postgresql:'].includes(address.protocol) ||
        address.searchParams.getAll('sslmode').length !== 1 ||
        address.searchParams.get('sslmode') !== 'verify-full' ||
        address.searchParams.has('ssl')
      )
        throw new Error(
          'Production PostgreSQL requires sslmode=verify-full without an ssl override.',
        );
    }
    const pool = new pg.Pool({
      connectionString: connection,
      max: 5,
      idleTimeoutMillis: 5000,
      connectionTimeoutMillis: 10000,
      allowExitOnIdle: true,
    });
    pool.on('error', () => {
      console.error('An idle PostgreSQL connection closed unexpectedly. The pool will reconnect.');
    });
    try {
      if (migrate) await pool.query(await migration());
      // Both adapters expose the same PostgreSQL relational/transaction API used here.
      return {
        db: postgresDrizzle(pool, { schema }) as unknown as Database,
        pool,
        close: () => pool.end(),
      };
    } catch (error) {
      await pool.end();
      throw error;
    }
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
    if (migrate) await client.exec(await migration());
  } catch (error) {
    await client.close();
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
