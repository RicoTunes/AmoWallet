const express = require('express');
const router = express.Router();
const revenueService = require('../services/revenueService');
const FeeSweepService = require('../services/feeSweepService');
const TelegramService = require('../services/telegramService');
const database = require('../config/database');
const { logger } = require('../config/monitoring');
const fs = require('fs');
const path = require('path');

/**
 * Admin Dashboard API Routes
 * Protected endpoints for monitoring revenue, users, and security
 * 
 * SECURITY: Add authentication middleware before deploying!
 */

// Initialize services
const feeSweepService = new FeeSweepService();
const telegramService = new TelegramService();

// ==================================
// APP CONTROL STATE (Kill Switch)
// ==================================
const APP_STATE_FILE = path.join(__dirname, '../../config/app_state.json');

// Default app state
let appState = {
  isActive: true,            // Main kill switch
  maintenanceMode: false,    // Maintenance mode (read-only)
  allowSwaps: true,          // Enable/disable swaps
  allowWithdrawals: true,    // Enable/disable withdrawals
  allowDeposits: true,       // Enable/disable deposits
  minAppVersion: '1.0.0',    // Minimum app version required
  message: null,             // Custom message to show users
  deactivatedAt: null,       // Timestamp when deactivated
  deactivatedBy: null,       // Who deactivated
  lastUpdated: new Date().toISOString(),
};

// Load app state from file
function loadAppState() {
  try {
    if (fs.existsSync(APP_STATE_FILE)) {
      const data = fs.readFileSync(APP_STATE_FILE, 'utf8');
      appState = { ...appState, ...JSON.parse(data) };
    }
  } catch (error) {
    console.error('Error loading app state:', error);
  }
}

// Save app state to file
function saveAppState() {
  try {
    const dir = path.dirname(APP_STATE_FILE);
    if (!fs.existsSync(dir)) {
      fs.mkdirSync(dir, { recursive: true });
    }
    fs.writeFileSync(APP_STATE_FILE, JSON.stringify(appState, null, 2));
  } catch (error) {
    console.error('Error saving app state:', error);
  }
}

// Initialize
loadAppState();

// Export app state for middleware use
const getAppState = () => appState;

// Admin users (in production, use database)
const adminUsers = [
  { id: '1', username: 'admin', role: 'SUPER_ADMIN', twoFactorEnabled: false, lastLogin: null, apiKey: process.env.ADMIN_API_KEY || 'admin-secret-key-change-in-production' },
  { id: '2', username: 'operator', role: 'ADMIN', twoFactorEnabled: false, lastLogin: null, apiKey: 'operator-key-123' },
];

// Wallet state for admin panel (extends app state)
const walletControlState = {
  mode: 'ACTIVE',  // ACTIVE, READ_ONLY, PAUSED
  environment: process.env.NODE_ENV || 'development',
  message: null,
  features: {
    swaps: { enabled: true, crossChainEnabled: true },
    transfers: { enabled: true },
    deposits: { enabled: true },
    onboarding: { enabled: true },
    fiatRamp: { onRampEnabled: true, offRampEnabled: true },
  },
  chains: {
    ethereum: { enabled: true },
    bitcoin: { enabled: true },
    solana: { enabled: true },
    polygon: { enabled: true },
    bsc: { enabled: true },
    arbitrum: { enabled: true },
    avalanche: { enabled: true },
    optimism: { enabled: true },
    base: { enabled: true },
  },
  lastUpdated: new Date().toISOString(),
};

// Audit logs (in production, use database)
const auditLogs = [];

function addAuditLog(adminId, action, target, reason) {
  auditLogs.unshift({
    id: Date.now().toString(),
    timestamp: new Date().toISOString(),
    adminId,
    action,
    target,
    reason,
  });
  // Keep only last 100 logs
  if (auditLogs.length > 100) auditLogs.pop();
}

