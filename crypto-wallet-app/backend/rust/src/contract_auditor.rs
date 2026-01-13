use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use std::sync::{Arc, Mutex};

/// Security risk level for smart contracts
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub enum RiskLevel {
    Safe,
    Low,
    Medium,
    High,
    Critical,
}

/// Vulnerability type detected in contract
#[derive(Debug, Clone, Serialize, Deserialize)]
pub enum VulnerabilityType {
    Reentrancy,
    IntegerOverflow,
    UnprotectedFunction,
    DelegateCall,
    Uninitialized,
    AccessControl,
    FrontRunning,
    TimestampDependence,
    TxOrigin,
    UnhandledReturn,
}

/// Detected vulnerability in contract
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Vulnerability {
    pub vulnerability_type: VulnerabilityType,
    pub severity: RiskLevel,
    pub description: String,
    pub line_number: Option<u32>,
    pub recommendation: String,
}

/// Contract audit result
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ContractAuditResult {
    pub contract_address: String,
    pub is_verified: bool,
    pub risk_level: RiskLevel,
    pub vulnerabilities: Vec<Vulnerability>,
    pub is_whitelisted: bool,
    pub audited_by: Vec<String>,
    pub deployment_date: Option<u64>,
    pub compiler_version: Option<String>,
    pub warnings: Vec<String>,
    pub recommendations: Vec<String>,
    pub score: u8, // 0-100, higher is better
}

/// Known vulnerability patterns for bytecode analysis
pub struct VulnerabilityPattern {
    pub name: String,
    pub pattern: Vec<u8>,
    pub severity: RiskLevel,
    pub description: String,
}

/// Smart contract security auditor
pub struct ContractAuditor {
    whitelisted_contracts: Arc<Mutex<HashMap<String, ContractWhitelistEntry>>>,
    vulnerability_patterns: Vec<VulnerabilityPattern>,
}

/// Whitelisted contract entry
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ContractWhitelistEntry {
    pub address: String,
    pub name: String,
    pub audited_by: Vec<String>,
    pub audit_date: u64,
    pub risk_level: RiskLevel,
}

impl ContractAuditor {
    pub fn new() -> Self {
        let mut auditor = Self {
            whitelisted_contracts: Arc::new(Mutex::new(HashMap::new())),
            vulnerability_patterns: Vec::new(),
        };
        
        auditor.initialize_vulnerability_patterns();
        auditor.initialize_default_whitelist();
        
        auditor
    }

    /// Initialize known vulnerability patterns
    fn initialize_vulnerability_patterns(&mut self) {
        // Reentrancy pattern detection (simplified)
        self.vulnerability_patterns.push(VulnerabilityPattern {
            name: "Potential Reentrancy".to_string(),
            pattern: vec![0x5b, 0xf1], // JUMPDEST, CALL pattern (simplified)
            severity: RiskLevel::High,
            description: "Contract may be vulnerable to reentrancy attacks".to_string(),
        });

        // Unprotected SELFDESTRUCT
        self.vulnerability_patterns.push(VulnerabilityPattern {
            name: "Unprotected SELFDESTRUCT".to_string(),
            pattern: vec![0xff], // SELFDESTRUCT opcode
            severity: RiskLevel::Critical,
            description: "Contract contains SELFDESTRUCT without proper access control".to_string(),
        });

        // DELEGATECALL usage
        self.vulnerability_patterns.push(VulnerabilityPattern {
            name: "DELEGATECALL Usage".to_string(),
            pattern: vec![0xf4], // DELEGATECALL opcode
            severity: RiskLevel::Medium,
            description: "Contract uses DELEGATECALL which can be dangerous".to_string(),
        });
    }

    /// Initialize default whitelist of trusted protocols
    fn initialize_default_whitelist(&mut self) {
        let mut whitelist = self.whitelisted_contracts.lock().unwrap();
        
        // Uniswap V3 Router
        whitelist.insert(
            "0x68b3465833fb72A70ecDF485E0e4C7bD8665Fc45".to_lowercase(),
            ContractWhitelistEntry {
                address: "0x68b3465833fb72A70ecDF485E0e4C7bD8665Fc45".to_string(),
                name: "Uniswap V3 Router 2".to_string(),
                audited_by: vec!["OpenZeppelin".to_string(), "Trail of Bits".to_string()],
                audit_date: 1619000000,
                risk_level: RiskLevel::Safe,
            },
        );

        // Aave V3 Pool
        whitelist.insert(
            "0x87870Bca3F3fD6335C3F4ce8392D69350B4fA4E2".to_lowercase(),
            ContractWhitelistEntry {
                address: "0x87870Bca3F3fD6335C3F4ce8392D69350B4fA4E2".to_string(),
                name: "Aave V3 Pool".to_string(),
                audited_by: vec!["OpenZeppelin".to_string(), "ABDK".to_string()],
                audit_date: 1647000000,
                risk_level: RiskLevel::Safe,
            },
        );

        // Compound V3
        whitelist.insert(
            "0xc3d688B66703497DAA19211EEdff47f25384cdc3".to_lowercase(),
            ContractWhitelistEntry {
                address: "0xc3d688B66703497DAA19211EEdff47f25384cdc3".to_string(),
                name: "Compound V3 USDC".to_string(),
                audited_by: vec!["OpenZeppelin".to_string(), "ChainSecurity".to_string()],
                audit_date: 1661000000,
                risk_level: RiskLevel::Safe,
            },
        );
    }

