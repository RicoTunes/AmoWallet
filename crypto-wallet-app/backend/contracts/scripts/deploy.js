const hre = require("hardhat");

async function main() {
  console.log("🚀 Deploying Multi-Signature Wallet...\n");

  // Get deployment parameters from environment or use defaults
  const owners = process.env.MULTISIG_OWNERS 
    ? process.env.MULTISIG_OWNERS.split(',') 
    : [];
  
  const requiredConfirmations = parseInt(process.env.REQUIRED_CONFIRMATIONS || '2');

  // Validation
  if (owners.length < 2) {
    console.error("❌ Error: At least 2 owners required");
    console.log("💡 Set MULTISIG_OWNERS environment variable:");
    console.log("   export MULTISIG_OWNERS=0x123...,0x456...,0x789...");
    process.exit(1);
  }

  if (requiredConfirmations < 1 || requiredConfirmations > owners.length) {
    console.error("❌ Error: Required confirmations must be between 1 and", owners.length);
    process.exit(1);
  }

  console.log("📋 Deployment Configuration:");
  console.log("   Owners:", owners.length);
  owners.forEach((owner, i) => console.log(`     ${i + 1}. ${owner}`));
  console.log("   Required Confirmations:", requiredConfirmations);
  console.log();

  // Deploy contract
  console.log("📦 Compiling contracts...");
  const MultiSigWallet = await hre.ethers.getContractFactory("MultiSigWallet");
  
  console.log("🔨 Deploying to network:", hre.network.name);
  const wallet = await MultiSigWallet.deploy(owners, requiredConfirmations);
  
  await wallet.waitForDeployment();
  
  const address = await wallet.getAddress();
  console.log("\n✅ Multi-Signature Wallet deployed!");
  console.log("📍 Contract Address:", address);
  console.log();

  // Display transaction info
  console.log("📝 Transaction Details:");
  console.log("   Deployer:", wallet.deploymentTransaction().from);
  console.log("   Gas Used:", wallet.deploymentTransaction().gasLimit.toString());
  console.log();

  // Save deployment info
  const deploymentInfo = {
    network: hre.network.name,
    contractAddress: address,
    owners,
    requiredConfirmations,
    timestamp: new Date().toISOString(),
    deployer: wallet.deploymentTransaction().from,
    transactionHash: wallet.deploymentTransaction().hash
  };

  console.log("💾 Deployment Info:");
  console.log(JSON.stringify(deploymentInfo, null, 2));
  console.log();

  // Verification instructions
  if (hre.network.name !== 'hardhat' && hre.network.name !== 'localhost') {
    console.log("🔍 Verify contract on Etherscan:");
    console.log(`   npx hardhat verify --network ${hre.network.name} ${address} "${owners.join('","')}" ${requiredConfirmations}`);
    console.log();
  }

  console.log("✨ Deployment complete!");
  console.log();
  console.log("📚 Next Steps:");
  console.log("   1. Save the contract address");
  console.log("   2. Fund the wallet: Send ETH to", address);
  console.log("   3. Submit transactions via the API");
  console.log("   4. Confirm transactions with", requiredConfirmations, "owner(s)");
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error("❌ Deployment failed:", error);
    process.exit(1);
  });
