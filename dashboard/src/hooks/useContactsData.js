import { useState, useEffect, useCallback } from "react";
import { fetchMetrics, fetchContacts } from "../api/dashboardApi";

export function useContactsData(autoRefresh) {
  const [metrics, setMetrics] = useState(null);
  const [contacts, setContacts] = useState([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState(null);
  const [lastRefreshed, setLastRefreshed] = useState(null);

  const load = useCallback(async () => {
    try {
      const [metricsData, contactsData] = await Promise.all([
        fetchMetrics(),
        fetchContacts(),
      ]);
      setMetrics(metricsData);
      setContacts(contactsData.contacts ?? []);
      setLastRefreshed(new Date());
      setError(null);
    } catch (err) {
      setError(err);
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => {
    load();
  }, [load]);

  useEffect(() => {
    if (!autoRefresh) return;
    const id = setInterval(load, 60_000);
    return () => clearInterval(id);
  }, [autoRefresh, load]);

  return { metrics, contacts, loading, error, lastRefreshed, refresh: load };
}
