import { useState } from 'react';
import { MicOff, Check } from 'lucide-react';
import { Modal } from './Modal';
import { templates, type Page, type Preparation as Prep } from '../../shared/domain';
import type { ProductConfig } from '../api';
import { captureSupported } from '../capture';
import { RECORDING_LAW_REMINDER, TERMS_PATH } from '../../shared/legal';
export function Preparation({
  page,
  config,
  onSave,
  onClose,
}: {
  page: Page;
  config: ProductConfig;
  onSave: (p: Page) => void;
  onClose: () => void;
}) {
  const [prep, setPrep] = useState(page.document.preparation),
    [title, setTitle] = useState(page.title),
    [ready, setReady] = useState(false);
  const field = (key: keyof Prep, label: string, placeholder = '', rows = 2) => (
    <label>
      {label}
      <textarea
        rows={rows}
        value={prep[key]}
        placeholder={placeholder}
        onChange={(e) => setPrep({ ...prep, [key]: e.target.value })}
      />
    </label>
  );
  return (
    <Modal title="Prepare a meeting" onClose={onClose} wide>
      <p className="muted">A little context goes a long way. Every field is optional.</p>
      <form
        onSubmit={(e) => {
          e.preventDefault();
          onSave({
            ...page,
            title: title.trim() || 'Untitled meeting',
            document: { ...page.document, preparation: prep, meetingState: 'prepared' },
          });
          onClose();
        }}
      >
        <label>
          Meeting title
          <input value={title} maxLength={200} onChange={(e) => setTitle(e.target.value)} />
        </label>
        <div className="form-row">
          <label>
            Meeting type
            <select
              value={prep.type}
              onChange={(e) => setPrep({ ...prep, type: e.target.value as Prep['type'] })}
            >
              {Object.keys(templates).map((type) => (
                <option key={type}>{type}</option>
              ))}
            </select>
          </label>
          <button
            type="button"
            className="template-button"
            onClick={() => {
              const defaults = templates[prep.type];
              setPrep({
                ...prep,
                ...Object.fromEntries(
                  Object.entries(defaults).filter(([key]) => !prep[key as keyof Prep]),
                ),
              });
            }}
          >
            Fill empty fields from template
          </button>
        </div>
        <div className="form-row">
          {field('participants', 'Participants', 'Names, roles, or teams')}
          {field('context', 'Company / context', 'What brings everyone together?')}
        </div>
        {field('outcome', 'Desired outcome', 'What would make this meeting useful?')}
        {field('agenda', 'Agenda', 'Topics to cover', 3)}
        <div className="form-row">
          {field('questions', 'Must-ask questions')}
          {field('concerns', 'Known concerns')}
        </div>
        {field('background', 'Background notes')}
        {field('references', 'Reference text', 'Paste relevant material here', 3)}
        <p className="fine-print">
          Preparation provides context. It is not evidence of what was said or agreed.
        </p>
        <div className="readiness">
          <MicOff size={20} />
          <div>
            <strong>In-person microphone capture</strong>
            <p>
              This listens to your device microphone. It does not capture both sides of arbitrary
              calls or meeting apps.
            </p>
            <p className="legal-reminder">
              {RECORDING_LAW_REMINDER}{' '}
              <a href={TERMS_PATH} target="_blank" rel="noreferrer">
                Review Terms
              </a>
              .
            </p>
            <button type="button" onClick={() => setReady(true)}>
              Check capture readiness
            </button>
            {ready && (
              <p
                role="status"
                className={config.capture.ready && captureSupported() ? '' : 'error'}
              >
                {!config.capture.ready
                  ? config.capture.reason
                  : !captureSupported()
                    ? 'This browser does not support live microphone transcription. Use a supported browser over HTTPS.'
                    : 'Live transcription is connected. Save your preparation, then start live capture above the notebook. Your microphone stays off until you start.'}
              </p>
            )}
            <small>
              Saving preparation does not start the microphone. Live capture begins only after you
              explicitly select Start.
            </small>
          </div>
        </div>
        <div className="modal-actions">
          <button type="button" onClick={onClose}>
            Cancel
          </button>
          <button type="submit" className="primary">
            <Check size={17} />
            Save preparation
          </button>
        </div>
      </form>
    </Modal>
  );
}
