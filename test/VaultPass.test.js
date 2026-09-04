const { expect } = require("chai");
const { ethers } = require("hardhat");

describe("VaultPass", function () {
  let c, owner, alice, bob, mfr;
  const FEE = ethers.parseEther("0.005");

  beforeEach(async () => {
    [owner, alice, bob, mfr] = await ethers.getSigners();
    const F = await ethers.getContractFactory("VaultPass");
    c = await F.deploy();
    await c.waitForDeployment();
  });

  describe("Minting", () => {
    it("mints a pass with fee", async () => {
      await expect(c.connect(alice).mintPass("Sony", "WH-1000XM5", "SN-001", "ipfs://x", 365, { value: FEE }))
        .to.emit(c, "PassMinted");
      const p = await c.getPassport(1);
      expect(p.owner).to.equal(alice.address);
      expect(p.brand).to.equal("Sony");
    });

    it("rejects duplicate serial", async () => {
      await c.connect(alice).mintPass("A", "B", "SN-1", "", 30, { value: FEE });
      await expect(c.connect(bob).mintPass("A", "B", "SN-1", "", 30, { value: FEE }))
        .to.be.revertedWith("Serial already registered");
    });

    it("resolveSerial works", async () => {
      await c.connect(alice).mintPass("A", "B", "SN-9", "", 30, { value: FEE });
      const p = await c.resolveSerial("SN-9");
      expect(p.owner).to.equal(alice.address);
    });
  });

  describe("Transfer", () => {
    it("owner transfers", async () => {
      await c.connect(alice).mintPass("A", "B", "SN", "", 30, { value: FEE });
      await c.connect(alice).transferPass(1, bob.address);
      const p = await c.getPassport(1);
      expect(p.owner).to.equal(bob.address);
    });

    it("non-owner cannot transfer", async () => {
      await c.connect(alice).mintPass("A", "B", "SN", "", 30, { value: FEE });
      await expect(c.connect(bob).transferPass(1, bob.address)).to.be.revertedWith("Not owner");
    });
  });

  describe("Claims", () => {
    beforeEach(async () => {
      await c.connect(alice).mintPass("A", "B", "SN", "", 30, { value: FEE });
      await c.connect(owner).setResolver(mfr.address, true);
    });

    it("owner files a claim", async () => {
      await expect(c.connect(alice).fileClaim(1, "Broken headphone jack")).to.emit(c, "ClaimFiled");
      const claims = await c.getClaims(1);
      expect(claims.length).to.equal(1);
      expect(claims[0].status).to.equal(0); // Pending
    });

    it("resolver approves", async () => {
      await c.connect(alice).fileClaim(1, "broken");
      await c.connect(mfr).resolveClaim(1, 0, 1, "replace unit"); // Approved
      const claims = await c.getClaims(1);
      expect(claims[0].status).to.equal(1);
    });

    it("non-resolver cannot resolve", async () => {
      await c.connect(alice).fileClaim(1, "broken");
      await expect(c.connect(bob).resolveClaim(1, 0, 1, "")).to.be.revertedWith("Not a resolver");
    });
  });

  describe("Warranty", () => {
    it("reports under warranty", async () => {
      await c.connect(alice).mintPass("A", "B", "SN", "", 30, { value: FEE });
      expect(await c.isUnderWarranty(1)).to.equal(true);
    });
  });

  describe("Admin", () => {
    it("owner sets resolver", async () => {
      await c.connect(owner).setResolver(mfr.address, true);
      expect(await c.approvedResolver(mfr.address)).to.equal(true);
    });
    it("non-owner cannot", async () => {
      await expect(c.connect(alice).setResolver(mfr.address, true)).to.be.reverted;
    });
  });
});
