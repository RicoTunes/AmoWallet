const express = require('express');
const router = express.Router();
const axios = require('axios');
const { apiLimiter } = require('../middleware/rateLimiter');

const RUST_SERVER = process.env.RUST_SERVER_URL || 'http://127.0.0.1:8443';
const ETHERSCAN_API_KEY = process.env.ETHERSCAN_API_KEY || '';
const ETHERSCAN_API_URL = 'https://api.etherscan.io/api';

/**
 * @route   POST /api/audit/contract
 * @desc    Perform comprehensive security audit on smart contract
 * @access  Public (should be authenticated in production)
 * @body    { contract_address, bytecode?, source_code? }
 */
router.post('/contract', apiLimiter, async (req, res) => {
    try {
        const { contract_address, bytecode, source_code } = req.body;

        if (!contract_address) {
            return res.status(400).json({
                success: false,
                error: 'Contract address is required'
            });
        }

        // If no bytecode/source provided, try to fetch from Etherscan
        let contractData = { contract_address, bytecode, source_code };

        if ((!bytecode || !source_code) && ETHERSCAN_API_KEY) {
            try {
                // Fetch contract source code from Etherscan
                const etherscanResponse = await axios.get(ETHERSCAN_API_URL, {
                    params: {
                        module: 'contract',
                        action: 'getsourcecode',
                        address: contract_address,
                        apikey: ETHERSCAN_API_KEY
                    }
                });

                if (etherscanResponse.data.status === '1' && etherscanResponse.data.result[0]) {
                    const contractInfo = etherscanResponse.data.result[0];
                    contractData.source_code = contractInfo.SourceCode || source_code;
                    contractData.compiler_version = contractInfo.CompilerVersion;
                    contractData.contract_name = contractInfo.ContractName;
                }
            } catch (etherscanError) {
                console.warn('Failed to fetch from Etherscan:', etherscanError.message);
            }
        }

        // Forward to Rust server for audit
        const response = await axios.post(`${RUST_SERVER}/api/audit/contract`, contractData);

        // Enhance response with Etherscan verification status
        if (response.data.success && response.data.data) {
            response.data.data.etherscan_verified = !!contractData.source_code;
        }

        res.json(response.data);
    } catch (error) {
        console.error('Error auditing contract:', error.message);
        res.status(500).json({
            success: false,
            error: 'Failed to audit contract'
        });
    }
});

/**
 * @route   GET /api/audit/quick/:address
 * @desc    Quick risk assessment without full audit
 * @access  Public
 */
router.get('/quick/:address', apiLimiter, async (req, res) => {
    try {
        const { address } = req.params;

        if (!address) {
            return res.status(400).json({
                success: false,
                error: 'Contract address is required'
            });
        }

        // Forward to Rust server
        const response = await axios.get(`${RUST_SERVER}/api/audit/quick/${address}`);

        res.json(response.data);
    } catch (error) {
        console.error('Error in quick audit:', error.message);
        res.status(500).json({
            success: false,
            error: 'Failed to perform quick audit'
        });
    }
});

/**
 * @route   GET /api/audit/whitelist
 * @desc    Get list of whitelisted contracts
 * @access  Public
 */
router.get('/whitelist', apiLimiter, async (req, res) => {
    try {
        const response = await axios.get(`${RUST_SERVER}/api/audit/whitelist`);
        res.json(response.data);
    } catch (error) {
        console.error('Error getting whitelist:', error.message);
        res.status(500).json({
            success: false,
            error: 'Failed to get whitelist'
        });
    }
});

/**
 * @route   POST /api/audit/whitelist
 * @desc    Add contract to whitelist (requires admin auth in production)
 * @access  Public (should be admin-only in production)
 * @body    { address, name, audited_by, audit_date, risk_level }
 */
