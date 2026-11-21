// Prueba de carga para demostrar el escalado del HPA (2 → 5 pods).
// Corre en un contenedor y le pega al Service LoadBalancer por el host:
//   docker run --rm -v "${PWD}/loadtest:/scripts" grafana/k6 run /scripts/k6-hpa.js
// Duración total: ~6 min. Mientras corre, mira Grafana y `kubectl get hpa -w`.
import http from 'k6/http';
import { check, sleep } from 'k6';

const BASE = __ENV.BASE_URL || 'http://host.docker.internal';

export const options = {
  scenarios: {
    carga: {
      executor: 'ramping-vus',
      startVUs: 0,
      stages: [
        { duration: '30s', target: 20 },  // calentamiento
        { duration: '4m', target: 50 },   // carga sostenida: el HPA debería llegar a 5
        { duration: '1m', target: 0 },    // bajada
      ],
      gracefulRampDown: '10s',
    },
  },
  thresholds: {
    // Si el escalado funciona, la API aguanta la carga sin errores.
    http_req_failed: ['rate<0.01'],
    http_req_duration: ['p(95)<1000'],
  },
};

export default function () {
  const r = Math.random();
  let res;
  if (r < 0.15) {
    res = http.post(`${BASE}/tasks/`, JSON.stringify({
      title: `carga-${__VU}-${__ITER}`,
      description: 'creada por k6',
    }), { headers: { 'Content-Type': 'application/json' } });
    check(res, { 'POST 201': (x) => x.status === 201 });
  } else {
    res = http.get(`${BASE}/tasks/`);
    check(res, { 'GET 200': (x) => x.status === 200 });
  }
  sleep(0.05);
}
