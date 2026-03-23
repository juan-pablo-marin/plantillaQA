import http from 'k6/http';
import { check, sleep, group } from 'k6';
import { Rate, Trend } from 'k6/metrics';
import { jUnit } from 'https://jslib.k6.io/k6-summary/0.0.3/index.js';

// RAV — ajusta BACKEND_URL en docker-compose / .env.qa (por defecto :8082)
const BACKEND_URL = __ENV.BACKEND_URL || 'http://backend:8082';

const errors = new Rate('errors');
const rootLatency = new Trend('root_latency');

export const options = {
  stages: [
    { duration: '30s', target: 10 },
    { duration: '1m', target: 30 },
    { duration: '30s', target: 0 },
  ],
  thresholds: {
    http_req_duration: ['p(95)<800'],
    errors: ['rate<0.2'],
    root_latency: ['p(99)<500'],
  },
};

export default function () {
  group('Raíz (Gin sin ruta / → 404)', () => {
    const res = http.get(`${BACKEND_URL}/`);
    rootLatency.add(res.timings.duration);
    const ok = check(res, {
      'status 404 o 200': (r) => r.status === 404 || r.status === 200,
    });
    errors.add(!ok);
  });

  sleep(1);
}

export function handleSummary(data) {
  return {
    '/qa/reports/k6/summary.json': JSON.stringify(data, null, 2),
    '/qa/reports/k6/junit.xml': jUnit(data),
  };
}
