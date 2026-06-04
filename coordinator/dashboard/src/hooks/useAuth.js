import { useState } from 'react';

export const useAuth = () => {
  // Read token synchronously — no useEffect, no async gap.
  // token state is initialised directly from localStorage so it is
  // correct on the very first render (prevents the flash-redirect bug).
  const [token, setToken] = useState(() => localStorage.getItem('token'));

  const isAuthenticated = () => {
    return !!localStorage.getItem('token');
  };

  const login = (newToken) => {
    localStorage.setItem('token', newToken);
    setToken(newToken);
    return true;
  };

  const logout = () => {
    localStorage.removeItem('token');
    setToken(null);
  };

  return { token, isAuthenticated, login, logout };
};
