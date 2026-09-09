import { useEffect, useRef } from 'react';
import { X } from 'lucide-react';
import type { ReactNode } from 'react';
export function Modal({
  title,
  onClose,
  children,
  wide = false,
  dismissDisabled = false,
}: {
  title: string;
  onClose: () => void;
  children: ReactNode;
  wide?: boolean;
  dismissDisabled?: boolean;
}) {
  const ref = useRef<HTMLDialogElement>(null);
  useEffect(() => {
    ref.current?.showModal();
    return () => ref.current?.close();
  }, []);
  return (
    <dialog
      ref={ref}
      className={wide ? 'modal wide' : 'modal'}
      onCancel={(event) => {
        if (dismissDisabled) event.preventDefault();
        else onClose();
      }}
      onClick={(e) => {
        if (!dismissDisabled && e.target === e.currentTarget) onClose();
      }}
      aria-label={title}
      aria-busy={dismissDisabled}
    >
      <div className="modal-inner">
        <div className="modal-heading">
          <h2>{title}</h2>
          <button
            className="icon-button"
            aria-label="Close dialog"
            disabled={dismissDisabled}
            onClick={onClose}
          >
            <X size={20} />
          </button>
        </div>
        {children}
      </div>
    </dialog>
  );
}
