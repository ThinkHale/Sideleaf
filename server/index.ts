import { serve } from '@hono/node-server';
import { serveStatic } from '@hono/node-server/serve-static';
import { configuration } from './config.js';
import { openDatabase } from './database.js';
import { createApp } from './app.js';
const config = await configuration();
const database = await openDatabase(process.env.DATABASE_URL);
const app = createApp(database.db, config);
if (config.production || process.env.SERVE_WEB === 'true') {
  app.use('/*', serveStatic({ root: './dist/web' }));
  app.get('*', serveStatic({ path: './dist/web/index.html' }));
}
const server = serve(
  {
    fetch: app.fetch,
    hostname: config.production ? '0.0.0.0' : '127.0.0.1',
    port: Number(process.env.PORT || 3001),
  },
  (info) => console.log(`Notebook API ready on port ${info.port}. Audio capture is disabled.`),
);
async function shutdown() {
  server.close();
  await database.close();
  process.exit(0);
}
process.once('SIGINT', shutdown);
process.once('SIGTERM', shutdown);