    /// Add contract to whitelist
    pub fn add_to_whitelist(&self, entry: ContractWhitelistEntry) {
        let mut whitelist = self.whitelisted_contracts.lock().unwrap();
        whitelist.insert(entry.address.to_lowercase(), entry);
    }

    /// Check if contract is whitelisted
    pub fn is_whitelisted(&self, address: &str) -> bool {
        let whitelist = self.whitelisted_contracts.lock().unwrap();
        whitelist.contains_key(&address.to_lowercase())
    }

    /// Get whitelist entry for contract
    pub fn get_whitelist_entry(&self, address: &str) -> Option<ContractWhitelistEntry> {
        let whitelist = self.whitelisted_contracts.lock().unwrap();
        whitelist.get(&address.to_lowercase()).cloned()
    }

    /// Perform comprehensive audit on contract
    pub fn audit_contract(
        &self,
        contract_address: &str,
        bytecode: Option<&[u8]>,
        source_code: Option<&str>,
    ) -> ContractAuditResult {
        let mut result = ContractAuditResult {
            contract_address: contract_address.to_string(),
            is_verified: source_code.is_some(),
            risk_level: RiskLevel::Low,
            vulnerabilities: Vec::new(),
            is_whitelisted: self.is_whitelisted(contract_address),
            audited_by: Vec::new(),
            deployment_date: None,
            compiler_version: None,
            warnings: Vec::new(),
            recommendations: Vec::new(),
            score: 100,
        };

        // If whitelisted, return safe result
        if result.is_whitelisted {
            if let Some(entry) = self.get_whitelist_entry(contract_address) {
                result.risk_level = entry.risk_level.clone();
                result.audited_by = entry.audited_by.clone();
                result.score = 95;
                return result;
            }
        }

        // Check if contract is verified
        if !result.is_verified {
            result.warnings.push("Contract source code is not verified".to_string());
            result.recommendations.push("Only interact with verified contracts".to_string());
            result.risk_level = RiskLevel::Medium;
            result.score -= 30;
        }

        // Analyze bytecode if available
        if let Some(code) = bytecode {
            self.analyze_bytecode(code, &mut result);
        }

        // Analyze source code if available
        if let Some(source) = source_code {
            self.analyze_source_code(source, &mut result);
        }

        // Calculate final risk level
        self.calculate_risk_level(&mut result);

        result
    }

    /// Analyze bytecode for vulnerability patterns
    fn analyze_bytecode(&self, bytecode: &[u8], result: &mut ContractAuditResult) {
        for pattern in &self.vulnerability_patterns {
            if self.contains_pattern(bytecode, &pattern.pattern) {
                result.vulnerabilities.push(Vulnerability {
                    vulnerability_type: match pattern.name.as_str() {
                        "Potential Reentrancy" => VulnerabilityType::Reentrancy,
                        "Unprotected SELFDESTRUCT" => VulnerabilityType::UnprotectedFunction,
                        "DELEGATECALL Usage" => VulnerabilityType::DelegateCall,
                        _ => VulnerabilityType::UnhandledReturn,
                    },
                    severity: pattern.severity.clone(),
                    description: pattern.description.clone(),
                    line_number: None,
                    recommendation: self.get_recommendation(&pattern.name),
                });

                // Deduct score based on severity
                result.score -= match pattern.severity {
                    RiskLevel::Critical => 40,
                    RiskLevel::High => 25,
                    RiskLevel::Medium => 15,
                    RiskLevel::Low => 5,
                    RiskLevel::Safe => 0,
                };
            }
        }
    }

    /// Check if bytecode contains pattern
    fn contains_pattern(&self, bytecode: &[u8], pattern: &[u8]) -> bool {
        if pattern.is_empty() || bytecode.len() < pattern.len() {
            return false;
        }

        bytecode.windows(pattern.len()).any(|window| window == pattern)
    }

