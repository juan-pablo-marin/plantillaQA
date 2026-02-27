import http from 'k6/http';
import { check, sleep, group } from 'k6';
import { Rate, Trend } from 'k6/metrics';

const BACKEND_URL = __ENV.BACKEND_URL || 'http://backend:8080';
const AUTH_ID_USER = __ENV.K6_AUTH_ID_USER;
const AUTH_PASSWORD = __ENV.K6_AUTH_PASSWORD;

const errors = new Rate('errors');
const healthLatency = new Trend('health_latency');
const usersLatency = new Trend('users_latency');

export const options = {
  stages: [
    { duration: '30s', target: 10 },   // ramp-up
    { duration: '1m',  target: 50 },   // carga sostenida
    { duration: '30s', target: 100 },  // pico
    { duration: '30s', target: 0 },    // ramp-down
  ],
  thresholds: {
    http_req_duration: ['p(95)<500'],   // 95% de requests < 500ms
    errors: ['rate<0.1'],               // < 10% de errores
    health_latency: ['p(99)<200'],      // health check < 200ms
  },
};

export function setup() {
  if (!AUTH_ID_USER || !AUTH_PASSWORD) {
    return { token: null };
  }

  const res = http.post(
    `${BACKEND_URL}/api/v1/auth/login`,
    JSON.stringify({ id_user: AUTH_ID_USER, password: AUTH_PASSWORD }),
    { headers: { 'Content-Type': 'application/json' } },
  );

  const ok = check(res, { 'login status 200': (r) => r.status === 200 });
  if (!ok) {
    return { token: null };
  }

  try {
    const json = res.json();
    let token = null;
    if (json && json.data && json.data.token) {
      token = json.data.token;
    }
    return { token: token };
  } catch (_) {
    return { token: null };
  }
}

export default function (data) {
  const token = data && data.token ? data.token : null;
  const authHeaders = token ? { Authorization: `Bearer ${token}` } : null;

  group('Health Check', () => {
    const res = http.get(`${BACKEND_URL}/health`);
    healthLatency.add(res.timings.duration);
    const ok = check(res, {
      'health status 200': (r) => r.status === 200,
      'health response < 100ms': (r) => r.timings.duration < 100,
    });
    errors.add(!ok);
  });

  group('API - Listar usuarios', () => {
    if (!authHeaders) {
      return;
    }

    const res = http.get(`${BACKEND_URL}/api/v1/users/`, { headers: authHeaders });
    usersLatency.add(res.timings.duration);
    const ok = check(res, {
      'users status 200': (r) => r.status === 200,
      'users response < 500ms': (r) => r.timings.duration < 500,
    });
    errors.add(!ok);
  });

  group('API - Geographic data', () => {
    const res = http.get(`${BACKEND_URL}/api/v1/geo/`);
    const ok = check(res, {
      'geo status 200': (r) => r.status === 200,
    });
    errors.add(!ok);
  });

  sleep(1);
}

export function handleSummary(data) {
  return {
    '/qa/reports/k6-summary.json': JSON.stringify(data, null, 2),
  };
}
