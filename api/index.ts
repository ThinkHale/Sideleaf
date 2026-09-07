import { attachDatabasePool } from '@vercel/functions';
import { createApp } from '../server/app.js';
import { configuration } from '../server/config.js';
import { openDatabase } from '../server/database.js';

type App = ReturnType<typeof createApp>;
let initialization: Promise<App> | undefined;

async function initialize(): Promise<App> {
  // This entry is cloud-only. Local development keeps using server/index.ts.
  // Check before configuration() so missing cloud settings never create local files.
  const connection = process.env.DATABASE_URL;
  if (process.env.NODE_ENV !== 'production' || !connection?.trim()) {
    throw new Error('The cloud API requires production configuration.');
  }

  const config = await configuration();
  const database = await openDatabase(connection, undefined, { migrate: false });
  try {
    if (!database.pool) throw new Error('The cloud API requires PostgreSQL.');
    // Creating a pool does not connect. Confirm credentials, schema, and read access.
    await database.pool.query('SELECT id FROM auth_user LIMIT 0');
    const app = createApp(database.db, config);
    app.notFound((c) => c.json({ error: 'API route not found.' }, 404));
    attachDatabasePool(database.pool);
    return app;
  } catch (error) {
    await database.close().catch(() => undefined);
    throw error;
  }
}

function getApp(): Promise<App> {
  if (!initialization) {
    const pending = initialize();
    initialization = pending;
    // A failed cold start must not poison every later request in this instance.
    void pending.catch(() => {
      if (initialization === pending) initialization = undefined;
    });
  }
  return initialization;
}

export default {
  async fetch(request: Request): Promise<Response> {
    let app: App;
    try {
      app = await getApp();
    } catch {
      // Configuration and database errors can contain credentials or connection URLs.
      console.error(
        'Sideleaf API initialization failed. Check server configuration and database connectivity.',
      );
      return Response.json(
        { error: 'Sideleaf is temporarily unavailable. Please try again shortly.' },
        { status: 503, headers: { 'Cache-Control': 'no-store', 'Retry-After': '30' } },
      );
    }
    return app.fetch(request);
  },
};
