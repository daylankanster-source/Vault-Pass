const hre = require("hardhat");

async function main() {
  const [deployer] = await hre.ethers.getSigners();
  console.log("Deploying VaultPass with account:", deployer.address);
  console.log("Balance:", (await hre.ethers.provider.getBalance(deployer.address)).toString());

  const VaultPass = await hre.ethers.getContractFactory("VaultPass");
  const c = await VaultPass.deploy();
  await c.waitForDeployment();

  const addr = await c.getAddress();
  console.log("VaultPass deployed to:", addr);
  console.log("\nNext steps:");
  console.log("1. Copy this address into frontend/index.html → CONTRACT_ADDRESS");
  console.log("2. Call setResolver(address,true) for each manufacturer/authority that will approve claims");
}

main().catch((e) => { console.error(e); process.exit(1); });
