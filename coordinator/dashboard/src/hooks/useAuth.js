import { useState, useEffect } from 'react';

export const useAuth = () => {
  const [token, setToken] = useState(null);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    // Check localStorage for token on mount
    const storedToken = localStorage.getItem('token');
    if (storedToken) {
      try {
        // Validate token is not expired (basic check)
        const parts = storedToken.split('.');
        if (parts.length === 3) {
          setToken(storedToken);
        }
      } catch (err) {
        localStorage.removeItem('token');
      }
    }
    setLoading(false);
  }, []);

  const login = (newToken) => {
    localStorage.setItem('token', newToken);
    setToken(newToken);
    return true;
  };

  const logout = () => {
    localStorage.removeItem('token');
    setToken(null);
  };

  return { token, loading, login, logout };
};
