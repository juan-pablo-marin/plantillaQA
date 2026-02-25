import http from 'k6/http';
import { check, sleep, group } from 'k6';
import { Rate, Trend } from 'k6/metrics';

const BACKEND_URL = __ENV.BACKEND_URL || 'http://backend:8080';

const errorRate = new Rate('errors');
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

export default function () {

  group('Health Check', () => {
    const res = http.get(`${BACKEND_URL}/health`);
    healthLatency.add(res.timings.duration);
    check(res, {
      'health status 200': (r) => r.status === 200,
      'health response < 100ms': (r) => r.timings.duration < 100,
    }) || errorRate.add(1);
  });

  group('API - Listar usuarios', () => {
    const res = http.get(`${BACKEND_URL}/api/v1/users`);
    usersLatency.add(res.timings.duration);
    check(res, {
      'users status 200': (r) => r.status === 200,
      'users response < 500ms': (r) => r.timings.duration < 500,
    }) || errorRate.add(1);
  });

  group('API - Geographic data', () => {
    const res = http.get(`${BACKEND_URL}/api/v1/geo`);
    check(res, {
      'geo status 200': (r) => r.status === 200,
    }) || errorRate.add(1);
  });

  sleep(1);
}

export function handleSummary(data) {
  return {
    '/qa/reports/k6-summary.json': JSON.stringify(data, null, 2),
  };
}
