const express = require('express');
const router = express.Router();
const {
  generateAPIKey,
  getAllKeys,
  revokeKey,
  deleteKey,
} = require('../middleware/auth');

/**
 * Authentication & API Key Management Routes
 */

/**
 * @route   POST /api/auth/keys/generate
 * @desc    Generate a new API key pair
 * @access  Public (in production, this should be admin-protected)
 */
router.post('/keys/generate', (req, res) => {
  try {
    const { description } = req.body;
    
    const keyPair = generateAPIKey();
    
    res.json({
      success: true,
      message: 'API key generated successfully',
      data: {
        apiKey: keyPair.apiKey,
        apiSecret: keyPair.apiSecret,
        description: description || 'No description',
      },
      warning: 'Store the API secret securely. It will not be shown again.',
    });
  } catch (error) {
    console.error('Error generating API key:', error);
    res.status(500).json({
      success: false,
      error: 'Failed to generate API key',
      message: error.message,
    });
  }
});

/**
 * @route   GET /api/auth/keys
 * @desc    Get all API keys (without secrets)
 * @access  Admin only (in production, add admin authentication)
 */
router.get('/keys', (req, res) => {
  try {
    const keys = getAllKeys();
    
    res.json({
      success: true,
      count: keys.length,
      data: keys,
    });
  } catch (error) {
    console.error('Error fetching API keys:', error);
    res.status(500).json({
      success: false,
      error: 'Failed to fetch API keys',
      message: error.message,
    });
  }
});

/**
 * @route   POST /api/auth/keys/:apiKey/revoke
 * @desc    Revoke an API key (deactivate without deleting)
 * @access  Admin only
 */
router.post('/keys/:apiKey/revoke', (req, res) => {
  try {
    const { apiKey } = req.params;
    
    const revoked = revokeKey(apiKey);
    
    if (revoked) {
      res.json({
        success: true,
        message: 'API key revoked successfully',
        apiKey,
      });
    } else {
      res.status(404).json({
        success: false,
        error: 'API key not found',
      });
    }
  } catch (error) {
    console.error('Error revoking API key:', error);
    res.status(500).json({
      success: false,
      error: 'Failed to revoke API key',
      message: error.message,
    });
  }
});

/**
 * @route   DELETE /api/auth/keys/:apiKey
 * @desc    Delete an API key permanently
 * @access  Admin only
 */
router.delete('/keys/:apiKey', (req, res) => {
  try {
    const { apiKey } = req.params;
    
    const deleted = deleteKey(apiKey);
    
    if (deleted) {
      res.json({
        success: true,
        message: 'API key deleted successfully',
        apiKey,
      });
    } else {
      res.status(404).json({
        success: false,
        error: 'API key not found',
      });
    }
  } catch (error) {
    console.error('Error deleting API key:', error);
    res.status(500).json({
      success: false,
      error: 'Failed to delete API key',
      message: error.message,
    });
  }
});

/**
 * @route   GET /api/auth/test
 * @desc    Test authentication (requires valid API key + signature)
 * @access  Protected
 */
router.get('/test', (req, res) => {
  res.json({
    success: true,
    message: 'Authentication successful',
    apiKey: req.apiKey,
    timestamp: new Date().toISOString(),
  });
});

module.exports = router;
