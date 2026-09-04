# VaultPass

**On-chain device passports with warranty claims, on BOT Chain.**

Mint a passport for any physical device (brand + model + serial + optional metadata). The passport is transferable — sell your device, transfer the passport in one tx. File warranty claims on-chain; an approved resolver (manufacturer or authority) approves/rejects them.

Frontend style: **luxury passport / ID document** — deep navy + gold, Playfair Display + Cormorant Garamond serif, passport-page layout with wax stamps.

## Setup

```bash
npm install
cp .env.example .env
npx hardhat compile
npx hardhat test
```

## Deploy

```bash
npx hardhat run scripts/deploy.js --network botchain_testnet
npx hardhat run scripts/deploy.js --network botchain
```

Update `frontend/index.html` → `CONTRACT_ADDRESS` (and network config for mainnet).

## Contract Functions

- `mintPass(brand, model, serial, metadataURI, warrantyDays)` payable — mint fee 0.005 BOT
- `transferPass(id, to)` — owner-only transfer
- `fileClaim(id, description)` — owner-only, file warranty claim
- `resolveClaim(id, claimIndex, newStatus, note)` — approved resolvers only
- `deactivate(id, reason)` — owner or resolver marks pass inactive
- `resolveSerial(serial)` view — lookup by serial
- `setResolver(addr, approved)` — contract-owner only

## Resolver setup after deploy

The contract owner (deployer) must call `setResolver(manufacturerWallet, true)` for each manufacturer/authority who will resolve claims. The Resolver Admin tab in the frontend does this.

## Frontend

Single-file `frontend/index.html`. Hosts on Vercel/Netlify. Publish directory: `frontend`.