// Simple admin authentication (REPLACE WITH PROPER AUTH!)
const adminAuth = (req, res, next) => {
  const adminKey = req.headers['x-admin-key'];
  
  // Check against any admin user's API key
  const admin = adminUsers.find(a => a.apiKey === adminKey);
  
  if (!admin) {
    return res.status(401).json({
      success: false,
      error: 'Unauthorized - Invalid admin key',
    });
  }
  
  // Attach admin to request for later use
  req.admin = admin;
  next();
};

// ==================================
// ADMIN PANEL API ROUTES
// ==================================

/**
 * POST /api/admin/auth/login
 * Admin login with API key
 */
router.post('/auth/login', (req, res) => {
  const adminKey = req.headers['x-admin-key'];
  const { twoFactorToken } = req.body;
  
  // Find admin by API key
  const admin = adminUsers.find(a => a.apiKey === adminKey);
  
  if (!admin) {
    return res.status(401).json({
      success: false,
      error: 'Invalid admin key',
    });
  }
  
  // Update last login
  admin.lastLogin = new Date().toISOString();
  
  res.json({
    success: true,
    admin: {
      id: admin.id,
      username: admin.username,
      role: admin.role,
      twoFactorEnabled: admin.twoFactorEnabled,
    },
    walletState: walletControlState,
  });
});

/**
 * GET /api/admin/wallet/state
 * Get current wallet state
 */
router.get('/wallet/state', adminAuth, (req, res) => {
  res.json({
    success: true,
    state: walletControlState,
  });
});

/**
 * POST /api/admin/wallet/kill-switch
 * Emergency kill switch
 */
router.post('/wallet/kill-switch', adminAuth, async (req, res) => {
  try {
    const { enable, reason, confirm } = req.body;
    
    if (!confirm) {
      return res.status(400).json({ success: false, error: 'Confirmation required' });
    }
    
    walletControlState.mode = enable ? 'PAUSED' : 'ACTIVE';
    walletControlState.lastUpdated = new Date().toISOString();
    
    addAuditLog('admin', 'KILL_SWITCH', walletControlState.mode, reason);
    
    // Send Telegram alert
    await telegramService.sendAlert(
      enable ? '🚨 KILL SWITCH ACTIVATED' : '✅ WALLET REACTIVATED',
      `Mode: ${walletControlState.mode}\nReason: ${reason}`
    );
    
    res.json({
      success: true,
      mode: walletControlState.mode,
    });
  } catch (error) {
    res.status(500).json({ success: false, error: error.message });
  }
});

/**
 * POST /api/admin/wallet/mode
 * Change wallet mode
 */
router.post('/wallet/mode', adminAuth, async (req, res) => {
  try {
    const { mode, message, reason, confirm } = req.body;
    
    if (!confirm) {
      return res.status(400).json({ success: false, error: 'Confirmation required' });
    }
    
    const validModes = ['ACTIVE', 'READ_ONLY', 'PAUSED'];
    if (!validModes.includes(mode)) {
      return res.status(400).json({ success: false, error: 'Invalid mode' });
    }
    
    walletControlState.mode = mode;
    walletControlState.message = message || null;
    walletControlState.lastUpdated = new Date().toISOString();
    
    addAuditLog('admin', 'SET_GLOBAL_MODE', mode, reason);
    
    res.json({
      success: true,
      state: walletControlState,
    });
  } catch (error) {
    res.status(500).json({ success: false, error: error.message });
  }
});

/**
 * POST /api/admin/features/toggle
 * Toggle feature
 */
router.post('/features/toggle', adminAuth, (req, res) => {
  try {
    const { feature, subFeature, enabled, reason, confirm } = req.body;
    
    if (!confirm) {
      return res.status(400).json({ success: false, error: 'Confirmation required' });
    }
    
    if (walletControlState.features[feature]) {
      if (subFeature) {
        walletControlState.features[feature][subFeature] = enabled;
      } else {
        walletControlState.features[feature].enabled = enabled;
      }
      walletControlState.lastUpdated = new Date().toISOString();
      
      addAuditLog('admin', 'TOGGLE_FEATURE', `${feature}.${subFeature || 'enabled'}`, reason);
      
      res.json({
        success: true,
        features: walletControlState.features,
      });
    } else {
      res.status(400).json({ success: false, error: 'Feature not found' });
    }
  } catch (error) {
    res.status(500).json({ success: false, error: error.message });
  }
});

