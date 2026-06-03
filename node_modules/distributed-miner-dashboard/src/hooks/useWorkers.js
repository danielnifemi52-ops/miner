import { useState, useEffect } from 'react';
import { apiClient } from '../utils/api';

export const useWorkers = () => {
  const [workers, setWorkers] = useState([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState(null);

  const fetchWorkers = async () => {
    try {
      setLoading(true);
      const response = await apiClient.get('/api/workers/all');
      setWorkers(response.data);
      setError(null);
    } catch (err) {
      console.error('Failed to fetch workers:', err);
      setError(err.message);
    } finally {
      setLoading(false);
    }
  };

  useEffect(() => {
    fetchWorkers();
    // Poll for updates every 30 seconds
    const interval = setInterval(fetchWorkers, 30000);
    return () => clearInterval(interval);
  }, []);

  return { workers, loading, error, refetch: fetchWorkers };
};