router.post('/whitelist', apiLimiter, async (req, res) => {
    try {
        const { address, name, audited_by, audit_date, risk_level } = req.body;

        if (!address || !name) {
            return res.status(400).json({
                success: false,
                error: 'Address and name are required'
            });
        }

        const entry = {
            address,
            name,
            audited_by: audited_by || [],
            audit_date: audit_date || Math.floor(Date.now() / 1000),
            risk_level: risk_level || 'Safe'
        };

        const response = await axios.post(`${RUST_SERVER}/api/audit/whitelist`, entry);

        res.json(response.data);
    } catch (error) {
        console.error('Error adding to whitelist:', error.message);
        res.status(500).json({
            success: false,
            error: 'Failed to add to whitelist'
        });
    }
});

/**
 * @route   POST /api/audit/verify-etherscan
 * @desc    Verify contract on Etherscan and return verification status
 * @access  Public
 * @body    { contract_address }
 */
router.post('/verify-etherscan', apiLimiter, async (req, res) => {
    try {
        const { contract_address } = req.body;

        if (!contract_address) {
            return res.status(400).json({
                success: false,
                error: 'Contract address is required'
            });
        }

        if (!ETHERSCAN_API_KEY) {
            return res.status(503).json({
                success: false,
                error: 'Etherscan API key not configured'
            });
        }

        // Query Etherscan API
        const response = await axios.get(ETHERSCAN_API_URL, {
            params: {
                module: 'contract',
                action: 'getsourcecode',
                address: contract_address,
                apikey: ETHERSCAN_API_KEY
            }
        });

        if (response.data.status === '1' && response.data.result[0]) {
            const contractInfo = response.data.result[0];
            const isVerified = contractInfo.SourceCode && contractInfo.SourceCode.length > 0;

            res.json({
                success: true,
                data: {
                    contract_address,
                    is_verified: isVerified,
                    contract_name: contractInfo.ContractName,
                    compiler_version: contractInfo.CompilerVersion,
                    optimization_used: contractInfo.OptimizationUsed === '1',
                    runs: contractInfo.Runs,
                    constructor_arguments: contractInfo.ConstructorArguments,
                    evm_version: contractInfo.EVMVersion,
                    library: contractInfo.Library,
                    license_type: contractInfo.LicenseType,
                    proxy: contractInfo.Proxy === '1',
                    implementation: contractInfo.Implementation,
                    swarm_source: contractInfo.SwarmSource
                }
            });
        } else {
            res.json({
                success: true,
                data: {
                    contract_address,
                    is_verified: false,
                    message: 'Contract not verified on Etherscan'
                }
            });
        }
    } catch (error) {
        console.error('Error verifying on Etherscan:', error.message);
        res.status(500).json({
            success: false,
            error: 'Failed to verify contract on Etherscan'
        });
    }
});

/**
 * @route   GET /api/audit/info
 * @desc    Get information about auditing capabilities
 * @access  Public
 */
router.get('/info', apiLimiter, (req, res) => {
    res.json({
        success: true,
        data: {
            features: [
                'Bytecode analysis for vulnerability patterns',
                'Source code static analysis',
                'Etherscan verification checks',
                'Whitelisted protocol database',
                'Risk scoring (0-100)',
                'Multi-tier risk levels (Safe, Low, Medium, High, Critical)',
                'Vulnerability detection (Reentrancy, Integer Overflow, etc.)',
                'Security recommendations'
            ],
            vulnerability_types: [
                'Reentrancy',
                'Integer Overflow',
                'Unprotected Function',
                'Delegate Call',
                'Uninitialized Storage',
                'Access Control',
                'Front Running',
                'Timestamp Dependence',
                'tx.origin Usage',
                'Unhandled Return Values'
            ],
            whitelisted_protocols: [
                'Uniswap V3',
                'Aave V3',
                'Compound V3',
                'OpenZeppelin Contracts'
            ],
            etherscan_enabled: !!ETHERSCAN_API_KEY,
            rust_backend: 'All security checks performed in Rust'
        }
    });
});

module.exports = router;