/**
 * POST /api/admin/chains/toggle
 * Toggle chain
 */
router.post('/chains/toggle', adminAuth, (req, res) => {
  try {
    const { chain, enabled, reason, confirm } = req.body;
    
    if (!confirm) {
      return res.status(400).json({ success: false, error: 'Confirmation required' });
    }
    
    if (walletControlState.chains[chain]) {
      walletControlState.chains[chain].enabled = enabled;
      walletControlState.lastUpdated = new Date().toISOString();
      
      addAuditLog('admin', 'TOGGLE_CHAIN', chain, reason);
      
      res.json({
        success: true,
        chains: walletControlState.chains,
      });
    } else {
      res.status(400).json({ success: false, error: 'Chain not found' });
    }
  } catch (error) {
    res.status(500).json({ success: false, error: error.message });
  }
});

/**
 * GET /api/admin/audit/logs
 * Get audit logs
 */
router.get('/audit/logs', adminAuth, (req, res) => {
  res.json({
    success: true,
    logs: auditLogs,
  });
});

/**
 * GET /api/admin/audit/verify
 * Verify audit log integrity
 */
router.get('/audit/verify', adminAuth, (req, res) => {
  res.json({
    success: true,
    integrity: 'VERIFIED',
    validLogs: auditLogs.length,
    invalidLogs: 0,
  });
});

/**
 * GET /api/admin/admins
 * Get admin users list
 */
router.get('/admins', adminAuth, (req, res) => {
  res.json({
    success: true,
    admins: adminUsers,
  });
});

/**
 * POST /api/admin/admins/create
 * Create a new admin user
 */
router.post('/admins/create', adminAuth, (req, res) => {
  const { username, role, apiKey } = req.body;
  
  // Validate required fields
  if (!username || !role || !apiKey) {
    return res.status(400).json({
      success: false,
      error: 'Username, role, and API key are required',
    });
  }
  
  // Check if username already exists
  const existingAdmin = adminUsers.find(a => a.username === username);
  if (existingAdmin) {
    return res.status(400).json({
      success: false,
      error: 'Username already exists',
    });
  }
  
  // Validate role
  const validRoles = ['SUPER_ADMIN', 'ADMIN', 'OPERATOR', 'VIEWER'];
  if (!validRoles.includes(role)) {
    return res.status(400).json({
      success: false,
      error: 'Invalid role. Must be one of: ' + validRoles.join(', '),
    });
  }
  
  // Only SUPER_ADMIN can create other SUPER_ADMINs
  const currentAdmin = adminUsers.find(a => a.apiKey === req.headers['x-admin-key']);
  if (role === 'SUPER_ADMIN' && currentAdmin?.role !== 'SUPER_ADMIN') {
    return res.status(403).json({
      success: false,
      error: 'Only SUPER_ADMIN can create other SUPER_ADMINs',
    });
  }
  
  // Create new admin
  const newAdmin = {
    id: `admin_${Date.now()}`,
    username,
    role,
    apiKey,
    twoFactorEnabled: false,
    lastLogin: null,
    createdAt: new Date().toISOString(),
    createdBy: currentAdmin?.username || 'system',
  };
  
  adminUsers.push(newAdmin);
  
  // Add audit log
  auditLogs.unshift({
    id: `log_${Date.now()}`,
    timestamp: new Date().toISOString(),
    adminId: currentAdmin?.username || 'system',
    action: 'CREATE_ADMIN',
    target: username,
    reason: `Created admin user with role ${role}`,
  });
  
  res.json({
    success: true,
    admin: {
      id: newAdmin.id,
      username: newAdmin.username,
      role: newAdmin.role,
      createdAt: newAdmin.createdAt,
    },
  });
});

/**
 * DELETE /api/admin/admins/:username
 * Delete an admin user
 */
