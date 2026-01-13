/**
 * Admin Control Service
 * Manages wallet state and admin controls
 */

const WalletModes = {
  NORMAL: 'normal',
  READ_ONLY: 'read_only',
  PAUSED: 'paused',
};

// In-memory state (in production, use Redis or database)
let walletState = {
  mode: WalletModes.NORMAL,
  message: null,
  updatedAt: new Date(),
  updatedBy: null,
};

const getWalletState = () => {
  return { ...walletState };
};

const setWalletMode = (mode, message = null, updatedBy = 'system') => {
  if (!Object.values(WalletModes).includes(mode)) {
    throw new Error(`Invalid wallet mode: ${mode}`);
  }
  
  walletState = {
    mode,
    message,
    updatedAt: new Date(),
    updatedBy,
  };
  
  console.log(`🔧 Wallet mode changed to: ${mode}${message ? ` - ${message}` : ''}`);
  return walletState;
};

const pauseWallet = (message = 'Wallet paused for maintenance', updatedBy = 'admin') => {
  return setWalletMode(WalletModes.PAUSED, message, updatedBy);
};

const setReadOnly = (message = 'Wallet in read-only mode', updatedBy = 'admin') => {
  return setWalletMode(WalletModes.READ_ONLY, message, updatedBy);
};

const resumeWallet = (updatedBy = 'admin') => {
  return setWalletMode(WalletModes.NORMAL, null, updatedBy);
};

const isWalletActive = () => {
  return walletState.mode === WalletModes.NORMAL;
};

const canWrite = () => {
  return walletState.mode === WalletModes.NORMAL;
};

module.exports = {
  WalletModes,
  getWalletState,
  setWalletMode,
  pauseWallet,
  setReadOnly,
  resumeWallet,
  isWalletActive,
  canWrite,
};
