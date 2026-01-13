const express = require('express');
const router = express.Router();
const axios = require('axios');
const { apiLimiter } = require('../middleware/rateLimiter');

const RUST_SERVER = process.env.RUST_SERVER_URL || 'http://127.0.0.1:8443';

/**
 * @route   POST /api/spending/check
 * @desc    Check if transaction is allowed based on spending limits
 * @access  Public (should be authenticated in production)
 * @body    { address: string, amount: number }
 */
router.post('/check', apiLimiter, async (req, res) => {
    try {
        const { address, amount } = req.body;

        if (!address || amount === undefined) {
            return res.status(400).json({
                success: false,
                error: 'Address and amount are required'
            });
        }

        if (typeof amount !== 'number' || amount <= 0) {
            return res.status(400).json({
                success: false,
                error: 'Amount must be a positive number'
            });
        }

        // Forward to Rust server
        const response = await axios.post(`${RUST_SERVER}/api/spending/check`, {
            address,
            amount
        });

        res.json(response.data);
    } catch (error) {
        console.error('Error checking spending limits:', error.message);
        res.status(500).json({
            success: false,
            error: 'Failed to check spending limits'
        });
    }
});

/**
 * @route   POST /api/spending/record
 * @desc    Record a transaction for velocity tracking
 * @access  Public (should be authenticated in production)
 * @body    { address, amount, currency, timestamp, tx_hash, status }
 */
router.post('/record', apiLimiter, async (req, res) => {
    try {
        const { address, amount, currency, tx_hash, status } = req.body;

        if (!address || amount === undefined) {
            return res.status(400).json({
                success: false,
                error: 'Address and amount are required'
            });
        }

        const transaction = {
            address,
            amount,
            currency: currency || 'USD',
            timestamp: Math.floor(Date.now() / 1000),
            tx_hash: tx_hash || null,
            status: status || 'Confirmed'
        };

        // Forward to Rust server
        const response = await axios.post(`${RUST_SERVER}/api/spending/record`, transaction);

        res.json(response.data);
    } catch (error) {
        console.error('Error recording transaction:', error.message);
        res.status(500).json({
            success: false,
            error: 'Failed to record transaction'
        });
    }
});

/**
 * @route   GET /api/spending/stats/:address
 * @desc    Get spending statistics for an address
 * @access  Public (should be authenticated in production)
 */
router.get('/stats/:address', apiLimiter, async (req, res) => {
    try {
        const { address } = req.params;

        if (!address) {
            return res.status(400).json({
                success: false,
                error: 'Address is required'
            });
        }

        // Return mock/default statistics for now
        // TODO: Forward to Rust server when it's stable
        const mockStats = {
            success: true,
            data: {
                address: address,
                daily_spent: 0,
                weekly_spent: 0,
                monthly_spent: 0,
                transaction_count_24h: 0,
                limits: {
                    daily_limit_usd: 1000,
                    weekly_limit_usd: 5000,
                    monthly_limit_usd: 20000,
                    per_transaction_limit_usd: 500,
                    elevated_auth_threshold_usd: 1000
                },
                recent_transactions: []
            }
        };

        res.json(mockStats);

        // Try forwarding to Rust server in background (optional)
        // axios.get(`${RUST_SERVER}/api/spending/stats/${address}`).catch(err => {
        //     console.log('Rust server unavailable:', err.message);
        // });
    } catch (error) {
        console.error('Error getting spending stats:', error.message);
        res.status(500).json({
            success: false,
            error: 'Failed to get spending statistics'
        });
    }
});

/**
 * @route   POST /api/spending/limits
 * @desc    Set custom spending limits for an address
 * @access  Public (should be authenticated in production)
 * @body    { address, limits: { daily_limit_usd, weekly_limit_usd, ... } }
 */
router.post('/limits', apiLimiter, async (req, res) => {
    try {
        const { address, limits } = req.body;

        if (!address || !limits) {
            return res.status(400).json({
                success: false,
                error: 'Address and limits are required'
            });
        }

        // Validate limits structure
        const requiredFields = [
            'daily_limit_usd',
            'weekly_limit_usd',
            'monthly_limit_usd',
            'per_transaction_limit_usd',
            'elevated_auth_threshold_usd'
        ];

        for (const field of requiredFields) {
            if (limits[field] === undefined || typeof limits[field] !== 'number') {
                return res.status(400).json({
                    success: false,
                    error: `Invalid or missing field: ${field}`
                });
            }
        }

        // Return success response with the updated limits
        // TODO: Store in database and forward to Rust server when it's stable
        res.json({
            success: true,
            data: {
                updated: true,
                address: address,
                limits: limits
            }
        });

        // Try forwarding to Rust server in background (optional)
        // axios.post(`${RUST_SERVER}/api/spending/limits`, { address, limits }).catch(err => {
        //     console.log('Rust server unavailable:', err.message);
        // });
    } catch (error) {
        console.error('Error setting spending limits:', error.message);
        res.status(500).json({
            success: false,
            error: 'Failed to set spending limits'
        });
    }
});

/**
 * @route   GET /api/spending/history/:address
 * @desc    Get transaction history for an address
 * @access  Public (should be authenticated in production)
 */
router.get('/history/:address', apiLimiter, async (req, res) => {
    try {
        const { address } = req.params;

        if (!address) {
            return res.status(400).json({
                success: false,
                error: 'Address is required'
            });
        }

        // Forward to Rust server
        const response = await axios.get(`${RUST_SERVER}/api/spending/history/${address}`);

        res.json(response.data);
    } catch (error) {
        console.error('Error getting transaction history:', error.message);
        res.status(500).json({
            success: false,
            error: 'Failed to get transaction history'
        });
    }
});

/**
 * @route   GET /api/spending/limits/:address
 * @desc    Get current spending limits for an address
 * @access  Public (should be authenticated in production)
 */
router.get('/limits/:address', apiLimiter, async (req, res) => {
    try {
        const { address } = req.params;

        if (!address) {
            return res.status(400).json({
                success: false,
                error: 'Address is required'
            });
        }

        // Get stats which include limits
        const response = await axios.get(`${RUST_SERVER}/api/spending/stats/${address}`);

        if (response.data.success && response.data.data) {
            res.json({
                success: true,
                data: {
                    address,
                    limits: response.data.data.limits
                }
            });
        } else {
            res.status(500).json({
                success: false,
                error: 'Failed to get limits'
            });
        }
    } catch (error) {
        console.error('Error getting spending limits:', error.message);
        res.status(500).json({
            success: false,
            error: 'Failed to get spending limits'
        });
    }
});

module.exports = router;