    /// Analyze source code for vulnerabilities
    fn analyze_source_code(&self, source: &str, result: &mut ContractAuditResult) {
        // Check for common vulnerability patterns in source

        // Reentrancy check
        if source.contains(".call{value:") || source.contains(".call.value") {
            if !source.contains("nonReentrant") && !source.contains("ReentrancyGuard") {
                result.vulnerabilities.push(Vulnerability {
                    vulnerability_type: VulnerabilityType::Reentrancy,
                    severity: RiskLevel::High,
                    description: "Potential reentrancy vulnerability detected".to_string(),
                    line_number: None,
                    recommendation: "Use ReentrancyGuard or checks-effects-interactions pattern".to_string(),
                });
                result.score -= 25;
            }
        }

        // tx.origin usage
        if source.contains("tx.origin") {
            result.vulnerabilities.push(Vulnerability {
                vulnerability_type: VulnerabilityType::TxOrigin,
                severity: RiskLevel::Medium,
                description: "Use of tx.origin for authorization".to_string(),
                line_number: None,
                recommendation: "Use msg.sender instead of tx.origin".to_string(),
            });
            result.score -= 15;
        }

        // Timestamp dependence
        if source.contains("block.timestamp") || source.contains("now") {
            result.warnings.push("Contract uses block.timestamp which can be manipulated".to_string());
            result.score -= 5;
        }

        // Unchecked external calls
        if source.contains(".call(") && !source.contains("require(success") {
            result.vulnerabilities.push(Vulnerability {
                vulnerability_type: VulnerabilityType::UnhandledReturn,
                severity: RiskLevel::Medium,
                description: "External call without checking return value".to_string(),
                line_number: None,
                recommendation: "Always check return values from external calls".to_string(),
            });
            result.score -= 15;
        }

        // Positive checks for security best practices
        if source.contains("@openzeppelin/contracts") {
            result.score += 5;
            result.warnings.push("Uses OpenZeppelin contracts (good practice)".to_string());
        }

        if source.contains("SafeMath") || source.contains("^0.8") {
            result.score += 5;
        }
    }

    /// Calculate overall risk level based on vulnerabilities
    fn calculate_risk_level(&self, result: &mut ContractAuditResult) {
        let critical_count = result.vulnerabilities.iter()
            .filter(|v| matches!(v.severity, RiskLevel::Critical))
            .count();
        
        let high_count = result.vulnerabilities.iter()
            .filter(|v| matches!(v.severity, RiskLevel::High))
            .count();

        result.risk_level = if critical_count > 0 {
            RiskLevel::Critical
        } else if high_count > 0 {
            RiskLevel::High
        } else if result.vulnerabilities.len() > 2 {
            RiskLevel::Medium
        } else if !result.is_verified {
            RiskLevel::Medium
        } else {
            RiskLevel::Low
        };

        // Ensure score is within bounds
        result.score = result.score.max(0).min(100);
    }

    /// Get recommendation for vulnerability
    fn get_recommendation(&self, vulnerability_name: &str) -> String {
        match vulnerability_name {
            "Potential Reentrancy" => "Implement ReentrancyGuard or use checks-effects-interactions pattern".to_string(),
            "Unprotected SELFDESTRUCT" => "Add access control modifiers (onlyOwner) to SELFDESTRUCT".to_string(),
            "DELEGATECALL Usage" => "Ensure DELEGATECALL is used safely with trusted contracts only".to_string(),
            _ => "Review contract code and consult security best practices".to_string(),
        }
    }

    /// Get all whitelisted contracts
    pub fn get_whitelist(&self) -> Vec<ContractWhitelistEntry> {
        let whitelist = self.whitelisted_contracts.lock().unwrap();
        whitelist.values().cloned().collect()
    }

    /// Quick risk assessment (no bytecode analysis)
    pub fn quick_assess(&self, contract_address: &str, is_verified: bool) -> RiskLevel {
        if self.is_whitelisted(contract_address) {
            return RiskLevel::Safe;
        }

        if !is_verified {
            return RiskLevel::High;
        }

        RiskLevel::Medium
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_whitelisted_contract() {
        let auditor = ContractAuditor::new();
        
        // Uniswap should be whitelisted
        assert!(auditor.is_whitelisted("0x68b3465833fb72A70ecDF485E0e4C7bD8665Fc45"));
        
        let result = auditor.audit_contract(
            "0x68b3465833fb72A70ecDF485E0e4C7bD8665Fc45",
            None,
            None,
        );
        
        assert_eq!(result.risk_level, RiskLevel::Safe);
        assert!(result.is_whitelisted);
    }

    #[test]
    fn test_unverified_contract() {
        let auditor = ContractAuditor::new();
        
        let result = auditor.audit_contract(
            "0x1234567890123456789012345678901234567890",
            None,
            None,
        );
        
        assert!(!result.is_verified);
        assert!(matches!(result.risk_level, RiskLevel::Medium | RiskLevel::High));
        assert!(result.score < 100);
    }

    #[test]
    fn test_vulnerability_detection() {
        let auditor = ContractAuditor::new();
        
        let dangerous_source = r#"
            function withdraw() public {
                uint amount = balances[msg.sender];
                msg.sender.call{value: amount}("");
                balances[msg.sender] = 0;
            }
        "#;
        
        let result = auditor.audit_contract(
            "0x1234567890123456789012345678901234567890",
            None,
            Some(dangerous_source),
        );
        
        assert!(!result.vulnerabilities.is_empty());
        assert!(result.score < 100);
    }

    #[test]
    fn test_bytecode_pattern_detection() {
        let auditor = ContractAuditor::new();
        
        // Bytecode with DELEGATECALL opcode
        let bytecode = vec![0x60, 0x80, 0xf4, 0x60, 0x00];
        
        let result = auditor.audit_contract(
            "0x1234567890123456789012345678901234567890",
            Some(&bytecode),
            None,
        );
        
        assert!(!result.vulnerabilities.is_empty());
    }
}
