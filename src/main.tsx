import { createRoot } from 'react-dom/client';
import App from './App';
import './styles.css';
import './print.css';
createRoot(document.getElementById('root')!).render(<App />);
// Cache only built static assets. Never cache authenticated API responses.
if (import.meta.env.PROD && 'serviceWorker' in navigator)
  navigator.serviceWorker.register('/sw.js').catch(() => {});
