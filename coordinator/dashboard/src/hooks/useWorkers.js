import { useState, useEffect, useCallback } from 'react';
import { apiClient } from '../utils/api';

export const useWorkers = () => {
  const [workers, setWorkers] = useState([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState(null);

  const fetchWorkers = useCallback(async () => {
    // Debug: confirm token is present before fetch
    const token = localStorage.getItem('token');
    console.log('[useWorkers] fetchWorkers called, token present:', !!token);

    try {
      setLoading(true);
      // Use GET /api/workers (root handler added in last server fix)
      const response = await apiClient.get('/api/workers');
      console.log('[useWorkers] API response status:', response.status);
      console.log('[useWorkers] API response data:', response.data);

      const data = Array.isArray(response.data) ? response.data : [];
      setWorkers(data);
      setError(null);
      console.log('[useWorkers] workers state set to', data.length, 'workers');
    } catch (err) {
      console.error('[useWorkers] Failed to fetch workers:', err);
      console.error('[useWorkers] Error response:', err.response?.status, err.response?.data);
      setError(err.response?.data?.error || err.message || 'Failed to fetch workers');
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => {
    fetchWorkers();
    // Polling fallback every 30 seconds
    const interval = setInterval(fetchWorkers, 30000);
    return () => clearInterval(interval);
  }, [fetchWorkers]);

  return { workers, loading, error, refetch: fetchWorkers };
};
