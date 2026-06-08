import { useEffect, useState, useCallback } from 'react';
import { supabase } from '../utils/supabase';

export const useRealtime = (onWorkerChange) => {
  const [stats, setStats] = useState({});
  const [connected, setConnected] = useState(false);

  // Stable callback ref so the subscription closure always calls the latest version
  const handleWorkerChange = useCallback(() => {
    if (typeof onWorkerChange === 'function') {
      console.log('[useRealtime] Worker table updated — triggering refetch');
      onWorkerChange();
    }
  }, [onWorkerChange]);

  useEffect(() => {
    console.log('[useRealtime] Setting up Supabase realtime subscription…');

    const fetchInitialStats = async () => {
      try {
        const { data, error } = await supabase
          .from('stats')
          .select('*')
          .order('recorded_at', { ascending: false });
        
        if (!error && data) {
          const latestStats = {};
          for (const s of data) {
            if (!latestStats[s.worker_id]) {
              latestStats[s.worker_id] = {
                hashrate: s.hashrate,
                cpu_percent: s.cpu_percent,
                uptime_secs: s.uptime_secs,
                recorded_at: s.recorded_at,
              };
            }
          }
          setStats(latestStats);
        }
      } catch (err) {
        console.error('[useRealtime] Error fetching initial stats:', err);
      }
    };

    fetchInitialStats();

    const subscription = supabase
      .channel('dashboard-realtime')
      .on(
        'postgres_changes',
        {
          event: 'INSERT',
          schema: 'public',
          table: 'stats',
        },
        (payload) => {
          console.log('[useRealtime] stats INSERT received:', payload.new);
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
          console.log('[useRealtime] workers UPDATE received:', payload.new);
          // Refresh the full workers list so last_seen etc. are current
          handleWorkerChange();
        }
      )
      .on(
        'postgres_changes',
        {
          event: 'INSERT',
          schema: 'public',
          table: 'workers',
        },
        (payload) => {
          console.log('[useRealtime] workers INSERT received (new worker!):', payload.new);
          // New worker registered — force full list refresh
          handleWorkerChange();
        }
      )
      .subscribe((status) => {
        console.log('[useRealtime] subscription status:', status);
        if (status === 'SUBSCRIBED') {
          setConnected(true);
          console.log('[useRealtime] ✓ Connected to Supabase Realtime');
        } else if (status === 'CLOSED' || status === 'CHANNEL_ERROR') {
          setConnected(false);
          console.warn('[useRealtime] ✗ Disconnected from Supabase Realtime:', status);
        }
      });

    return () => {
      console.log('[useRealtime] Cleaning up subscription');
      supabase.removeChannel(subscription);
      setConnected(false);
    };
  }, [handleWorkerChange]);

  return { stats, connected };
};