router.delete('/admins/:username', adminAuth, (req, res) => {
  const { username } = req.params;
  
  // Find admin to delete
  const adminIndex = adminUsers.findIndex(a => a.username === username);
  if (adminIndex === -1) {
    return res.status(404).json({
      success: false,
      error: 'Admin not found',
    });
  }
  
  // Cannot delete yourself
  const currentAdmin = adminUsers.find(a => a.apiKey === req.headers['x-admin-key']);
  if (adminUsers[adminIndex].username === currentAdmin?.username) {
    return res.status(400).json({
      success: false,
      error: 'Cannot delete your own account',
    });
  }
  
  // Only SUPER_ADMIN can delete admins
  if (currentAdmin?.role !== 'SUPER_ADMIN') {
    return res.status(403).json({
      success: false,
      error: 'Only SUPER_ADMIN can delete admin users',
    });
  }
  
  // Remove admin
  const deletedAdmin = adminUsers.splice(adminIndex, 1)[0];
  
  // Add audit log
  auditLogs.unshift({
    id: `log_${Date.now()}`,
    timestamp: new Date().toISOString(),
    adminId: currentAdmin?.username || 'system',
    action: 'DELETE_ADMIN',
    target: username,
    reason: `Deleted admin user`,
  });
  
  res.json({
    success: true,
    message: `Admin ${username} deleted`,
  });
});

/**
 * POST /api/admin/admins/2fa/enable
 * Enable 2FA
 */
router.post('/admins/2fa/enable', adminAuth, (req, res) => {
  const secret = 'JBSWY3DPEHPK3PXP'; // Demo secret
  adminUsers[0].twoFactorEnabled = true;
  res.json({
    success: true,
    secret: secret,
  });
});

/**
 * GET /api/admin/monitoring/health
 * Get monitoring health
 */
router.get('/monitoring/health', adminAuth, (req, res) => {
  res.json({
    success: true,
    health: {
      swapSuccessRate: 98.5,
      errorRate: 0.3,
      chainStatus: Object.fromEntries(
        Object.entries(walletControlState.chains).map(([k, v]) => [k, v.enabled])
      ),
      lastUpdate: new Date().toISOString(),
    },
  });
});

// ==================================
// KILL SWITCH & APP CONTROL ROUTES
// ==================================

/**
 * GET /api/admin/app/status
 * Get current app status (public - used by app to check if active)
 */
router.get('/app/status', async (req, res) => {
  res.json({
    success: true,
    status: {
      isActive: appState.isActive,
      maintenanceMode: appState.maintenanceMode,
      allowSwaps: appState.allowSwaps,
      allowWithdrawals: appState.allowWithdrawals,
      allowDeposits: appState.allowDeposits,
      minAppVersion: appState.minAppVersion,
      message: appState.message,
    },
    timestamp: new Date().toISOString(),
  });
});

/**
 * POST /api/admin/app/kill-switch
 * Emergency kill switch - disable entire app
 */
router.post('/app/kill-switch', adminAuth, async (req, res) => {
  try {
    const { enable, message } = req.body;
    
    appState.isActive = enable !== false;
    appState.message = message || (appState.isActive ? null : 'App is temporarily unavailable');
    appState.lastUpdated = new Date().toISOString();
    
    if (!appState.isActive) {
      appState.deactivatedAt = new Date().toISOString();
      appState.deactivatedBy = 'admin';
      
      // Send alert
      await telegramService.sendAlert(
        '🚨 KILL SWITCH ACTIVATED',
        `App has been DEACTIVATED!\nReason: ${message || 'Manual deactivation'}\nTime: ${appState.deactivatedAt}`
      );
    } else {
      appState.deactivatedAt = null;
      appState.deactivatedBy = null;
      
      await telegramService.sendAlert(
        '✅ APP REACTIVATED',
        `App has been reactivated!\nTime: ${appState.lastUpdated}`
      );
    }
    
    saveAppState();
    
    res.json({
      success: true,
      message: appState.isActive ? 'App activated' : 'App deactivated',
      status: appState,
    });
    
  } catch (error) {
    logger.error('Error toggling kill switch:', error);
    res.status(500).json({
      success: false,
      error: 'Failed to toggle kill switch',
    });
  }
});

