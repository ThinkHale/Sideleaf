import { useEffect, useRef, useState } from 'react';
import { Download, Mic, MicOff, Pause, Play, Square } from 'lucide-react';
import { captureSupported, initialCaptureSnapshot, LiveCaptureClient } from '../capture';
import { download } from '../api';
import '../capture.css';

const clock = (seconds: number) =>
  `${Math.floor(seconds / 60)}:${String(seconds % 60).padStart(2, '0')}`;

export function LiveCapture({
  pageId,
  ready,
  reason,
  onActiveChange,
  onMicrophoneChange,
}: {
  pageId: string;
  ready: boolean;
  reason: string;
  onActiveChange?: (active: boolean) => void;
  onMicrophoneChange?: (live: boolean) => void;
}) {
  const [snapshot, setSnapshot] = useState(initialCaptureSnapshot);
  const [consent, setConsent] = useState(false);
  const client = useRef<LiveCaptureClient | null>(null);
  const onActive = useRef(onActiveChange);
  onActive.current = onActiveChange;
  const onMicrophone = useRef(onMicrophoneChange);
  onMicrophone.current = onMicrophoneChange;
  const supported = captureSupported();
  const busy = ['connecting', 'listening', 'finalizing'].includes(snapshot.state);
  const active = busy || snapshot.unconfirmedText.length > 0 || snapshot.interim.length > 0;

  useEffect(() => {
    let current = new LiveCaptureClient({ pageId, onChange: setSnapshot });
    client.current = current;
    setSnapshot(initialCaptureSnapshot());
    setConsent(false);
    void current.refreshTranscript();
    const pagehide = () => current.dispose();
    const pageshow = (event: PageTransitionEvent) => {
      if (!event.persisted) return;
      current = new LiveCaptureClient({ pageId, onChange: setSnapshot });
      client.current = current;
      setSnapshot(initialCaptureSnapshot());
      setConsent(false);
      void current.refreshTranscript();
    };
    const offline = () => void current.stop('interrupted');
    const beforeunload = (event: BeforeUnloadEvent) => {
      if (
        ['connecting', 'listening', 'finalizing'].includes(current.current.state) ||
        current.current.unconfirmedText.length ||
        current.current.interim.length
      ) {
        event.preventDefault();
        event.returnValue = '';
      }
    };
    window.addEventListener('pagehide', pagehide);
    window.addEventListener('pageshow', pageshow);
    window.addEventListener('offline', offline);
    window.addEventListener('beforeunload', beforeunload);
    return () => {
      current.dispose();
      onActive.current?.(false);
      onMicrophone.current?.(false);
      window.removeEventListener('pagehide', pagehide);
      window.removeEventListener('pageshow', pageshow);
      window.removeEventListener('offline', offline);
      window.removeEventListener('beforeunload', beforeunload);
    };
  }, [pageId]);

  useEffect(() => {
    onActive.current?.(active);
  }, [active]);
  useEffect(() => {
    onMicrophone.current?.(snapshot.state === 'listening');
  }, [snapshot.state]);
  const label = {
    ready: 'Ready to listen',
    connecting: 'Connecting microphone',
    listening: 'Listening',
    paused: 'Microphone paused',
    interrupted: 'Capture interrupted',
    finalizing: 'Finishing transcript',
    complete: 'Capture complete',
  }[snapshot.state];

  return (
    <section className={`live-capture ${snapshot.state}`} aria-label="Live transcription">
      <div className="capture-heading">
        {snapshot.state === 'listening' ? <Mic size={18} /> : <MicOff size={18} />}
        <strong role="status">{label}</strong>
        <span className="capture-clock" aria-label={`${snapshot.elapsedSeconds} seconds captured`}>
          {clock(snapshot.elapsedSeconds)}
        </span>
        {snapshot.remainingSeconds !== null && (
          <small>{clock(snapshot.remainingSeconds)} available</small>
        )}
      </div>
      {!busy && (
        <div className="capture-introduction">
          <p>
            Turn this device’s microphone into live notes. Capture only what the microphone can
            hear.
          </p>
          <p className="fine-print">
            Audio is streamed to OpenAI for transcription. Sideleaf saves transcript text and does
            not create or store an audio recording. OpenAI may retain API content for up to 30 days
            in abuse-monitoring logs, with legal or safety exceptions. Connected time, including
            brief setup, counts toward your allowance.
          </p>
          <label className="checkbox">
            <input
              type="checkbox"
              checked={consent}
              onChange={(event) => setConsent(event.target.checked)}
            />
            I have informed participants and obtained the consent required for this meeting.
          </label>
        </div>
      )}
      {!ready && <p className="notice">{reason}</p>}
      {!supported && (
        <p className="notice">
          Live capture needs microphone access in a supported browser over HTTPS.
        </p>
      )}
      <div className="capture-controls">
        {!busy && (
          <button
            className="primary"
            disabled={
              !ready ||
              !supported ||
              !consent ||
              snapshot.unconfirmedText.length > 0 ||
              snapshot.interim.length > 0
            }
            onClick={() => void client.current?.start(consent)}
          >
            <Play size={16} />
            {['paused', 'interrupted'].includes(snapshot.state)
              ? 'Resume capture'
              : 'Start live capture'}
          </button>
        )}
        {snapshot.state === 'listening' && (
          <button onClick={() => void client.current?.stop('paused')}>
            <Pause size={16} />
            Pause
          </button>
        )}
        {busy && (
          <button
            disabled={snapshot.state === 'finalizing'}
            onClick={() => void client.current?.stop()}
          >
            <Square size={15} />
            {snapshot.state === 'connecting' ? 'Cancel' : 'Stop'}
          </button>
        )}
        <button onClick={() => void client.current?.refreshTranscript()}>Refresh transcript</button>
      </div>
      {snapshot.state === 'listening' && (
        <p className="fine-print">
          The microphone is live. Keep this tab open. Pause to release the microphone.
        </p>
      )}
      {snapshot.interim && (
        <div className="capture-interim" aria-label="Unfinished transcript">
          <small>Transcribing</small>
          <p>{snapshot.interim}</p>
        </div>
      )}
      {snapshot.unconfirmedText.length > 0 && (
        <div className="capture-unsaved" aria-label="Unconfirmed transcript">
          <strong>Waiting for save confirmation</strong>
          {snapshot.unconfirmedText.map((text, index) => (
            <p key={index}>{text}</p>
          ))}
        </div>
      )}
      {!busy && (snapshot.unconfirmedText.length > 0 || snapshot.interim) && (
        <div className="capture-controls">
          <button
            onClick={() =>
              download(
                [snapshot.interim, ...snapshot.unconfirmedText].filter(Boolean).join('\n\n'),
                'sideleaf-unconfirmed-transcript.txt',
                'text/plain',
              )
            }
          >
            Download unconfirmed text
          </button>
          <button onClick={() => client.current?.discardUnconfirmed()}>
            Discard unconfirmed text
          </button>
        </div>
      )}
      {snapshot.error && (
        <p className="error" role="alert">
          {snapshot.error}
        </p>
      )}
      {snapshot.segments.length > 0 && (
        <div className="capture-transcript" aria-label="Saved meeting transcript">
          <div className="capture-heading">
            <h3>Meeting transcript</h3>
            <button
              onClick={() =>
                download(
                  snapshot.segments.map((segment) => segment.text).join('\n\n'),
                  'sideleaf-transcript.txt',
                  'text/plain',
                )
              }
            >
              <Download size={16} />
              Export transcript
            </button>
          </div>
          <p className="fine-print">
            Saved separately from your notes. Review names, numbers, and decisions for transcription
            errors.
          </p>
          {snapshot.segments.map((segment) => (
            <p key={segment.id}>{segment.text}</p>
          ))}
        </div>
      )}
    </section>
  );
}
