// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.0;

import "./OrgV1.sol";

interface SafeFactory {
    function createProxy(address masterCopy, bytes memory data) external returns (Safe);
}

interface Resolver {
    function multicall(bytes[] calldata data) external returns(bytes[] memory results);
    function setAddr(bytes32, address) external;
    function addr(bytes32 node) external returns (address);
    function name(bytes32 node) external returns (string memory);
}

interface Registrar {
    function commit(bytes32 commitment) external;
    function register(string calldata name, address owner, uint256 salt) external;
    function ens() external view returns (address);
    function radNode() external view returns (bytes32);
    function registrationFeeRad() external view returns (uint256);
    function minCommitmentAge() external view returns (uint256);
}

interface Safe {
    function setup(
        address[] calldata _owners,
        uint256 _threshold,
        address to,
        bytes calldata data,
        address fallbackHandler,
        address paymentToken,
        uint256 payment,
        address payable paymentReceiver
    ) external;

    function getThreshold() external returns (uint256);
    function isOwner(address owner) external returns (bool);
}

/// Factory for orgs.
contract OrgV2Factory {
    SafeFactory immutable safeFactory;
    address immutable safeMasterCopy;

    // Radicle ENS domain.
    string public radDomain = ".radicle.eth";

    /// An org was created. Includes the org and owner address as well as the name.
    event OrgCreated(address org, address safe, string domain);

    /// An org was created. Includes the org and owner address.
    event OrgCreated(address org, address safe);

    constructor(
        address _safeFactory,
        address _safeMasterCopy
    ) {
        safeFactory = SafeFactory(_safeFactory);
        safeMasterCopy = _safeMasterCopy;
    }

    /// Create an org with a specified owner.
    function createOrg(address owner) public returns (OrgV1 org) {
        org = new OrgV1(address(owner));
        emit OrgCreated(address(org), address(owner));
    }

    /// Create an org with multiple owners, via a multi-sig contract. The threshold specifies
    /// how many signatures are required to transact.
    function createOrg(address[] memory owners, uint256 threshold) public returns (OrgV1 org) {
        require(owners.length > 0, "OrgFactory: owners must not be empty");
        require(threshold > 0, "OrgFactory: threshold must be greater than zero");
        require(threshold <= owners.length, "OrgFactory: threshold must be lesser than or equal to owner count");

        // Deploy safe.
        Safe safe = safeFactory.createProxy(safeMasterCopy, new bytes(0));
        safe.setup(owners, threshold, address(0), new bytes(0), address(0), address(0), 0, payable(address(0)));

        // Deploy org
        org = new OrgV1(address(safe));
        emit OrgCreated(address(org), address(safe));
    }

    function registerAndCreateEnsOrg(
        address owner,
        bytes[] calldata data,
        string memory name,
        uint256 salt,
        Registrar registrar
    ) public returns (OrgV1, bytes32) {
        // Temporarily set the owner of the name to this contract.
        // It will be transfered to the org owner once the setup
        // is complete.
        registrar.register(name, address(this), salt);

        ENS ens = ENS(registrar.ens());
        bytes32 root = registrar.radNode();
        bytes32 label = keccak256(bytes(name));

        return createEnsOrg(
            owner,
            data,
            string(abi.encodePacked(name, radDomain)),
            root,
            label,
            ens
        );
    }

    function registerAndCreateEnsOrg(
        address[] memory owners,
        uint256 threshold,
        bytes[] calldata data,
        string memory name,
        uint256 salt,
        Registrar registrar
    ) public returns (OrgV1, bytes32) {
        registrar.register(name, address(this), salt);

        ENS ens = ENS(registrar.ens());
        bytes32 root = registrar.radNode();
        bytes32 label = keccak256(bytes(name));

        return createEnsOrg(
            owners,
            threshold,
            data,
            string(abi.encodePacked(name, radDomain)),
            root,
            label,
            ens
        );
    }

    function createEnsOrg(
        address[] memory owners,
        uint256 threshold,
        bytes[] calldata data,
        string memory domain,
        bytes32 parent,
        bytes32 label,
        ENS ens
    ) public returns (OrgV1, bytes32) {
        require(owners.length > 0, "OrgFactory: owners must not be empty");
        require(threshold > 0, "OrgFactory: threshold must be greater than zero");
        require(threshold <= owners.length, "OrgFactory: threshold must be lesser than or equal to owner count");

        // Deploy safe.
        Safe safe = safeFactory.createProxy(safeMasterCopy, new bytes(0));
        safe.setup(owners, threshold, address(0), new bytes(0), address(0), address(0), 0, payable(address(0)));

        return createEnsOrg(address(safe), data, domain, parent, label, ens);
    }

    function createEnsOrg(
        address owner,
        bytes[] calldata data,
        string memory domain,
        bytes32 parent,
        bytes32 label,
        ENS ens
    ) public returns (OrgV1, bytes32) {
        // Create org, temporarily holding ownership.
        OrgV1 org = new OrgV1(address(this));
        // Get the ENS node for the name associated with this org.
        bytes32 node = keccak256(abi.encodePacked(parent, label));
        // Get the ENS resolver for the node.
        Resolver resolver = Resolver(ens.resolver(node));
        // Set the address of the ENS name to this org.
        resolver.setAddr(node, address(org));
        // Set any other ENS records.
        resolver.multicall(data);
        // Set org ENS reverse-record.
        org.setName(domain, ens);
        // Transfer ownership of the org to the owner.
        org.setOwner(address(owner));
        // Transfer ownership of the name to the owner.
        ens.setOwner(node, address(owner));

        emit OrgCreated(address(org), address(owner), domain);

        return (org, node);
    }
}