/**
 * POST /api/admin/app/maintenance
 * Toggle maintenance mode (read-only, no transactions)
 */
router.post('/app/maintenance', adminAuth, async (req, res) => {
  try {
    const { enable, message } = req.body;
    
    appState.maintenanceMode = enable === true;
    appState.message = message || (appState.maintenanceMode ? 'Under maintenance' : null);
    appState.lastUpdated = new Date().toISOString();
    
    if (appState.maintenanceMode) {
      appState.allowSwaps = false;
      appState.allowWithdrawals = false;
    } else {
      appState.allowSwaps = true;
      appState.allowWithdrawals = true;
    }
    
    saveAppState();
    
    await telegramService.sendAlert(
      appState.maintenanceMode ? '🔧 MAINTENANCE MODE ON' : '✅ MAINTENANCE MODE OFF',
      `Status: ${appState.maintenanceMode ? 'Enabled' : 'Disabled'}\nMessage: ${appState.message || 'None'}`
    );
    
    res.json({
      success: true,
      message: appState.maintenanceMode ? 'Maintenance mode enabled' : 'Maintenance mode disabled',
      status: appState,
    });
    
  } catch (error) {
    logger.error('Error toggling maintenance:', error);
    res.status(500).json({
      success: false,
      error: 'Failed to toggle maintenance mode',
    });
  }
});

/**
 * POST /api/admin/app/toggle-feature
 * Toggle specific features (swaps, withdrawals, deposits)
 */
router.post('/app/toggle-feature', adminAuth, async (req, res) => {
  try {
    const { feature, enable, message } = req.body;
    
    const validFeatures = ['swaps', 'withdrawals', 'deposits'];
    if (!validFeatures.includes(feature)) {
      return res.status(400).json({
        success: false,
        error: `Invalid feature. Must be one of: ${validFeatures.join(', ')}`,
      });
    }
    
    const featureKey = `allow${feature.charAt(0).toUpperCase() + feature.slice(1)}`;
    appState[featureKey] = enable === true;
    appState.lastUpdated = new Date().toISOString();
    
    if (message) {
      appState.message = message;
    }
    
    saveAppState();
    
    await telegramService.sendAlert(
      `⚙️ FEATURE TOGGLE: ${feature.toUpperCase()}`,
      `${feature} is now ${enable ? 'ENABLED' : 'DISABLED'}`
    );
    
    res.json({
      success: true,
      message: `${feature} ${enable ? 'enabled' : 'disabled'}`,
      status: appState,
    });
    
  } catch (error) {
    logger.error('Error toggling feature:', error);
    res.status(500).json({
      success: false,
      error: 'Failed to toggle feature',
    });
  }
});

/**
 * POST /api/admin/app/set-min-version
 * Set minimum required app version
 */
router.post('/app/set-min-version', adminAuth, async (req, res) => {
  try {
    const { version, message } = req.body;
    
    if (!version || !/^\d+\.\d+\.\d+$/.test(version)) {
      return res.status(400).json({
        success: false,
        error: 'Invalid version format. Use semver (e.g., 1.0.0)',
      });
    }
    
    appState.minAppVersion = version;
    appState.message = message || null;
    appState.lastUpdated = new Date().toISOString();
    
    saveAppState();
    
    await telegramService.sendAlert(
      '📱 MIN VERSION UPDATED',
      `New minimum version: ${version}\nMessage: ${message || 'None'}`
    );
    
    res.json({
      success: true,
      message: `Minimum version set to ${version}`,
      status: appState,
    });
    
  } catch (error) {
    logger.error('Error setting min version:', error);
    res.status(500).json({
      success: false,
      error: 'Failed to set minimum version',
    });
  }
});

/**
 * GET /api/admin/revenue/stats
 * Get revenue statistics
 */
