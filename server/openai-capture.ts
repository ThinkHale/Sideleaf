import WebSocket from 'ws';

export type ProviderEvent = {
  type: string;
  item_id?: string;
  previous_item_id?: string | null;
  transcript?: string;
};
export interface CaptureObserver {
  events: AsyncIterable<ProviderEvent>;
  commit(): void;
  close(): void;
}
export interface CaptureProvider {
  create(sdp: string): Promise<{ callId: string; sdp: string }>;
  hangup(callId: string): Promise<void>;
  observe(callId: string): Promise<CaptureObserver>;
}

export function openAICapture(): CaptureProvider {
  const key = () => {
    if (!process.env.OPENAI_API_KEY) throw new Error('Transcription provider is not configured.');
    return process.env.OPENAI_API_KEY;
  };
  return {
    async create(sdp) {
      const body = new FormData();
      body.set('sdp', sdp);
      body.set(
        'session',
        JSON.stringify({
          type: 'transcription',
          audio: {
            input: {
              transcription: { model: 'gpt-4o-mini-transcribe' },
              turn_detection: {
                type: 'server_vad',
                threshold: 0.5,
                prefix_padding_ms: 300,
                silence_duration_ms: 600,
              },
            },
          },
        }),
      );
      const response = await fetch('https://api.openai.com/v1/realtime/calls', {
        method: 'POST',
        headers: { Authorization: `Bearer ${key()}` },
        body,
        signal: AbortSignal.timeout(45000),
      });
      if (!response.ok) {
        const failure = (await response.json().catch(() => ({}))) as {
          error?: { code?: unknown; param?: unknown };
        };
        const safe = (value: unknown) =>
          typeof value === 'string' && /^[\w.\[\]-]{1,100}$/.test(value) ? value : undefined;
        console.error(
          JSON.stringify({
            event: 'capture_provider_connection_failed',
            status: response.status,
            code: safe(failure.error?.code),
            param: safe(failure.error?.param),
          }),
        );
        throw new Error(`Transcription connection failed (${response.status}).`);
      }
      const location = response.headers.get('location');
      const callId = location?.split('/').at(-1);
      if (!callId || !/^[a-zA-Z0-9_-]{4,200}$/.test(callId))
        throw new Error('The provider returned no call identifier.');
      return { callId, sdp: await response.text() };
    },
    async hangup(callId) {
      const response = await fetch(
        `https://api.openai.com/v1/realtime/calls/${encodeURIComponent(callId)}/hangup`,
        {
          method: 'POST',
          headers: { Authorization: `Bearer ${key()}` },
          signal: AbortSignal.timeout(8000),
        },
      );
      await response.body?.cancel();
      if (!response.ok && response.status !== 404 && response.status !== 410)
        throw new Error(`The provider could not close the call (${response.status}).`);
    },
    async observe(callId) {
      const socket = new WebSocket(
        `wss://api.openai.com/v1/realtime?call_id=${encodeURIComponent(callId)}`,
        {
          headers: { Authorization: `Bearer ${key()}` },
          maxPayload: 256 * 1024,
          handshakeTimeout: 10000,
          perMessageDeflate: false,
        },
      );
      const queue: ProviderEvent[] = [];
      let ended = false,
        failure: Error | undefined;
      let wake: (() => void) | undefined;
      socket.on('message', (raw) => {
        try {
          const value = JSON.parse(raw.toString());
          // Never request/retrieve audio items, and never retain raw event payloads.
          if (
            value.type === 'error' ||
            value.type === 'conversation.item.input_audio_transcription.failed'
          ) {
            // Committing an already-empty VAD buffer is harmless during finalization.
            if (value.error?.code === 'input_audio_buffer_commit_empty') return;
            failure = new Error('The transcription provider reported an error.');
            ended = true;
          } else if (
            [
              'input_audio_buffer.committed',
              'conversation.item.input_audio_transcription.completed',
            ].includes(value.type)
          ) {
            if (queue.length >= 64) throw new Error('Transcription processing fell behind.');
            queue.push({
              type: value.type,
              item_id: value.item_id,
              previous_item_id: value.previous_item_id,
              transcript: value.transcript,
            });
          }
        } catch {
          failure = new Error('The transcription stream could not be processed.');
          ended = true;
        }
        wake?.();
      });
      socket.on('error', () => {
        failure = new Error('The transcription connection was interrupted.');
        ended = true;
        wake?.();
      });
      socket.on('close', () => {
        ended = true;
        wake?.();
      });
      await new Promise<void>((resolve, reject) => {
        socket.once('open', resolve);
        socket.once('error', () =>
          reject(new Error('Could not connect to the transcription observer.')),
        );
      });
      return {
        events: {
          async *[Symbol.asyncIterator]() {
            while (!ended || queue.length) {
              while (queue.length) yield queue.shift()!;
              if (!ended)
                await new Promise<void>((resolve) => {
                  wake = resolve;
                });
            }
            if (failure) throw failure;
          },
        },
        commit() {
          if (socket.readyState === WebSocket.OPEN)
            socket.send(JSON.stringify({ type: 'input_audio_buffer.commit' }));
        },
        close() {
          ended = true;
          wake?.();
          socket.terminate();
        },
      };
    },
  };
}
