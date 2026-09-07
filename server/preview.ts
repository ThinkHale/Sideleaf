export {};
process.env.SERVE_WEB = 'true';
process.env.APP_ORIGIN ||= `http://127.0.0.1:${process.env.PORT || 3001}`;
await import('./index');