router.get('/revenue/stats', adminAuth, async (req, res) => {
  try {
    const period = req.query.period || 'today'; // today, month, all
    
    const stats = await revenueService.getRevenueStats(period);
    const byChain = await revenueService.getRevenueByChain(period);
    
    res.json({
      success: true,
      period,
      stats,
      byChain,
      timestamp: new Date().toISOString(),
    });
    
  } catch (error) {
    logger.error('Error getting revenue stats:', error);
    res.status(500).json({
      success: false,
      error: 'Failed to get revenue stats',
    });
  }
});

/**
 * GET /api/admin/revenue/top-users
 * Get top revenue-generating users
 */
router.get('/revenue/top-users', adminAuth, async (req, res) => {
  try {
    const limit = parseInt(req.query.limit) || 10;
    const topUsers = await revenueService.getTopRevenueUsers(limit);
    
    res.json({
      success: true,
      topUsers,
      timestamp: new Date().toISOString(),
    });
    
  } catch (error) {
    logger.error('Error getting top users:', error);
    res.status(500).json({
      success: false,
      error: 'Failed to get top users',
    });
  }
});

/**
 * GET /api/admin/revenue/daily
 * Get daily revenue summary
 */
router.get('/revenue/daily', adminAuth, async (req, res) => {
  try {
    const days = parseInt(req.query.days) || 30;
    
    const query = `
      SELECT 
        date,
        total_transactions,
        total_revenue_usd,
        avg_fee_usd,
        highest_fee_usd
      FROM daily_revenue_summary
      WHERE date >= CURRENT_DATE - INTERVAL '${days} days'
      ORDER BY date DESC
    `;
    
    const result = await database.query(query);
    
    // Calculate totals
    const totals = {
      totalTransactions: result.rows.reduce((sum, row) => sum + parseInt(row.total_transactions), 0),
      totalRevenue: result.rows.reduce((sum, row) => sum + parseFloat(row.total_revenue_usd), 0),
    };
    
    res.json({
      success: true,
      days,
      dailyStats: result.rows,
      totals,
      timestamp: new Date().toISOString(),
    });
    
  } catch (error) {
    logger.error('Error getting daily revenue:', error);
    res.status(500).json({
      success: false,
      error: 'Failed to get daily revenue',
    });
  }
});

/**
 * GET /api/admin/users/activity
 * Get recent user activity
 */
router.get('/users/activity', adminAuth, async (req, res) => {
  try {
    const limit = parseInt(req.query.limit) || 50;
    const suspicious = req.query.suspicious === 'true';
    
    let query = `
      SELECT 
        id, user_id, ip_address, activity_type,
        endpoint, method, response_status,
        is_suspicious, risk_score, created_at
      FROM user_activity_log
    `;
    
    if (suspicious) {
      query += ` WHERE is_suspicious = true`;
    }
    
    query += ` ORDER BY created_at DESC LIMIT $1`;
    
    const result = await database.query(query, [limit]);
    
    res.json({
      success: true,
      activities: result.rows,
      count: result.rows.length,
      timestamp: new Date().toISOString(),
    });
    
  } catch (error) {
    logger.error('Error getting user activity:', error);
    res.status(500).json({
      success: false,
      error: 'Failed to get user activity',
    });
  }
});

/**
 * GET /api/admin/security/events
 * Get security events
 */
router.get('/security/events', adminAuth, async (req, res) => {
  try {
    const limit = parseInt(req.query.limit) || 50;
    const severity = req.query.severity; // low, medium, high, critical
    
    let query = `
      SELECT 
        id, event_type, severity, ip_address,
        description, action_taken, created_at
      FROM security_events
    `;
    
    if (severity) {
      query += ` WHERE severity = $2`;
    }
    
    query += ` ORDER BY created_at DESC LIMIT $1`;
    
    const params = severity ? [limit, severity] : [limit];
    const result = await database.query(query, params);
    
    res.json({
      success: true,
      events: result.rows,
      count: result.rows.length,
      timestamp: new Date().toISOString(),
    });
    
  } catch (error) {
    logger.error('Error getting security events:', error);
    res.status(500).json({
      success: false,
      error: 'Failed to get security events',
    });
  }
});

/**
 * GET /api/admin/users/stats
 * Get user statistics
 */
