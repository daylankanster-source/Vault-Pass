// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";

/// @title VaultPass — on-chain device ownership passports with warranty claims
contract VaultPass is Ownable, ReentrancyGuard, Pausable {

    enum ClaimStatus { Pending, Approved, Rejected, Resolved }

    struct Passport {
        uint256 id;
        address owner;
        string brand;         // e.g. "Sony"
        string model;         // e.g. "WH-1000XM5"
        string serial;        // unique serial number
        string metadataURI;   // optional IPFS/HTTP link to full spec
        uint256 mintedAt;
        uint256 warrantyExpires;
        bool active;          // false if reported destroyed
    }

    struct Claim {
        address claimant;
        string description;
        uint256 filedAt;
        ClaimStatus status;
        string resolutionNote;
    }

    uint256 public mintFee = 0.005 ether;
    uint256 public passCount;
    uint256 public feesCollected;

    mapping(uint256 => Passport) public passports;
    mapping(string => uint256) public serialToId;             // serial => id (0 = not registered)
    mapping(uint256 => Claim[]) public claims;                // passId => claims
    mapping(address => uint256[]) public passesByOwner;
    mapping(address => bool) public approvedResolver;         // manufacturers/authorities who can resolve claims

    event PassMinted(uint256 indexed id, address indexed owner, string brand, string model, string serial);
    event PassTransferred(uint256 indexed id, address indexed from, address indexed to);
    event ClaimFiled(uint256 indexed passId, uint256 claimIndex, address claimant, string description);
    event ClaimResolved(uint256 indexed passId, uint256 claimIndex, ClaimStatus status, string note);
    event PassDeactivated(uint256 indexed id, string reason);
    event ResolverSet(address indexed who, bool approved);

    constructor() Ownable(msg.sender) {}

    // ---------- Core ----------

    function mintPass(
        string calldata brand,
        string calldata model,
        string calldata serial,
        string calldata metadataURI,
        uint256 warrantyDays
    ) external payable whenNotPaused nonReentrant returns (uint256) {
        require(msg.value >= mintFee, "Insufficient mint fee");
        require(bytes(brand).length > 0 && bytes(brand).length <= 64, "Brand 1-64");
        require(bytes(model).length > 0 && bytes(model).length <= 64, "Model 1-64");
        require(bytes(serial).length > 0 && bytes(serial).length <= 64, "Serial 1-64");
        require(serialToId[serial] == 0, "Serial already registered");
        require(warrantyDays <= 3650, "Max 10 years");

        passCount++;
        uint256 id = passCount;

        passports[id] = Passport({
            id: id,
            owner: msg.sender,
            brand: brand,
            model: model,
            serial: serial,
            metadataURI: metadataURI,
            mintedAt: block.timestamp,
            warrantyExpires: block.timestamp + (warrantyDays * 1 days),
            active: true
        });
        serialToId[serial] = id;
        passesByOwner[msg.sender].push(id);
        feesCollected += msg.value;

        emit PassMinted(id, msg.sender, brand, model, serial);
        return id;
    }

    function transferPass(uint256 id, address to) external whenNotPaused {
        require(id > 0 && id <= passCount, "Invalid pass");
        require(to != address(0), "Zero address");
        Passport storage P = passports[id];
        require(msg.sender == P.owner, "Not owner");
        require(P.active, "Deactivated");

        address from = P.owner;
        P.owner = to;

        _removeFromOwner(from, id);
        passesByOwner[to].push(id);

        emit PassTransferred(id, from, to);
    }

    function fileClaim(uint256 id, string calldata description) external whenNotPaused returns (uint256) {
        require(id > 0 && id <= passCount, "Invalid pass");
        Passport memory P = passports[id];
        require(P.active, "Deactivated");
        require(msg.sender == P.owner, "Not owner");
        require(bytes(description).length > 0 && bytes(description).length <= 512, "Desc 1-512");

        claims[id].push(Claim({
            claimant: msg.sender,
            description: description,
            filedAt: block.timestamp,
            status: ClaimStatus.Pending,
            resolutionNote: ""
        }));
        uint256 idx = claims[id].length - 1;
        emit ClaimFiled(id, idx, msg.sender, description);
        return idx;
    }

    function resolveClaim(uint256 id, uint256 claimIndex, ClaimStatus newStatus, string calldata note) external {
        require(approvedResolver[msg.sender] || msg.sender == owner(), "Not a resolver");
        require(id > 0 && id <= passCount, "Invalid pass");
        require(claimIndex < claims[id].length, "Invalid claim");
        require(newStatus != ClaimStatus.Pending, "Cannot set pending");
        Claim storage C = claims[id][claimIndex];
        require(C.status == ClaimStatus.Pending, "Already resolved");
        C.status = newStatus;
        C.resolutionNote = note;
        emit ClaimResolved(id, claimIndex, newStatus, note);
    }

    function deactivate(uint256 id, string calldata reason) external {
        require(id > 0 && id <= passCount, "Invalid pass");
        Passport storage P = passports[id];
        require(msg.sender == P.owner || approvedResolver[msg.sender] || msg.sender == owner(), "Not authorised");
        require(P.active, "Already inactive");
        P.active = false;
        emit PassDeactivated(id, reason);
    }

    // ---------- Views ----------

    function getPassport(uint256 id) external view returns (Passport memory) {
        require(id > 0 && id <= passCount, "Invalid pass");
        return passports[id];
    }

    function resolveSerial(string calldata serial) external view returns (Passport memory) {
        uint256 id = serialToId[serial];
        require(id != 0, "Not found");
        return passports[id];
    }

    function getClaims(uint256 id) external view returns (Claim[] memory) {
        return claims[id];
    }

    function getPassesByOwner(address who) external view returns (uint256[] memory) {
        return passesByOwner[who];
    }

    function isUnderWarranty(uint256 id) external view returns (bool) {
        if (id == 0 || id > passCount) return false;
        return passports[id].active && block.timestamp <= passports[id].warrantyExpires;
    }

    // ---------- Admin ----------

    function setMintFee(uint256 v) external onlyOwner { mintFee = v; }
    function setResolver(address who, bool approved) external onlyOwner {
        approvedResolver[who] = approved;
        emit ResolverSet(who, approved);
    }
    function pause() external onlyOwner { _pause(); }
    function unpause() external onlyOwner { _unpause(); }

    function withdrawFees(address payable to) external onlyOwner nonReentrant {
        uint256 amt = feesCollected;
        feesCollected = 0;
        (bool ok, ) = to.call{value: amt}("");
        require(ok, "Withdraw failed");
    }

    // ---------- Internal ----------

    function _removeFromOwner(address from, uint256 id) internal {
        uint256[] storage arr = passesByOwner[from];
        for (uint256 i = 0; i < arr.length; i++) {
            if (arr[i] == id) {
                arr[i] = arr[arr.length - 1];
                arr.pop();
                break;
            }
        }
    }
}
