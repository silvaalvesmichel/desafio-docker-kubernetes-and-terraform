// Constant load on the API through the Ingress, enough to push its CPU above the HPA target.
// Usage: k6 run -e BASE_URL=http://mural.localtest.me infra/k6/load.js
import http from "k6/http";
import { check } from "k6";

const BASE_URL = __ENV.BASE_URL || "http://mural.localtest.me";

export const options = {
  vus: Number(__ENV.VUS || 50),
  duration: __ENV.DURATION || "3m",
};

export default function () {
  const res = http.get(`${BASE_URL}/api/messages`);
  check(res, { "status is 200": (r) => r.status === 200 });
}
