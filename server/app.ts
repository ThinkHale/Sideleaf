import { Hono } from 'hono';
import { bodyLimit } from 'hono/body-limit';
import { secureHeaders } from 'hono/secure-headers';
import { and, eq, desc } from 'drizzle-orm';
import { z } from 'zod';
import { notebooks, pages, revisions, user } from './schema.js';
import { pageWriteSchema } from '../shared/domain.js';
import { exportMarkdown } from '../shared/export.js';
import type { Database } from './database.js';
import type { Config } from './config.js';
import { passwordAuthEnabled } from './config.js';
import { createAuth } from './auth.js';
import { createBilling, BillingError } from './billing.js';
import { createCapture, captureReady, CaptureError, CAPTURE_DISCLOSURE } from './capture.js';

export function createApp(db: Database, config: Config) {
  const auth = createAuth(db, config);
  const billing = createBilling(db, config);
  const capture = createCapture(db, config, billing.entitlement);
  const app = new Hono<{ Variables: { userId: string; signedInAt: Date } }>();
  app.use('*', secureHeaders({ crossOriginEmbedderPolicy: false }));
  app.use(
    '/api/*',
    bodyLimit({
      maxSize: 4 * 1024 * 1024,
      onError: (c) =>
        c.json({ error: 'This page is too large. Split it into smaller pages.' }, 413),
    }),
  );
  app.use('/api/*', async (c, next) => {
    c.header('Cache-Control', 'no-store');
    await next();
  });
  app.post('/api/billing/webhook', billing.webhook);
  app.get('/api/capture/maintenance', capture.maintenance);
  app.use('/api/*', async (c, next) => {
    if (
      !['GET', 'HEAD', 'OPTIONS'].includes(c.req.method) &&
      c.req.header('origin') !== config.origin
    )
      return c.json({ error: 'Untrusted request origin' }, 403);
    await next();
  });
  app.on(['GET', 'POST'], '/api/auth/*', (c) => auth.handler(c.req.raw));
  app.get('/api/health', (c) => c.json({ ok: true }));
  app.get('/api/config', (c) =>
    c.json({
      name: config.name,
      development: !config.production,
      passwordAuth: passwordAuthEnabled(config),
      googleAuth: Boolean(process.env.GOOGLE_CLIENT_ID && process.env.GOOGLE_CLIENT_SECRET),
      freeMinutes: config.freeMinutes,
      meetingMinutes: config.meetingMinutes,
      price: config.price,
      capture: {
        ready: captureReady(),
        disclosure: CAPTURE_DISCLOSURE,
        reason: captureReady()
          ? 'Live microphone transcription is available. Start it from your saved notebook page.'
          : 'Live transcription is not connected in this build. No microphone access will be requested. You can prepare the meeting and keep taking notes.',
      },
    }),
  );
  app.use('/api/*', async (c, next) => {
    const session = await auth.api.getSession({ headers: c.req.raw.headers });
    if (!session) return c.json({ error: 'Sign in to access your notebook.' }, 401);
    c.set('userId', session.user.id);
    c.set('signedInAt', session.session.createdAt);
    await next();
  });
  const owner = (id: string, uid: string) => and(eq(pages.id, id), eq(pages.userId, uid));
  app.get('/api/billing', billing.status);
  app.post('/api/billing/checkout', billing.checkout);
  app.post('/api/billing/portal', billing.portal);
  app.get('/api/capture/usage', capture.usageRoute);
  app.get('/api/capture/pages/:pageId', capture.page);
  app.post('/api/capture/sessions', capture.start);
  app.get('/api/capture/sessions/:id/events', capture.events);
  app.post('/api/capture/sessions/:id/heartbeat', capture.heartbeat);
  app.post('/api/capture/sessions/:id/stop', capture.stop);
  app.get('/api/notebooks', async (c) =>
    c.json(
      await db
        .select({ id: notebooks.id, name: notebooks.name, color: notebooks.color })
        .from(notebooks)
        .where(eq(notebooks.userId, c.get('userId'))),
    ),
  );
  app.post('/api/notebooks', async (c) => {
    const input = z
      .object({ id: z.string().uuid(), name: z.string().trim().min(1).max(80) })
      .strict()
      .parse(await c.req.json());
    await db
      .insert(notebooks)
      .values({ ...input, userId: c.get('userId') })
      .onConflictDoNothing();
    const [found] = await db
      .select({ id: notebooks.id, name: notebooks.name, color: notebooks.color })
      .from(notebooks)
      .where(and(eq(notebooks.id, input.id), eq(notebooks.userId, c.get('userId'))));
    return found ? c.json(found, 201) : c.json({ error: 'Notebook could not be created.' }, 409);
  });
  app.get('/api/pages', async (c) =>
    c.json(
      await db
        .select()
        .from(pages)
        .where(eq(pages.userId, c.get('userId')))
        .orderBy(desc(pages.updatedAt)),
    ),
  );
  app.get('/api/pages/:id', async (c) => {
    const [page] = await db
      .select()
      .from(pages)
      .where(owner(c.req.param('id'), c.get('userId')));
    return page ? c.json(page) : c.json({ error: 'Page not found.' }, 404);
  });
  app.put('/api/pages/:id', async (c) => {
    const id = z.string().uuid().parse(c.req.param('id'));
    const input = pageWriteSchema.parse(await c.req.json());
    // Only the provider observer may write confirmed transcript provenance.
    if (input.document.blocks.some((b) => b.source !== 'personal'))
      return c.json({ error: 'Transcript and AI blocks require a trusted ingestion route.' }, 422);
    const uid = c.get('userId');
    const [notebook] = await db
      .select()
      .from(notebooks)
      .where(and(eq(notebooks.id, input.notebookId), eq(notebooks.userId, uid)));
    if (!notebook) return c.json({ error: 'Notebook not found.' }, 404);
    const result = await db.transaction(async (tx) => {
      const [existing] = await tx.select().from(pages).where(eq(pages.id, id)).for('update');
      if (existing && existing.userId !== uid) return { kind: 'missing' as const };
      const [prior] = existing
        ? await tx
            .select()
            .from(revisions)
            .where(and(eq(revisions.pageId, id), eq(revisions.mutationId, input.mutationId)))
        : [];
      if (prior)
        return {
          kind: 'saved' as const,
          page: {
            ...existing!,
            title: prior.title,
            document: prior.document,
            version: prior.version,
          },
        };
      if ((existing?.version ?? 0) !== input.baseVersion)
        return { kind: 'conflict' as const, page: existing ?? null };
      const version = input.baseVersion + 1;
      const values = {
        title: input.title,
        notebookId: input.notebookId,
        document: input.document,
        version,
        updatedAt: new Date(),
      };
      let page;
      if (existing)
        [page] = await tx
          .update(pages)
          .set(values)
          .where(and(owner(id, uid), eq(pages.version, input.baseVersion)))
          .returning();
      else
        [page] = await tx
          .insert(pages)
          .values({ id, userId: uid, ...values })
          .onConflictDoNothing()
          .returning();
      if (!page) return { kind: 'conflict' as const, page: null };
      await tx.insert(revisions).values({
        pageId: id,
        version,
        title: input.title,
        document: input.document,
        mutationId: input.mutationId,
      });
      return { kind: 'saved' as const, page };
    });
    if (result.kind === 'missing') return c.json({ error: 'Page not found.' }, 404);
    if (result.kind === 'conflict')
      return c.json(
        { error: 'Another edit has been saved. Your draft is preserved.', current: result.page },
        409,
      );
    return c.json(result.page);
  });
  app.get('/api/pages/:id/history', async (c) => {
    const [page] = await db
      .select()
      .from(pages)
      .where(owner(c.req.param('id'), c.get('userId')));
    if (!page) return c.json({ error: 'Page not found.' }, 404);
    return c.json(
      await db
        .select()
        .from(revisions)
        .where(eq(revisions.pageId, page.id))
        .orderBy(desc(revisions.version))
        .limit(50),
    );
  });
  app.get('/api/pages/:id/export', async (c) => {
    const [page] = await db
      .select()
      .from(pages)
      .where(owner(c.req.param('id'), c.get('userId')));
    if (!page) return c.json({ error: 'Page not found.' }, 404);
    c.header('Content-Type', 'text/markdown; charset=utf-8');
    return c.body(exportMarkdown({ ...page, updatedAt: page.updatedAt.toISOString() }));
  });
  app.delete('/api/pages/:id', async (c) => {
    const found = await db.transaction(async (tx) => {
      await tx
        .select({ id: user.id })
        .from(user)
        .where(eq(user.id, c.get('userId')))
        .for('update');
      await capture.beforeDelete(c.get('userId'), c.req.param('id'), tx as unknown as Database);
      return tx
        .delete(pages)
        .where(owner(c.req.param('id'), c.get('userId')))
        .returning({ id: pages.id });
    });
    return found.length ? c.json({ deleted: true }) : c.json({ error: 'Page not found.' }, 404);
  });
  app.get('/api/account/export', async (c) =>
    c.json({
      exportedAt: new Date().toISOString(),
      schemaVersion: 2,
      transcripts: await capture.accountExport(c.get('userId')),
      notebooks: await db
        .select()
        .from(notebooks)
        .where(eq(notebooks.userId, c.get('userId'))),
      pages: await db
        .select()
        .from(pages)
        .where(eq(pages.userId, c.get('userId'))),
      revisions: await db
        .select({
          pageId: revisions.pageId,
          version: revisions.version,
          title: revisions.title,
          document: revisions.document,
          createdAt: revisions.createdAt,
        })
        .from(revisions)
        .innerJoin(pages, eq(pages.id, revisions.pageId))
        .where(eq(pages.userId, c.get('userId'))),
    }),
  );
  app.delete('/api/account', async (c) => {
    z.object({ confirmation: z.literal('DELETE') })
      .strict()
      .parse(await c.req.json());
    if (Date.now() - c.get('signedInAt').getTime() > 5 * 60 * 1000)
      return c.json({ error: 'Sign out and sign in again before deleting your account.' }, 403);
    await db.transaction(async (tx) => {
      await tx
        .select({ id: user.id })
        .from(user)
        .where(eq(user.id, c.get('userId')))
        .for('update');
      await capture.beforeDelete(c.get('userId'), undefined, tx as unknown as Database);
      await billing.beforeAccountDeletion(c.get('userId'), tx);
      await tx.delete(user).where(eq(user.id, c.get('userId')));
    });
    return c.json({ deleted: true });
  });
  app.post('/api/capture/start', (c) =>
    c.json(
      {
        error: 'CAPTURE_NOT_CONFIGURED',
        message:
          'Live transcription is not implemented in this slice. Your preparation and notes remain available.',
      },
      503,
    ),
  );
  app.onError((error, c) => {
    if (error instanceof CaptureError || error instanceof BillingError)
      return c.json({ error: error.message }, error.status);
    if (error instanceof z.ZodError)
      return c.json(
        {
          error: 'Invalid notebook data.',
          issues: error.issues.map((i) => ({ path: i.path, message: i.message })),
        },
        400,
      );
    // Deliberately omit request bodies, user content, stack traces and credentials.
    return c.json(
      { error: 'The operation could not be completed. Your local draft is preserved.' },
      500,
    );
  });
  return app;
}
