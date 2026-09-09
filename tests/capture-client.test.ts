import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import {
  LiveCaptureClient,
  CaptureRequestError,
  orderTranscriptSegments,
  type CaptureDependencies,
} from '../src/capture';

const clients: LiveCaptureClient[] = [];

function setup() {
  const track = { enabled: true, onended: null, stop: vi.fn() };
  const stream = { getTracks: () => [track], getAudioTracks: () => [track] };
  const channel = {
    readyState: 'connecting',
    onmessage: null as null | ((event: { data: string }) => void),
    onopen: null as null | (() => void),
    onclose: null,
    send: vi.fn(),
    close: vi.fn(),
  };
  const peer = {
    connectionState: 'new',
    onconnectionstatechange: null,
    addTrack: vi.fn(),
    createDataChannel: vi.fn(() => channel),
    createOffer: vi.fn(async () => ({ type: 'offer', sdp: 'fake-sdp-offer' })),
    setLocalDescription: vi.fn(async () => undefined),
    setRemoteDescription: vi.fn(async () => {
      channel.readyState = 'open';
      channel.onopen?.();
    }),
    close: vi.fn(),
  };
  const session = {
    id: 'test-session',
    sdp: 'fake-sdp-answer',
    expiresAt: new Date(Date.now() + 60000).toISOString(),
    maxSeconds: 120,
    heartbeatSeconds: 20,
  };
  const eventListeners = new Map<string, (event: { data: string }) => void>();
  const observer = {
    addEventListener: (name: string, callback: (event: { data: string }) => void) =>
      eventListeners.set(name, callback),
    close: vi.fn(),
    onerror: null as null | (() => void),
  };
  const serverEvent = (name: string, data: unknown = {}) =>
    eventListeners.get(name)?.({ data: JSON.stringify(data) });
  const request = vi.fn(async (path: string) =>
    path === '/sessions'
      ? session
      : path.endsWith('/heartbeat')
        ? { expiresAt: new Date(Date.now() + 60000).toISOString(), remainingSeconds: 90 }
        : path.startsWith('/pages/')
          ? { segments: [], sessions: [] }
          : {},
  );
  const dependencies = {
    getUserMedia: vi.fn(async () => stream),
    createPeer: () => peer,
    createEvents: () => observer,
    request,
    now: Date.now,
  } as unknown as CaptureDependencies;
  const onChange = vi.fn();
  const client = new LiveCaptureClient({ pageId: 'page-id', onChange, dependencies });
  clients.push(client);
  const event = (data: Record<string, unknown>) =>
    channel.onmessage?.({ data: JSON.stringify(data) });
  return {
    client,
    track,
    stream,
    peer,
    channel,
    request,
    dependencies,
    onChange,
    event,
    observer,
    serverEvent,
  };
}

beforeEach(() => vi.useFakeTimers());
afterEach(() => {
  clients.splice(0).forEach((client) => client.dispose());
  vi.useRealTimers();
});

