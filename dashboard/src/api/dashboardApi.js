import axios from "axios";

const api = axios.create({
  baseURL: import.meta.env.VITE_API_BASE_URL,
});

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
