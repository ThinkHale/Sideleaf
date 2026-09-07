import { randomUUID, timingSafeEqual } from 'node:crypto';
import { and, eq, inArray, lt, gt, sql, asc } from 'drizzle-orm';
import type { Context } from 'hono';
import { streamSSE } from 'hono/streaming';
import { z } from 'zod';
import type { Database } from './database.js';
import type { Config } from './config.js';
import { pages, user } from './schema.js';
import {
  captureSessions,
  captureUsage,
  captureWatchdog,
  meetingTranscripts,
} from './capture-schema.js';
import { openAICapture, type CaptureProvider, type CaptureObserver } from './openai-capture.js';

type AuthContext = Context<{ Variables: { userId: string; signedInAt: Date } }>;
const activeStates = ['starting', 'live', 'stopping'];
const endingStates = ['paused', 'stopped', 'interrupted', 'rollover', 'limit'];
export const CAPTURE_DISCLOSURE =
  'Audio streams to OpenAI for live transcription. Sideleaf saves the transcript, not audio files. OpenAI may retain API content in abuse-monitoring logs for up to 30 days by default, with legal or safety exceptions. API data is not used for training unless the account opts in. Inform participants and obtain any required consent.';
export function captureReady() {
  return Boolean(
    process.env.OPENAI_API_KEY &&
    process.env.CAPTURE_ENABLED === 'true' &&
    process.env.CAPTURE_WATCHDOG_ENABLED === 'true',
  );
}
export function calendarPeriod(date: Date) {
  return {
    start: new Date(Date.UTC(date.getUTCFullYear(), date.getUTCMonth(), 1)),
    end: new Date(Date.UTC(date.getUTCFullYear(), date.getUTCMonth() + 1, 1)),
  };
}
export function usageIntervals(from: Date, to: Date) {
  const result: { start: Date; end: Date; milliseconds: number }[] = [];
  let cursor = from.getTime();
  while (cursor < to.getTime()) {
    const period = calendarPeriod(new Date(cursor));
    const next = Math.min(to.getTime(), period.end.getTime());
    result.push({ ...period, milliseconds: next - cursor });
    cursor = next;
  }
  return result;
}
export class CaptureError extends Error {
  constructor(
    public status: 400 | 401 | 402 | 404 | 409 | 503,
    message: string,
  ) {
    super(message);
  }
}
type Session = typeof captureSessions.$inferSelect;