describe('browser live capture lifecycle', () => {
  it('keeps speech turns in their original order when confirmations arrive out of order', () => {
    const first = {
      id: 'a',
      sessionId: 'session',
      itemId: 'first',
      previousItemId: null,
      text: 'First turn.',
      createdAt: '2026-01-01T00:00:02.000Z',
    };
    const second = {
      id: 'b',
      sessionId: 'session',
      itemId: 'second',
      previousItemId: 'first',
      text: 'Second turn.',
      createdAt: '2026-01-01T00:00:01.000Z',
    };
    expect(orderTranscriptSegments([second, first])).toEqual([first, second]);
  });
  it('waits for an explicit start call before requesting microphone permission', async () => {
    const { client, dependencies, request } = setup();
    expect(dependencies.getUserMedia).not.toHaveBeenCalled();
    expect(request).not.toHaveBeenCalled();
    await client.start();
    expect(dependencies.getUserMedia).toHaveBeenCalledOnce();
    expect(request).toHaveBeenCalledWith(
      '/sessions',
      { pageId: 'page-id', sdp: 'fake-sdp-offer' },
      expect.any(Object),
    );
  });

  it('releases a microphone if permission resolves after cancellation', async () => {
    const { client, dependencies, stream, track, request } = setup();
    let resolvePermission!: (value: MediaStream) => void;
    vi.mocked(dependencies.getUserMedia).mockImplementation(
      () =>
        new Promise((resolve) => {
          resolvePermission = resolve;
        }),
    );
    const starting = client.start();
    await client.stop();
    resolvePermission(stream as unknown as MediaStream);
    await starting;
    expect(track.stop).toHaveBeenCalledOnce();
    expect(request).not.toHaveBeenCalled();
    expect(client.current.state).toBe('complete');
  });

  it('sends no consent assertion during setup and releases the microphone on pause', async () => {
    const { client, track, peer, request, serverEvent } = setup();
    await client.start();
    expect(request).toHaveBeenCalledWith(
      '/sessions',
      { pageId: 'page-id', sdp: 'fake-sdp-offer' },
      expect.any(Object),
    );
    expect(track.enabled).toBe(false);
    expect(client.current.state).toBe('connecting');
    serverEvent('ready');
    expect(track.enabled).toBe(true);
    expect(client.current.state).toBe('listening');
    const stopping = client.stop('paused');
    expect(track.enabled).toBe(false);
    expect(track.stop).toHaveBeenCalledOnce();
    expect(request).toHaveBeenCalledWith('/sessions/test-session/stop', { reason: 'paused' });
    await vi.advanceTimersByTimeAsync(350);
    await stopping;
    expect(peer.close).toHaveBeenCalledOnce();
    expect(request).toHaveBeenCalledWith('/sessions/test-session/stop', { reason: 'paused' });
    expect(client.current.state).toBe('paused');
  });

  it('keeps browser-reported text transient and accepts saved text only from the server observer', async () => {
    const { client, event, request, serverEvent } = setup();
    await client.start();
    serverEvent('ready');
    event({ type: 'input_audio_buffer.committed', item_id: 'item_2', previous_item_id: 'item_1' });
    event({
      type: 'conversation.item.input_audio_transcription.delta',
      item_id: 'item_2',
      delta: 'Hello',
    });
    expect(client.current.interim).toBe('Hello');
    expect(request.mock.calls.filter(([path]) => path.endsWith('/transcripts'))).toHaveLength(0);
    event({
      type: 'conversation.item.input_audio_transcription.completed',
      item_id: 'item_2',
      transcript: 'Hello team.',
    });
    event({
      type: 'conversation.item.input_audio_transcription.completed',
      item_id: 'item_2',
      transcript: 'Hello team.',
    });
    expect(client.current.interim).toBe('');
    expect(client.current.segments).toEqual([]);
    expect(client.current.unconfirmedText).toEqual(['Hello team.']);
    const segment = {
      id: 'segment-1',
      sessionId: 'test-session',
      itemId: 'item_2',
      previousItemId: 'item_1',
      text: 'Hello, team.',
      createdAt: new Date().toISOString(),
    };
    serverEvent('transcript', segment);
    serverEvent('transcript', segment);
    expect(client.current.segments).toEqual([segment]);
    expect(client.current.unconfirmedText).toEqual([]);
    expect(request.mock.calls.filter(([path]) => path.endsWith('/transcripts'))).toHaveLength(0);
  });

  it('retains unconfirmed text in memory and stops the microphone if the observer fails', async () => {
    const { client, event, observer, track, serverEvent } = setup();
    await client.start();
    serverEvent('ready');
    event({
      type: 'conversation.item.input_audio_transcription.completed',
      item_id: 'item_1',
      transcript: 'Keep this text.',
    });
    observer.onerror?.();
    expect(track.stop).toHaveBeenCalledOnce();
    expect(client.current.unconfirmedText).toEqual(['Keep this text.']);
    await vi.advanceTimersByTimeAsync(3050);
    expect(client.current.state).toBe('interrupted');
    expect(client.current.error).toContain('Copy the visible text');
    client.discardUnconfirmed();
    expect(client.current.unconfirmedText).toEqual([]);
  });

  it('does not expose provider error payloads and releases microphone access', async () => {
    const { client, event, track, serverEvent } = setup();
    await client.start();
    serverEvent('ready');
    event({ type: 'error', error: { message: 'Secret provider request detail' } });
    expect(track.stop).toHaveBeenCalledOnce();
    expect(client.current.error).not.toContain('Secret provider');
    await vi.advanceTimersByTimeAsync(350);
    expect(client.current.state).toBe('interrupted');
  });

  it('commits continuous speech periodically without sending audio through HTTP', async () => {
    const { client, event, channel, request, serverEvent } = setup();
    await client.start();
    serverEvent('ready');
    event({ type: 'input_audio_buffer.speech_started' });
    await vi.advanceTimersByTimeAsync(10000);
    expect(channel.send).toHaveBeenCalledWith(
      JSON.stringify({ type: 'input_audio_buffer.commit' }),
    );
    expect(request).toHaveBeenCalledTimes(1);
    event({ type: 'error', error: { code: 'input_audio_buffer_commit_empty' } });
    expect(client.current.state).toBe('listening');
  });

  it('reconnects after a server rollover and waits for the new observer before unmuting', async () => {
    const { client, serverEvent, dependencies, track } = setup();
    await client.start();
    serverEvent('ready');
    serverEvent('state', { reason: 'rollover' });
    expect(track.stop).toHaveBeenCalledOnce();
    await vi.advanceTimersByTimeAsync(350);
    expect(dependencies.getUserMedia).toHaveBeenCalledTimes(2);
    expect(client.current.state).toBe('connecting');
    expect(track.enabled).toBe(false);
    serverEvent('ready');
    expect(client.current.state).toBe('listening');
  });

  it('retries a rollover conflict while the prior server session finishes closing', async () => {
    const { client, serverEvent, request, track } = setup();
    const defaultRequest = request.getMockImplementation()!;
    let starts = 0;
    request.mockImplementation(async (path) => {
      if (path === '/sessions' && ++starts > 1 && starts < 4)
        throw new CaptureRequestError(409, 'Session is still closing.');
      return defaultRequest(path);
    });
    await client.start();
    serverEvent('ready');
    serverEvent('state', { reason: 'rollover' });
    await vi.advanceTimersByTimeAsync(1800);
    expect(starts).toBe(4);
    expect(client.current.state).toBe('connecting');
    expect(track.enabled).toBe(false);
    serverEvent('ready');
    expect(client.current.state).toBe('listening');
  });

  it('does not retry an active-session conflict on a user-initiated start', async () => {
    const { client, request, track } = setup();
    request.mockRejectedValueOnce(new CaptureRequestError(409, 'Only one meeting can be active.'));
    await client.start();
    expect(request).toHaveBeenCalledTimes(1);
    expect(track.stop).toHaveBeenCalledOnce();
    expect(client.current.state).toBe('interrupted');
    expect(client.current.error).toContain('Only one meeting');
  });

  it('terminates device capture immediately on disposal and sends a keepalive stop', async () => {
    const { client, track, peer, request } = setup();
    await client.start();
    client.dispose();
    expect(track.stop).toHaveBeenCalledOnce();
    expect(peer.close).toHaveBeenCalledOnce();
    expect(request).toHaveBeenCalledWith(
      '/sessions/test-session/stop',
      { reason: 'interrupted' },
      { keepalive: true },
    );
  });
});
