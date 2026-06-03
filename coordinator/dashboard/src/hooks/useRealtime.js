import { useEffect, useState } from 'react';
import { supabase } from '../utils/supabase';

export const useRealtime = () => {
  const [stats, setStats] = useState({});
  const [connected, setConnected] = useState(false);

  useEffect(() => {
    setConnected(true);

    // Subscribe to stats table for real-time updates
    const subscription = supabase
      .channel('public:stats')
      .on(
        'postgres_changes',
        {
          event: 'INSERT',
          schema: 'public',
          table: 'stats',
        },
        (payload) => {
          const { worker_id, hashrate, cpu_percent, uptime_secs, recorded_at } = payload.new;
          setStats((prev) => ({
            ...prev,
            [worker_id]: {
              hashrate,
              cpu_percent,
              uptime_secs,
              recorded_at,
            },
          }));
        }
      )
      .on(
        'postgres_changes',
        {
          event: 'UPDATE',
          schema: 'public',
          table: 'workers',
        },
        (payload) => {
          // Worker updated (e.g., last_seen)
          // Trigger refetch in parent component if needed
        }
      )
      .subscribe();

    return () => {
      subscription.unsubscribe();
      setConnected(false);
    };
  }, []);

  return { stats, connected };
};
