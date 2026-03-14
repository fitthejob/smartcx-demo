import { useState, useEffect } from "react";
import { fetchQueuesLive } from "../api/dashboardApi";

export function useQueueLive() {
  const [queues, setQueues] = useState([]);
  const [asOf, setAsOf] = useState(null);
  const [unavailable, setUnavailable] = useState(false);

  useEffect(() => {
    async function load() {
      try {
        const data = await fetchQueuesLive();
        setQueues(data.queues ?? []);
        setAsOf(new Date());
        setUnavailable(false);
      } catch {
        setUnavailable(true);
      }
    }

    load();
    const id = setInterval(load, 15_000);
    return () => clearInterval(id);
  }, []);

  return { queues, asOf, unavailable };
}
