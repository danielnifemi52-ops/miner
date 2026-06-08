import { useState, useEffect } from 'react';
import { useAuth } from '../hooks/useAuth';
import { useWorkers } from '../hooks/useWorkers';
import { useRealtime } from '../hooks/useRealtime';
import WorkerCard from '../components/WorkerCard';
import HashrateChart from '../components/HashrateChart';
import { useNavigate } from 'react-router-dom';
import { apiClient } from '../utils/api';
import './Dashboard.css';

function Dashboard() {
  const { logout } = useAuth();
  const { workers, loading, error, refetch } = useWorkers();
  // Pass refetch so realtime worker INSERT/UPDATE triggers an immediate list refresh
  const { stats, connected } = useRealtime(refetch);
  const navigate = useNavigate();

  const [config, setConfig] = useState(null);
  const [newWallet, setNewWallet] = useState('');
  const [saveStatus, setSaveStatus] = useState({ type: '', message: '' });
  const [saving, setSaving] = useState(false);

  useEffect(() => {
    const fetchConfig = async () => {
      try {
        const response = await apiClient.get('/api/config');
        setConfig(response.data);
      } catch (err) {
        console.error('Failed to fetch config:', err);
      }
    };
    fetchConfig();
  }, []);

  const maskWallet = (wallet) => {
    if (!wallet) return 'Not set';
    if (wallet.length <= 10) return wallet;
    return `${wallet.substring(0, 6)}***${wallet.substring(wallet.length - 4)}`;
  };

  const handleSaveWallet = async (e) => {
    e.preventDefault();
    if (!newWallet.trim()) return;
    setSaving(true);
    setSaveStatus({ type: '', message: '' });
    try {
      await apiClient.patch('/api/config', { key: 'wallet', value: newWallet.trim() });
      setConfig(prev => ({ ...prev, wallet: newWallet.trim() }));
      setNewWallet('');
      setSaveStatus({ type: 'success', message: 'Wallet updated successfully!' });
    } catch (err) {
      console.error('Failed to save wallet:', err);
      setSaveStatus({
        type: 'error',
        message: err.response?.data?.error || 'Failed to update wallet'
      });
    } finally {
      setSaving(false);
    }
  };

  const handleLogout = () => {
    logout();
    navigate('/login');
  };

  const totalHashrate = Object.values(stats).reduce(
    (sum, s) => sum + (s.hashrate || 0),
    0
  );

  // Debug: log workers array on every render
  console.log('[Dashboard] render — workers:', workers.length, workers, 'loading:', loading, 'error:', error);

  if (loading) {
    return <div className="dashboard loading">Loading workers…</div>;
  }

  return (
    <div className="dashboard">
      <header className="dashboard-header">
        <div className="header-left">
          <h1>⛏ Mining Dashboard</h1>
          <span className={`status-indicator ${connected ? 'connected' : 'disconnected'}`}>
            {connected ? '● Connected' : '● Disconnected'}
          </span>
        </div>
        <button onClick={handleLogout} className="logout-btn">
          Logout
        </button>
      </header>

      {error && <div className="error-banner">{error}</div>}

      <div className="stats-summary">
        <div className="stat-card">
          <div className="stat-label">Total Workers</div>
          <div className="stat-value">{workers.length}</div>
        </div>
        <div className="stat-card">
          <div className="stat-label">Network Hashrate</div>
          <div className="stat-value">{totalHashrate.toFixed(2)} H/s</div>
        </div>
        <div className="stat-card">
          <div className="stat-label">Realtime Status</div>
          <div className="stat-value">{connected ? '✓ Live' : '✗ Offline'}</div>
        </div>
      </div>

      <div className="workers-section">
        <h2>Active Workers</h2>
        {!Array.isArray(workers) || workers.length === 0 ? (
          <p className="no-workers">No workers registered yet</p>
        ) : (
          <div className="workers-grid">
            {workers.map((worker) => (
              <WorkerCard
                key={worker.id}
                worker={worker}
                stats={stats[worker.id]}
              />
            ))}
          </div>
        )}
      </div>

      <div className="chart-section">
        <h2>Network Hashrate History</h2>
        <HashrateChart workers={workers} stats={stats} />
      </div>

      <div className="settings-section">
        <h2>Settings</h2>
        <form onSubmit={handleSaveWallet} className="settings-form">
          <div className="form-group">
            <label htmlFor="wallet">XMR Wallet Address</label>
            <div className="current-wallet-display">
              Current Wallet: {maskWallet(config?.wallet)}
            </div>
            <input
              id="wallet"
              type="text"
              placeholder="Enter new Monero wallet address"
              value={newWallet}
              onChange={(e) => setNewWallet(e.target.value)}
              disabled={saving}
              required
            />
          </div>
          {saveStatus.message && (
            <div className={`status-message ${saveStatus.type}`}>
              {saveStatus.message}
            </div>
          )}
          <button type="submit" disabled={saving || !newWallet.trim()}>
            {saving ? 'Saving...' : 'Save Wallet'}
          </button>
        </form>
      </div>
    </div>
  );
}

export default Dashboard;