export function createCapture(
  db: Database,
  config: Config,
  entitlement: (uid: string) => Promise<{ plan: string }>,
  provider: CaptureProvider = openAICapture(),
  clock: () => Date = () => new Date(),
) {
  async function owned(uid: string, id: string) {
    const [found] = await db
      .select()
      .from(captureSessions)
      .where(and(eq(captureSessions.id, id), eq(captureSessions.userId, uid)));
    if (!found) throw new CaptureError(404, 'Meeting session not found.');
    return found;
  }
  async function ownedPage(uid: string, id: string) {
    const [found] = await db
      .select({ id: pages.id })
      .from(pages)
      .where(and(eq(pages.id, id), eq(pages.userId, uid)));
    if (!found) throw new CaptureError(404, 'Page not found.');
  }
  async function usage(uid: string, executor = db, knownPlan?: string) {
    const now = clock(),
      period = calendarPeriod(now);
    const [entry] = await executor
      .select()
      .from(captureUsage)
      .where(and(eq(captureUsage.userId, uid), eq(captureUsage.periodStart, period.start)));
    const sessions = await executor
      .select()
      .from(captureSessions)
      .where(and(eq(captureSessions.userId, uid), inArray(captureSessions.state, activeStates)));
    const pending = sessions.reduce(
      (total, session) =>
        total +
        (session.lastBilledAt
          ? Math.max(
              0,
              Math.min(
                now.getTime(),
                session.deadlineAt.getTime(),
                session.endedAt?.getTime() ?? Infinity,
              ) - Math.max(session.lastBilledAt.getTime(), period.start.getTime()),
            )
          : 0),
      0,
    );
    const plan = knownPlan || (await entitlement(uid)).plan;
    const usedMs = (entry?.usedMs || 0) + pending;
    return {
      plan,
      usedSeconds: Math.floor(usedMs / 1000),
      remainingSeconds:
        plan === 'pro' ? null : Math.max(0, Math.floor(config.freeMinutes * 60 - usedMs / 1000)),
      meetingLimitSeconds: plan === 'pro' ? null : config.meetingMinutes * 60,
      resetAt: period.end.toISOString(),
      activeSessionId: sessions[0]?.id || null,
    };
  }
  async function settle(session: Session, at: Date, terminal?: string) {
    return db.transaction(async (tx) => {
      await tx.select({ id: user.id }).from(user).where(eq(user.id, session.userId)).for('update');
      const [current] = await tx
        .select()
        .from(captureSessions)
        .where(eq(captureSessions.id, session.id))
        .for('update');
      if (!current || !activeStates.includes(current.state)) return;
      const until = new Date(
        Math.min(
          at.getTime(),
          current.deadlineAt.getTime(),
          current.endedAt?.getTime() ?? Infinity,
        ),
      );
      const from = current.lastBilledAt || current.activeAt;
      const elapsed = from ? Math.max(0, until.getTime() - from.getTime()) : 0;
      if (from && elapsed)
        for (const interval of usageIntervals(from, until)) {
          await tx
            .insert(captureUsage)
            .values({
              userId: current.userId,
              periodStart: interval.start,
              periodEnd: interval.end,
              usedMs: interval.milliseconds,
            })
            .onConflictDoUpdate({
              target: [captureUsage.userId, captureUsage.periodStart],
              set: { usedMs: sql`${captureUsage.usedMs} + ${interval.milliseconds}` },
            });
        }
      await tx
        .update(captureSessions)
        .set({
          billedMs: current.billedMs + elapsed,
          lastBilledAt: from ? until : null,
          ...(terminal
            ? { state: terminal, endedAt: current.endedAt || at, leaseExpiresAt: at }
            : {
                leaseExpiresAt: new Date(
                  Math.min(at.getTime() + 25000, current.deadlineAt.getTime()),
                ),
              }),
        })
        .where(eq(captureSessions.id, current.id));
    });
  }
  async function finish(session: Session, reason: string, at = clock()) {
    if (!activeStates.includes(session.state)) return;
    // Keep the lease eligible for watchdog retry if upstream termination fails.
    if (session.callId) await provider.hangup(session.callId);
    await settle(session, at, reason);
  }
  async function cleanup(uid?: string) {
    const expired = await db
      .select()
      .from(captureSessions)
      .where(
        and(
          inArray(captureSessions.state, activeStates),
          lt(captureSessions.leaseExpiresAt, clock()),
          ...(uid ? [eq(captureSessions.userId, uid)] : []),
        ),
      )
      .orderBy(asc(captureSessions.leaseExpiresAt))
      .limit(20);
    const results = await Promise.allSettled(
      expired.map((s) => finish(s, 'interrupted', s.leaseExpiresAt)),
    );
    if (results.some((r) => r.status === 'rejected'))
      throw new CaptureError(503, 'A previous meeting is still closing. Please retry shortly.');
  }
  const handler = (fn: (c: AuthContext) => Promise<Response>) => async (c: AuthContext) => {
    try {
      return await fn(c);
    } catch (e) {
      if (e instanceof z.ZodError) return c.json({ error: 'Invalid meeting request.' }, 400);
      if (!(e instanceof CaptureError)) {
        const error = e as { name?: unknown; code?: unknown; cause?: { code?: unknown } };
        const safe = (value: unknown) =>
          typeof value === 'string' && /^[\w-]{1,80}$/.test(value) ? value : undefined;
        console.error(
          JSON.stringify({
            event: 'capture_request_failed',
            name: safe(error?.name),
            code: safe(error?.code || error?.cause?.code),
          }),
        );
      }
      return c.json(
        {
          error:
            e instanceof CaptureError
              ? e.message
              : 'The transcription service is unavailable. Your notes are safe.',
        },
        e instanceof CaptureError ? e.status : 503,
      );
    }
  };
  return {
    usage,
    usageRoute: handler(async (c) => c.json(await usage(c.get('userId')))),
    page: handler(async (c) => {
      const uid = c.get('userId'),
        pageId = c.req.param('pageId')!;
      await ownedPage(uid, pageId);
      const sessions = await db
        .select({
          id: captureSessions.id,
          state: captureSessions.state,
          createdAt: captureSessions.createdAt,
          endedAt: captureSessions.endedAt,
          billedMs: captureSessions.billedMs,
        })
        .from(captureSessions)
        .where(eq(captureSessions.pageId, pageId))
        .orderBy(asc(captureSessions.createdAt));
      const segments = await db
        .select()
        .from(meetingTranscripts)
        .where(eq(meetingTranscripts.pageId, pageId))
        .orderBy(asc(meetingTranscripts.createdAt));
      return c.json({ sessions, segments, usage: await usage(uid) });
    }),
    start: handler(async (c) => {
      if (!captureReady())
        throw new CaptureError(
          503,
          'Live transcription is not connected in this build. The provider and session watchdog must be configured first.',
        );
      const input = z
        .object({
          pageId: z.string().uuid(),
          sdp: z.string().min(20).max(64000),
          consent: z.literal(true),
        })
        .strict()
        .parse(await c.req.json());
      const uid = c.get('userId');
      await ownedPage(uid, input.pageId);
      const [guard] = await db
        .select()
        .from(captureWatchdog)
        .where(eq(captureWatchdog.id, 'primary'));
      if (!guard || clock().getTime() - guard.checkedAt.getTime() > 90000)
        throw new CaptureError(
          503,
          'Session supervision is temporarily unavailable. Please try again shortly.',
        );
      await cleanup(uid);
      const plan = (await entitlement(uid)).plan;
      const reservation = await db.transaction(async (tx) => {
        await tx.select({ id: user.id }).from(user).where(eq(user.id, uid)).for('update');
        const existing = await tx
          .select({ id: captureSessions.id })
          .from(captureSessions)
          .where(
            and(eq(captureSessions.userId, uid), inArray(captureSessions.state, activeStates)),
          );
        if (existing.length)
          throw new CaptureError(409, 'Only one assisted meeting can be active on this account.');
        const attempts = await tx
          .select({ id: captureSessions.id })
          .from(captureSessions)
          .where(
            and(
              eq(captureSessions.userId, uid),
              gt(captureSessions.createdAt, new Date(clock().getTime() - 60000)),
            ),
          )
          .limit(5);
        if (attempts.length >= 5)
          throw new CaptureError(503, 'Please wait a minute before starting another connection.');
        const allowance = await usage(uid, tx as unknown as Database, plan);
        const prior = await tx
          .select({ total: sql<number>`coalesce(sum(${captureSessions.billedMs}), 0)` })
          .from(captureSessions)
          .where(eq(captureSessions.pageId, input.pageId));
        const remaining =
          allowance.plan === 'pro'
            ? 3600
            : Math.min(
                allowance.remainingSeconds || 0,
                config.meetingMinutes * 60 - Number(prior[0].total) / 1000,
              );
        if (remaining < 1)
          throw new CaptureError(
            402,
            'The free meeting allowance is exhausted. Ordinary notes and saved transcripts remain available.',
          );
        const now = clock();
        const item = {
          id: randomUUID(),
          userId: uid,
          pageId: input.pageId,
          state: 'starting',
          createdAt: now,
          leaseExpiresAt: new Date(now.getTime() + 70000),
          deadlineAt: new Date(now.getTime() + remaining * 1000),
        };
        await tx.insert(captureSessions).values(item);
        return { ...item, remaining };
      });
      let call: { callId: string; sdp: string } | undefined;
      try {
        call = await provider.create(input.sdp);
        const connectedAt = clock();
        // Meter from the moment the SDP can enable provider audio, including setup.
        const attached = await db
          .update(captureSessions)
          .set({
            callId: call.callId,
            activeAt: connectedAt,
            lastBilledAt: connectedAt,
            leaseExpiresAt: new Date(
              Math.min(connectedAt.getTime() + 20000, reservation.deadlineAt.getTime()),
            ),
          })
          .where(
            and(
              eq(captureSessions.id, reservation.id),
              eq(captureSessions.state, 'starting'),
              gt(captureSessions.leaseExpiresAt, connectedAt),
            ),
          )
          .returning({ id: captureSessions.id });
        if (!attached.length)
          throw new CaptureError(409, 'The meeting connection expired. Please try again.');
        return c.json({
          id: reservation.id,
          sdp: call.sdp,
          expiresAt: reservation.deadlineAt.toISOString(),
          maxSeconds: reservation.remaining,
          heartbeatSeconds: 10,
        });
      } catch (e) {
        let closed = !call;
        if (call) {
          try {
            await provider.hangup(call.callId);
            closed = true;
          } catch {
            /* Preserve the call identifier for the watchdog to retry. */
          }
        }
        await db
          .update(captureSessions)
          .set(
            closed
              ? { state: 'interrupted', endedAt: clock() }
              : {
                  callId: call!.callId,
                  state: 'stopping',
                  stopReason: 'interrupted',
                  endedAt: clock(),
                  leaseExpiresAt: clock(),
                },
          )
          .where(eq(captureSessions.id, reservation.id));
        throw e;
      }
    }),
    heartbeat: handler(async (c) => {
      const session = await owned(c.get('userId'), c.req.param('id')!);
      return c.json({
        expiresAt: session.leaseExpiresAt.toISOString(),
        remainingSeconds: Math.max(
          0,
          Math.floor((session.deadlineAt.getTime() - clock().getTime()) / 1000),
        ),
        state: session.state,
      });
    }),
    stop: handler(async (c) => {
      const reason = z
        .object({ reason: z.enum(['paused', 'stopped', 'interrupted']) })
        .strict()
        .parse(await c.req.json()).reason;
      const session = await owned(c.get('userId'), c.req.param('id')!);
      if (activeStates.includes(session.state)) {
        const at = clock();
        await db
          .update(captureSessions)
          .set({ state: 'stopping', stopReason: reason, endedAt: at })
          .where(
            and(
              eq(captureSessions.id, session.id),
              inArray(captureSessions.state, ['starting', 'live']),
            ),
          );
        // Let the observer commit and persist the last accepted speech turn.
        await new Promise((resolve) => setTimeout(resolve, 1600));
        await finish({ ...session, state: 'stopping', endedAt: at }, reason, at);
      }
      return c.json({ stopped: true, usage: await usage(c.get('userId')) });
    }),
    events: handler(async (c) => {
      const uid = c.get('userId'),
        id = c.req.param('id')!,
        observerId = randomUUID();
      const session = await db.transaction(async (tx) => {
        const [s] = await tx
          .select()
          .from(captureSessions)
          .where(and(eq(captureSessions.id, id), eq(captureSessions.userId, uid)))
          .for('update');
        if (!s) throw new CaptureError(404, 'Meeting session not found.');
        if (s.state !== 'starting' || s.observerId || s.leaseExpiresAt <= clock() || !s.callId)
          throw new CaptureError(409, 'This meeting connection is no longer available.');
        await tx.update(captureSessions).set({ observerId }).where(eq(captureSessions.id, id));
        return s;
      });
      let observer: CaptureObserver;
      try {
        observer = await provider.observe(session.callId!);
      } catch (e) {
        await finish(session, 'interrupted').catch(() => undefined);
        throw e;
      }
      const now = clock();
      let activated: { id: string }[];
      try {
        activated = await db
          .update(captureSessions)
          .set({
            state: 'live',
            leaseExpiresAt: new Date(Math.min(now.getTime() + 25000, session.deadlineAt.getTime())),
          })
          .where(
            and(
              eq(captureSessions.id, id),
              eq(captureSessions.state, 'starting'),
              eq(captureSessions.observerId, observerId),
              gt(captureSessions.leaseExpiresAt, now),
            ),
          )
          .returning({ id: captureSessions.id });
      } catch (e) {
        observer.close();
        await finish(session, 'interrupted').catch(() => undefined);
        throw e;
      }
      if (!activated.length) {
        observer.close();
        await provider.hangup(session.callId!).catch(() => undefined);
        throw new CaptureError(409, 'The meeting connection closed before it was ready.');
      }
      const live = { ...session, state: 'live', activeAt: now, lastBilledAt: now };
      return streamSSE(c, async (stream) => {
        let reason = 'interrupted',
          disconnected = false,
          failure = false,
          stopping = false;
        const parents = new Map<string, string | null>();
        const started = clock().getTime();
        let lastTick = started;
        stream.onAbort(() => {
          disconnected = true;
          observer.close();
        });
        const receive = (async () => {
          try {
            for await (const event of observer.events) {
              if (!event.item_id || !/^[\w-]{1,200}$/.test(event.item_id)) continue;
              if (event.type === 'input_audio_buffer.committed') {
                if (parents.size >= 1024) {
                  failure = true;
                  break;
                }
                parents.set(event.item_id, event.previous_item_id || null);
              }
              if (
                event.type === 'conversation.item.input_audio_transcription.completed' &&
                event.transcript?.trim()
              ) {
                if (event.transcript.length > 30000) {
                  failure = true;
                  break;
                }
                const segment = {
                  id: randomUUID(),
                  sessionId: id,
                  pageId: session.pageId,
                  itemId: event.item_id,
                  previousItemId: parents.get(event.item_id) || null,
                  text: event.transcript,
                  createdAt: clock(),
                };
                const stored = await db
                  .insert(meetingTranscripts)
                  .values(segment)
                  .onConflictDoNothing({
                    target: [meetingTranscripts.sessionId, meetingTranscripts.itemId],
                  })
                  .returning();
                if (stored.length && !disconnected)
                  await stream.writeSSE({
                    event: 'transcript',
                    data: JSON.stringify(stored[0]),
                    id: stored[0].id,
                  });
              }
            }
            if (!stopping) failure = true;
          } catch {
            failure = true;
          }
        })();
        try {
          await stream.writeSSE({ event: 'ready', data: '{}' });
          while (!disconnected && !failure) {
            await stream.sleep(500);
            const at = clock();
            const [current] = await db
              .select()
              .from(captureSessions)
              .where(eq(captureSessions.id, id));
            if (!current || endingStates.includes(current.state)) {
              reason = current?.state || 'stopped';
              break;
            }
            if (current.state === 'stopping') {
              stopping = true;
              observer.commit();
              await stream.sleep(1200);
              reason = current.stopReason || 'stopped';
              break;
            }
            if (at >= session.deadlineAt) {
              reason = 'limit';
              break;
            }
            if (at.getTime() - started >= 225000) {
              reason = 'rollover';
              break;
            }
            if (at.getTime() - lastTick >= 10000) {
              await settle(current, at);
              await stream.writeSSE({
                event: 'heartbeat',
                data: JSON.stringify({
                  remainingSeconds: Math.max(
                    0,
                    Math.floor((session.deadlineAt.getTime() - at.getTime()) / 1000),
                  ),
                }),
              });
              lastTick = at.getTime();
            }
          }
          stopping = true;
          if (!disconnected) {
            observer.commit();
            await stream.sleep(800);
          }
        } finally {
          stopping = true;
          if (!disconnected)
            await stream
              .writeSSE({
                event: 'state',
                data: JSON.stringify({
                  reason,
                  message:
                    reason === 'rollover'
                      ? 'Reconnecting transcription. Audio during the brief reconnect is not saved.'
                      : undefined,
                }),
              })
              .catch(() => undefined);
          await finish(live, reason).catch(() => {
            reason = 'interrupted';
          });
          observer.close();
          await receive;
        }
      });
    }),
    maintenance: async (c: Context) => {
      const expected = process.env.CAPTURE_CRON_SECRET;
      const token = c.req.header('authorization') || '';
      const target = `Bearer ${expected}`;
      if (
        !expected ||
        Buffer.byteLength(token) !== Buffer.byteLength(target) ||
        !timingSafeEqual(Buffer.from(token), Buffer.from(target))
      )
        return c.json({ error: 'Unauthorized' }, 401);
      try {
        await cleanup();
        const backlog = await db
          .select({ id: captureSessions.id })
          .from(captureSessions)
          .where(
            and(
              inArray(captureSessions.state, activeStates),
              lt(captureSessions.leaseExpiresAt, clock()),
            ),
          )
          .limit(1);
        if (backlog.length) throw new CaptureError(503, 'Session cleanup is still in progress.');
        await db
          .insert(captureWatchdog)
          .values({ id: 'primary', checkedAt: clock() })
          .onConflictDoUpdate({ target: captureWatchdog.id, set: { checkedAt: clock() } });
        return c.json({ ok: true });
      } catch {
        return c.json({ error: 'Session cleanup will retry.' }, 503);
      }
    },
    async beforeDelete(uid: string, pageId?: string, executor = db) {
      const sessions = await executor
        .select()
        .from(captureSessions)
        .where(
          and(
            eq(captureSessions.userId, uid),
            inArray(captureSessions.state, activeStates),
            ...(pageId ? [eq(captureSessions.pageId, pageId)] : []),
          ),
        );
      if (sessions.length)
        throw new CaptureError(409, 'Stop the active meeting before deleting its page or account.');
    },
    async accountExport(uid: string) {
      return db
        .select({
          id: meetingTranscripts.id,
          sessionId: meetingTranscripts.sessionId,
          pageId: meetingTranscripts.pageId,
          itemId: meetingTranscripts.itemId,
          text: meetingTranscripts.text,
          createdAt: meetingTranscripts.createdAt,
        })
        .from(meetingTranscripts)
        .innerJoin(pages, eq(pages.id, meetingTranscripts.pageId))
        .where(eq(pages.userId, uid));
    },
  };
}
