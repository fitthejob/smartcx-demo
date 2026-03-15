import axios from "axios";
import { getIdToken, signOut } from "../auth/cognitoClient";

const api = axios.create({
  baseURL: import.meta.env.VITE_API_BASE_URL,
});

// Attach the Cognito ID token as a Bearer token before every request.
// The SDK auto-refreshes the session from localStorage if it has expired.
api.interceptors.request.use((config) => {
  const token = getIdToken();
  if (token) {
    config.headers.Authorization = `Bearer ${token}`;
  }
  return config;
});

// On 401, clear auth state and reload so the login page is shown.
api.interceptors.response.use(
  (res) => res,
  (err) => {
    if (err.response?.status === 401) {
      signOut();
      window.location.reload();
    }
    return Promise.reject(err);
  }
);

export async function fetchMetrics() {
  const { data } = await api.get("/metrics");
  return data;
}

export async function fetchContacts() {
  const { data } = await api.get("/contacts");
  return data;
}

export async function fetchQueuesLive() {
  const { data } = await api.get("/queues/live");
  return data;
}
