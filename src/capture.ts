import type { CaptureState } from '../shared/domain';
import type {
  CaptureHeartbeat,
  CapturePageResult,
  CaptureSession,
  CaptureStopReason,
  SavedTranscriptSegment,
} from '../shared/capture';
import { notifyIfLegalAcceptanceRequired } from './api';

export type CaptureSnapshot = {
  state: CaptureState;
  elapsedSeconds: number;
  remainingSeconds: number | null;
  interim: string;
  segments: SavedTranscriptSegment[];
  unconfirmedText: string[];
  error: string;
};
export const initialCaptureSnapshot = (): CaptureSnapshot => ({
  state: 'ready',
  elapsedSeconds: 0,
  remainingSeconds: null,
  interim: '',
  segments: [],
  unconfirmedText: [],
  error: '',
});
type Request = <T>(path: string, body?: unknown, options?: RequestInit) => Promise<T>;
export class CaptureRequestError extends Error {
  constructor(
    public status: number,
    message: string,
  ) {
    super(message);
  }
}
export type CaptureDependencies = {
  getUserMedia: (constraints: MediaStreamConstraints) => Promise<MediaStream>;
  createPeer: () => RTCPeerConnection;
  createEvents: (sessionId: string) => EventSource;
  request: Request;
  now: () => number;
};
async function request<T>(path: string, body?: unknown, options: RequestInit = {}): Promise<T> {
  const response = await fetch(`/api/capture${path}`, {
    method: body === undefined ? 'GET' : 'POST',
    credentials: 'same-origin',
    headers: { 'Content-Type': 'application/json' },
    body: body === undefined ? undefined : JSON.stringify(body),
    signal: AbortSignal.timeout(20000),
    ...options,
  });
  const data = await response.json().catch(() => ({}));
  if (!response.ok) {
    notifyIfLegalAcceptanceRequired(response.status, data);
    throw new CaptureRequestError(
      response.status,
      typeof data.error === 'string' ? data.error : 'Capture request failed.',
    );
  }
  return data as T;
}
export function captureSupported() {
  return (
    typeof window !== 'undefined' &&
    window.isSecureContext &&
    !!navigator.mediaDevices?.getUserMedia &&
    typeof RTCPeerConnection !== 'undefined' &&
    typeof EventSource !== 'undefined'
  );
}
type Unconfirmed = { sessionId: string; itemId: string; text: string };

export function orderTranscriptSegments(segments: SavedTranscriptSegment[]) {
  const byItem = new Map(
    segments.map((segment) => [`${segment.sessionId}:${segment.itemId}`, segment]),
  );
  const visited = new Set<string>();
  const result: SavedTranscriptSegment[] = [];
  const visit = (segment: SavedTranscriptSegment) => {
    if (visited.has(segment.id)) return;
    visited.add(segment.id);
    const previous =
      segment.previousItemId && byItem.get(`${segment.sessionId}:${segment.previousItemId}`);
    if (previous) visit(previous);
    result.push(segment);
  };
  [...segments].sort((a, b) => a.createdAt.localeCompare(b.createdAt)).forEach(visit);
  return result;
}

// Microphone audio travels directly over WebRTC. Only the server observer confirms saved text.
export class LiveCaptureClient {
  private snapshot = initialCaptureSnapshot();
  private deps: CaptureDependencies;
  private stream?: MediaStream;
  private peer?: RTCPeerConnection;
  private channel?: RTCDataChannel;
  private observer?: EventSource;
  private observerReady = false;
  private session?: CaptureSession;
  private startAbort?: AbortController;
  private generation = 0;
  private disposed = false;
  private startedAt = 0;
  private priorSeconds = 0;
  private deadline = 0;
  private timer?: ReturnType<typeof setInterval>;
  private heartbeatTimer?: ReturnType<typeof setTimeout>;
  private connectionTimer?: ReturnType<typeof setTimeout>;
  private ending?: Promise<void>;
  private unconfirmed: Unconfirmed[] = [];
  private interim = new Map<string, string>();
  private completed = new Set<string>();
  private awaiting = new Set<string>();
  private speechStartedAt: number | null = null;
  private lastCommitAt = 0;

