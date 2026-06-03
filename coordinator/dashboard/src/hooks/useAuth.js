import { useState, useEffect } from 'react';

export const useAuth = () => {
  const [token, setToken] = useState(null);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    // Check localStorage for token on mount
    const storedToken = localStorage.getItem('auth_token');
    if (storedToken) {
      try {
        // Validate token is not expired (basic check)
        const parts = storedToken.split('.');
        if (parts.length === 3) {
          setToken(storedToken);
        }
      } catch (err) {
        localStorage.removeItem('auth_token');
      }
    }
    setLoading(false);
  }, []);

  const login = (newToken) => {
    localStorage.setItem('auth_token', newToken);
    setToken(newToken);
  };

  const logout = () => {
    localStorage.removeItem('auth_token');
    setToken(null);
  };

  return { token, loading, login, logout };
};