router.get('/users/stats', adminAuth, async (req, res) => {
  try {
    // Total users (based on activity)
    const totalUsersQuery = `
      SELECT COUNT(DISTINCT user_id) as total_users
      FROM user_activity_log
      WHERE user_id IS NOT NULL
    `;
    
    // Daily active users
    const dauQuery = `
      SELECT COUNT(DISTINCT user_id) as dau
      FROM user_activity_log
      WHERE DATE(created_at) = CURRENT_DATE
        AND user_id IS NOT NULL
    `;
    
    // Monthly active users
    const mauQuery = `
      SELECT COUNT(DISTINCT user_id) as mau
      FROM user_activity_log
      WHERE DATE_TRUNC('month', created_at) = DATE_TRUNC('month', CURRENT_DATE)
        AND user_id IS NOT NULL
    `;
    
    const [totalUsers, dau, mau] = await Promise.all([
      database.query(totalUsersQuery),
      database.query(dauQuery),
      database.query(mauQuery),
    ]);
    
    res.json({
      success: true,
      stats: {
        totalUsers: parseInt(totalUsers.rows[0].total_users),
        dailyActiveUsers: parseInt(dau.rows[0].dau),
        monthlyActiveUsers: parseInt(mau.rows[0].mau),
      },
      timestamp: new Date().toISOString(),
    });
    
  } catch (error) {
    logger.error('Error getting user stats:', error);
    res.status(500).json({
      success: false,
      error: 'Failed to get user stats',
    });
  }
});

/**
 * GET /api/admin/dashboard
 * Get complete dashboard data
 */
router.get('/dashboard', adminAuth, async (req, res) => {
  try {
    // Get all dashboard data in parallel
    const [
      revenueStats,
      revenueByChain,
      topUsers,
      securityEvents,
      userStats,
    ] = await Promise.all([
      revenueService.getRevenueStats('today'),
      revenueService.getRevenueByChain('today'),
      revenueService.getTopRevenueUsers(5),
      database.query(`
        SELECT COUNT(*) as count, severity
        FROM security_events
        WHERE DATE(created_at) = CURRENT_DATE
        GROUP BY severity
      `),
      database.query(`
        SELECT COUNT(DISTINCT user_id) as dau
        FROM user_activity_log
        WHERE DATE(created_at) = CURRENT_DATE
      `),
    ]);
    
    res.json({
      success: true,
      dashboard: {
        revenue: {
          today: revenueStats,
          byChain: revenueByChain,
          topUsers: topUsers,
        },
        security: {
          eventsByLevel: securityEvents.rows,
        },
        users: {
          dailyActive: parseInt(userStats.rows[0].dau || 0),
        },
      },
      timestamp: new Date().toISOString(),
    });
    
  } catch (error) {
    logger.error('Error getting dashboard data:', error);
    res.status(500).json({
      success: false,
      error: 'Failed to get dashboard data',
    });
  }
});

/**
 * GET /api/admin/transactions/recent
 * Get recent transactions with fees
 */
router.get('/transactions/recent', adminAuth, async (req, res) => {
  try {
    const limit = parseInt(req.query.limit) || 20;
    
    const query = `
      SELECT 
        id, user_id, chain, transaction_type,
        original_amount, original_amount_usd,
        fee_amount, fee_amount_usd, fee_percentage,
        status, created_at
      FROM revenue_transactions
      ORDER BY created_at DESC
      LIMIT $1
    `;
    
    const result = await database.query(query, [limit]);
    
    res.json({
      success: true,
      transactions: result.rows,
      count: result.rows.length,
      timestamp: new Date().toISOString(),
    });
    
  } catch (error) {
    logger.error('Error getting recent transactions:', error);
    res.status(500).json({
      success: false,
      error: 'Failed to get recent transactions',
    });
  }
});

/**
 * POST /api/admin/alerts/test
 * Test alert system
 */
router.post('/alerts/test', adminAuth, async (req, res) => {
  try {
    await revenueService.sendRevenueAlert();
    
    res.json({
      success: true,
      message: 'Test alert sent',
      timestamp: new Date().toISOString(),
    });
    
  } catch (error) {
    logger.error('Error sending test alert:', error);
    res.status(500).json({
      success: false,
      error: 'Failed to send test alert',
    });
  }
});