  constructor(
    private options: {
      pageId: string;
      onChange: (snapshot: CaptureSnapshot) => void;
      dependencies?: Partial<CaptureDependencies>;
    },
  ) {
    this.deps = {
      getUserMedia: (constraints) => navigator.mediaDevices.getUserMedia(constraints),
      createPeer: () => new RTCPeerConnection(),
      createEvents: (id) => new EventSource(`/api/capture/sessions/${id}/events`),
      request,
      now: Date.now,
      ...options.dependencies,
    };
  }
  get current() {
    return this.snapshot;
  }
  private publish(change: Partial<CaptureSnapshot> = {}) {
    this.snapshot = {
      ...this.snapshot,
      ...change,
      interim: [...this.interim.values()].join(' '),
      unconfirmedText: this.unconfirmed.map(({ text }) => text),
    };
    if (!this.disposed) this.options.onChange(this.snapshot);
  }
  async refreshTranscript() {
    try {
      const data = await this.deps.request<CapturePageResult>(`/pages/${this.options.pageId}`);
      if (this.disposed) return;
      for (const segment of data.segments) this.acceptSaved(segment);
      if (this.snapshot.error.startsWith('Saved transcripts could not'))
        this.publish({ error: '' });
    } catch {
      this.publish({
        error:
          'Saved transcripts could not be loaded. Check your connection and refresh the transcript.',
      });
    }
  }
  private acceptSaved(segment: SavedTranscriptSegment) {
    if (!segment || typeof segment.id !== 'string' || typeof segment.text !== 'string') return;
    this.unconfirmed = this.unconfirmed.filter(
      (entry) => entry.sessionId !== segment.sessionId || entry.itemId !== segment.itemId,
    );
    if (this.session?.id === segment.sessionId) {
      this.completed.add(segment.itemId);
      this.awaiting.delete(segment.itemId);
      this.interim.delete(segment.itemId);
    }
    const segments = this.snapshot.segments.filter((entry) => entry.id !== segment.id);
    segments.push(segment);
    this.publish({ segments: orderTranscriptSegments(segments) });
  }
  discardUnconfirmed() {
    this.unconfirmed = [];
    this.interim.clear();
    this.publish({ error: '' });
  }

