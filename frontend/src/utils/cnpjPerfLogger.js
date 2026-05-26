import { API_ENDPOINTS } from '@/config/api';

const sentSessions = new Set();

export function createCnpjPerfSession(cnpj) {
  const cleanCnpj = String(cnpj ?? '').replace(/\D/g, '');
  const sessionId = `${cleanCnpj || 'cnpj'}-${Date.now()}-${Math.random().toString(36).slice(2, 8)}`;
  const startedAt = performance.now();

  return {
    cnpj: cleanCnpj,
    sessionId,
    startedAt,
  };
}

export function logCnpjPerf(session, event, detail = {}) {
  if (!session?.cnpj || !event) return;

  const elapsedMs = Math.max(0, performance.now() - session.startedAt);
  const payload = {
    cnpj: session.cnpj,
    event,
    elapsed_ms: Number(elapsedMs.toFixed(2)),
    session_id: session.sessionId,
    detail,
  };

  const key = `${payload.session_id}|${payload.event}|${JSON.stringify(payload.detail)}`;
  if (sentSessions.has(key)) return;
  sentSessions.add(key);

  const body = JSON.stringify(payload);
  const blob = new Blob([body], { type: 'application/json' });

  if (navigator.sendBeacon?.(API_ENDPOINTS.analyticsClientPerf, blob)) {
    return;
  }

  fetch(API_ENDPOINTS.analyticsClientPerf, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body,
    keepalive: true,
  }).catch((error) => {
    console.warn('[CNPJ perf] Falha ao registrar evento de performance:', error);
  });
}