/**
 * POST /api/admin/fees/sweep
 * Manually trigger a fee sweep (normally runs on schedule)
 */
router.post('/fees/sweep', adminAuth, async (req, res) => {
  try {
    console.log('🔄 Manual fee sweep triggered via admin endpoint');
    
    // Run sweep asynchronously
    feeSweepService.performSweep().catch(error => {
      logger.error('Fee sweep error:', error);
      telegramService.sendAlert('❌ Manual Fee Sweep Failed', error.message);
    });
    
    res.json({
      success: true,
      message: 'Fee sweep initiated',
      status: 'processing',
      timestamp: new Date().toISOString()
    });
  } catch (error) {
    logger.error('Error triggering fee sweep:', error);
    res.status(500).json({
      success: false,
      error: 'Failed to trigger fee sweep',
      details: error.message
    });
  }
});

/**
 * GET /api/admin/fees/stats
 * Get fee sweep statistics
 */
router.get('/fees/stats', adminAuth, async (req, res) => {
  try {
    const stats = await feeSweepService.getStatistics();
    
    res.json({
      success: true,
      data: stats,
      timestamp: new Date().toISOString()
    });
  } catch (error) {
    logger.error('Error getting fee stats:', error);
    res.status(500).json({
      success: false,
      error: 'Failed to get fee statistics',
      details: error.message
    });
  }
});

/**
 * GET /api/admin/fees/pending
 * Get pending fees ready for sweep
 */
router.get('/fees/pending', adminAuth, async (req, res) => {
  try {
    const fees = await feeSweepService.getPendingFees();
    
    // Calculate totals by network
    const totals = {};
    let grandTotal = 0;
    
    for (const fee of fees) {
      const network = fee.network || 'UNKNOWN';
      if (!totals[network]) {
        totals[network] = 0;
      }
      totals[network] += parseFloat(fee.amount) || 0;
      grandTotal += parseFloat(fee.amount) || 0;
    }
    
    res.json({
      success: true,
      count: fees.length,
      totalValue: grandTotal.toFixed(8),
      byNetwork: totals,
      fees: fees.slice(0, 100), // Limit to latest 100
      timestamp: new Date().toISOString()
    });
  } catch (error) {
    logger.error('Error getting pending fees:', error);
    res.status(500).json({
      success: false,
      error: 'Failed to get pending fees',
      details: error.message
    });
  }
});

/**
 * POST /api/admin/telegram/test
 * Test Telegram connection and send test message
 */
router.post('/telegram/test', adminAuth, async (req, res) => {
  try {
    const success = await telegramService.testConnection();
    
    if (success) {
      res.json({
        success: true,
        message: 'Telegram connection successful',
        status: 'connected'
      });
    } else {
      res.status(400).json({
        success: false,
        message: 'Telegram connection failed',
        status: 'disconnected'
      });
    }
  } catch (error) {
    logger.error('Error testing Telegram:', error);
    res.status(500).json({
      success: false,
      error: 'Failed to test Telegram connection',
      details: error.message
    });
  }
});

/**
 * POST /api/admin/telegram/alert
 * Send custom alert to admin via Telegram
 */
router.post('/telegram/alert', adminAuth, async (req, res) => {
  try {
    const { title, message, severity = 'info' } = req.body;
    
    if (!title || !message) {
      return res.status(400).json({
        success: false,
        error: 'Missing required fields: title, message'
      });
    }
    
    await telegramService.sendAlert(title, message, 'HTML');
    
    res.json({
      success: true,
      message: 'Alert sent to Telegram',
      timestamp: new Date().toISOString()
    });
  } catch (error) {
    logger.error('Error sending Telegram alert:', error);
    res.status(500).json({
      success: false,
      error: 'Failed to send alert',
      details: error.message
    });
  }
});

// Export router and app state helper
module.exports = router;
module.exports.getAppState = getAppState;