  async start(rollover = false) {
    if (
      this.disposed ||
      this.ending ||
      ['connecting', 'listening', 'finalizing'].includes(this.snapshot.state)
    )
      return;
    if (this.unconfirmed.length || this.interim.size) {
      this.publish({ error: 'Check the unconfirmed transcript before starting again.' });
      return;
    }
    const generation = ++this.generation;
    this.interim.clear();
    this.completed.clear();
    this.awaiting.clear();
    this.observerReady = false;
    this.speechStartedAt = null;
    this.publish({ state: 'connecting', error: '', remainingSeconds: null });
    try {
      const stream = await this.deps.getUserMedia({
        audio: {
          echoCancellation: true,
          noiseSuppression: true,
          autoGainControl: true,
        },
        video: false,
      });
      if (generation !== this.generation || this.disposed) {
        stream.getTracks().forEach((track) => track.stop());
        return;
      }
      this.stream = stream;
      if (!stream.getAudioTracks().length) throw new Error('No microphone was found.');
      const peer = this.deps.createPeer();
      this.peer = peer;
      stream.getTracks().forEach((track) => {
        // No speech leaves the device until the server confirms its observer is ready.
        track.enabled = false;
        peer.addTrack(track, stream);
        track.onended = () =>
          void this.interrupt('The microphone disconnected. Reconnect it and resume.');
      });
      const channel = peer.createDataChannel('oai-events');
      this.channel = channel;
      channel.onmessage = (event) => this.receive(event.data);
      channel.onopen = () => this.beginListening();
      channel.onclose = () => {
        if (this.snapshot.state === 'listening')
          void this.interrupt('The live connection closed. Resume to reconnect.');
      };
      peer.onconnectionstatechange = () => {
        if (['failed', 'disconnected'].includes(peer.connectionState)) {
          void this.interrupt(
            'The live connection was interrupted. Resume when your connection is stable.',
          );
        }
      };
      const offer = await peer.createOffer();
      await peer.setLocalDescription(offer);
      if (generation !== this.generation) return;
      if (!offer.sdp) throw new Error('Your browser could not start a microphone connection.');
      this.startAbort = new AbortController();
      const signal = AbortSignal.any([this.startAbort.signal, AbortSignal.timeout(65000)]);
      let session: CaptureSession | undefined;
      for (let attempt = 0; attempt <= 3; attempt++) {
        try {
          session = await this.deps.request<CaptureSession>(
            '/sessions',
            {
              pageId: this.options.pageId,
              sdp: offer.sdp,
            },
            { signal },
          );
          break;
        } catch (error) {
          // Rollover can race the previous call's final database update. Never retry other failures.
          if (
            !rollover ||
            !(error instanceof CaptureRequestError) ||
            error.status !== 409 ||
            attempt === 3
          )
            throw error;
          await new Promise((resolve) => setTimeout(resolve, [400, 800, 1600][attempt]));
          if (generation !== this.generation || this.disposed) return;
          if (signal.aborted) throw signal.reason;
        }
      }
      if (!session) throw new Error('Could not reconnect live capture.');
      if (generation !== this.generation || this.disposed) {
        await this.deps
          .request(`/sessions/${session.id}/stop`, { reason: 'interrupted' })
          .catch(() => undefined);
        return;
      }
      this.session = session;
      this.deadline = this.deps.now() + session.maxSeconds * 1000;
      this.publish({ remainingSeconds: session.maxSeconds });
      this.connectionTimer = setTimeout(() => {
        void this.interrupt('The microphone connection timed out. Check your network and resume.');
      }, 15000);
      this.openObserver(session.id);
      await peer.setRemoteDescription({ type: 'answer', sdp: session.sdp });
      if (generation !== this.generation || this.disposed) return;
      this.timer = setInterval(() => this.tick(), 1000);
      this.scheduleHeartbeat();
    } catch (error) {
      if (generation !== this.generation || this.disposed) return;
      const denied = error instanceof DOMException && error.name === 'NotAllowedError';
      const missing = error instanceof DOMException && error.name === 'NotFoundError';
      await this.interrupt(
        denied
          ? 'Microphone permission was denied. Allow microphone access in your browser, then resume.'
          : missing
            ? 'No microphone was found. Connect a microphone, then resume.'
            : error instanceof Error
              ? error.message
              : 'Could not start live capture.',
      );
    }
  }
  private beginListening() {
    if (
      !this.session ||
      !this.observerReady ||
      this.channel?.readyState !== 'open' ||
      this.snapshot.state !== 'connecting'
    )
      return;
    this.stream?.getAudioTracks().forEach((track) => {
      track.enabled = true;
    });
    this.startedAt = this.deps.now();
    this.lastCommitAt = this.startedAt;
    clearTimeout(this.connectionTimer);
    this.publish({ state: 'listening' });
  }
  private openObserver(sessionId: string) {
    const observer = this.deps.createEvents(sessionId);
    this.observer = observer;
    observer.addEventListener('ready', () => {
      if (this.session?.id !== sessionId) return;
      this.observerReady = true;
      this.beginListening();
    });
    observer.addEventListener('transcript', (event) => {
      if (this.session?.id !== sessionId) return;
      try {
        this.acceptSaved(JSON.parse((event as MessageEvent).data));
      } catch {
        /* Invalid event is ignored. */
      }
    });
    observer.addEventListener('state', (event) => {
      if (this.session?.id !== sessionId || this.ending) return;
      let data: { reason?: string; message?: string };
      try {
        data = JSON.parse((event as MessageEvent).data);
      } catch {
        return;
      }
      observer.close();
      if (data.reason === 'rollover' && this.snapshot.state === 'listening') {
        void (async () => {
          await this.stop('paused');
          if (!this.disposed) await this.start(true);
        })();
      } else {
        void this.interrupt(
          data.message || 'This live session ended. Your saved transcript is available below.',
        );
      }
    });
    observer.onerror = () => {
      observer.close();
      if (this.session?.id === sessionId && !this.ending) {
        void this.interrupt(
          'The transcript connection was interrupted. Refresh the saved transcript, then resume.',
        );
      }
    };
  }
  private tick() {
    const now = this.deps.now();
    if (
      this.snapshot.state === 'listening' &&
      this.channel?.readyState === 'open' &&
      now - this.lastCommitAt >= 10000 &&
      (this.speechStartedAt !== null || this.interim.size > 0)
    ) {
      this.lastCommitAt = now;
      this.channel.send(JSON.stringify({ type: 'input_audio_buffer.commit' }));
    }
    if (this.snapshot.state === 'listening')
      this.publish({
        elapsedSeconds: this.priorSeconds + Math.floor((now - this.startedAt) / 1000),
        remainingSeconds: Math.max(0, Math.ceil((this.deadline - now) / 1000)),
      });
    if (now >= this.deadline)
      void this.interrupt(
        'The time available for this session has ended. Your saved notes remain available.',
      );
    if (this.session && now >= Date.parse(this.session.expiresAt))
      void this.interrupt('The session could not renew. Resume to reconnect.');
  }
  private scheduleHeartbeat() {
    if (!this.session) return;
    const sessionId = this.session.id;
    this.heartbeatTimer = setTimeout(
      async () => {
        try {
          const result = await this.deps.request<CaptureHeartbeat>(
            `/sessions/${sessionId}/heartbeat`,
            {},
          );
          if (this.session?.id !== sessionId || this.ending || this.disposed) return;
          this.session.expiresAt = result.expiresAt;
          this.deadline = this.deps.now() + result.remainingSeconds * 1000;
          this.scheduleHeartbeat();
        } catch {
          if (this.session?.id === sessionId && !this.ending)
            await this.interrupt('The session could not renew. Check your connection and resume.');
        }
      },
      Math.max(1, this.session.heartbeatSeconds) * 1000,
    );
  }
  private receive(raw: unknown) {
    if (typeof raw !== 'string' || raw.length > 100000 || !this.session) return;
    let event: Record<string, unknown>;
    try {
      event = JSON.parse(raw);
    } catch {
      return;
    }
    if (!event || typeof event !== 'object') return;
    const itemId = typeof event.item_id === 'string' ? event.item_id : '';
    if (event.type === 'input_audio_buffer.speech_started') this.speechStartedAt = this.deps.now();
    if (event.type === 'input_audio_buffer.committed' && itemId) {
      this.speechStartedAt = null;
      if (!this.completed.has(itemId)) this.awaiting.add(itemId);
    }
    if (
      event.type === 'conversation.item.input_audio_transcription.delta' &&
      itemId &&
      typeof event.delta === 'string' &&
      !this.completed.has(itemId)
    ) {
      this.interim.set(itemId, ((this.interim.get(itemId) || '') + event.delta).slice(0, 30000));
      this.publish();
    }
    if (
      event.type === 'conversation.item.input_audio_transcription.completed' &&
      itemId &&
      typeof event.transcript === 'string' &&
      !this.completed.has(itemId)
    ) {
      this.completed.add(itemId);
      this.interim.delete(itemId);
      if (event.transcript.trim())
        this.unconfirmed.push({
          sessionId: this.session.id,
          itemId,
          text: event.transcript.trim(),
        });
      this.publish();
    }
    if (event.type === 'conversation.item.input_audio_transcription.failed') {
      this.awaiting.delete(itemId);
      void this.interrupt(
        'A speech segment could not be transcribed. Please check the last words in your notes.',
      );
    }
    if (event.type === 'error') {
      const error = event.error as { code?: string } | undefined;
      if (error?.code === 'input_audio_buffer_commit_empty') return;
      void this.interrupt(
        'The transcription service reported an error. Your saved notes remain available.',
      );
    }
  }
  private async interrupt(message: string) {
    if (this.disposed || this.ending || !['connecting', 'listening'].includes(this.snapshot.state))
      return;
    this.publish({ error: message });
    await this.stop('interrupted');
  }
  async stop(reason: CaptureStopReason = 'stopped') {
    if (this.ending) return this.ending;
    if (['ready', 'complete', 'paused', 'interrupted'].includes(this.snapshot.state)) {
      if (reason === 'stopped') this.publish({ state: 'complete' });
      return;
    }
    ++this.generation;
    this.startAbort?.abort();
    if (this.snapshot.state === 'listening')
      this.priorSeconds += Math.floor((this.deps.now() - this.startedAt) / 1000);
    this.publish({ state: 'finalizing', elapsedSeconds: this.priorSeconds });
    this.releaseMicrophone();
    this.clearTimers();
    this.ending = (async () => {
      const session = this.session;
      if (this.channel?.readyState === 'open') {
        if (this.speechStartedAt !== null && this.deps.now() - this.speechStartedAt >= 100) {
          this.channel.send(JSON.stringify({ type: 'input_audio_buffer.commit' }));
        }
      }
      // Notify the server before draining final text so paused time is not metered.
      const stopped = session
        ? this.deps.request(`/sessions/${session.id}/stop`, { reason }).catch(() => {
            this.publish({
              error:
                this.snapshot.error ||
                'Capture stopped on this device. The server session will close when its lease expires.',
            });
          })
        : Promise.resolve();
      if (this.channel?.readyState === 'open') {
        for (let attempt = 0; attempt < 20; attempt++) {
          await new Promise((resolve) => setTimeout(resolve, 150));
          if (
            attempt >= 1 &&
            !this.awaiting.size &&
            !this.interim.size &&
            !this.unconfirmed.length &&
            this.speechStartedAt === null
          )
            break;
        }
      }
      await stopped;
      this.closePeer();
      if (session) {
        await this.refreshTranscript();
      }
      this.observer?.close();
      this.observer = undefined;
      this.session = undefined;
      if (this.interim.size || this.unconfirmed.length)
        this.publish({
          error:
            'Some speech could not be confirmed as saved. Copy the visible text before leaving this page.',
        });
      this.publish({
        state:
          reason === 'paused' ? 'paused' : reason === 'interrupted' ? 'interrupted' : 'complete',
        remainingSeconds: null,
      });
    })().finally(() => {
      this.ending = undefined;
    });
    return this.ending;
  }
  private releaseMicrophone() {
    this.stream?.getTracks().forEach((track) => {
      track.onended = null;
      track.enabled = false;
      track.stop();
    });
    this.stream = undefined;
  }
  private clearTimers() {
    clearInterval(this.timer);
    clearTimeout(this.heartbeatTimer);
    clearTimeout(this.connectionTimer);
  }
  private closePeer() {
    if (this.channel) {
      this.channel.onclose = null;
      this.channel.onmessage = null;
      this.channel.onopen = null;
      this.channel.close();
    }
    if (this.peer) {
      this.peer.onconnectionstatechange = null;
      this.peer.close();
    }
    this.channel = undefined;
    this.peer = undefined;
  }
  dispose() {
    if (this.disposed) return;
    this.disposed = true;
    ++this.generation;
    this.startAbort?.abort();
    this.releaseMicrophone();
    this.clearTimers();
    this.closePeer();
    this.observer?.close();
    if (this.session) {
      void this.deps
        .request(
          `/sessions/${this.session.id}/stop`,
          { reason: 'interrupted' },
          { keepalive: true },
        )
        .catch(() => undefined);
      this.session = undefined;
    }
  }
}
