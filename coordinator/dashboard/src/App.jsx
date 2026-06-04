import { createBrowserRouter, RouterProvider, Navigate } from 'react-router-dom';
import Login from './pages/Login';
import Dashboard from './pages/Dashboard';

const ProtectedRoute = ({ element }) => {
  const token = localStorage.getItem('token');
  return token ? element : <Navigate to="/login" replace />;
};

const router = createBrowserRouter([
  {
    path: '/login',
    element: <Login />,
  },
  {
    path: '/dashboard',
    element: <ProtectedRoute element={<Dashboard />} />,
  },
  {
    path: '/',
    element: <Navigate to="/dashboard" replace />,
  },
]);

function App() {
  return <RouterProvider router={router} />;
}

export default App;
