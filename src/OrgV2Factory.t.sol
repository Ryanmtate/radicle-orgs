// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.0;

import "ds-test/test.sol";

import "./OrgV2Factory.sol";
import "./OrgV1.sol";

interface Hevm {
    function roll(uint256) external;
    function store(address, bytes32, bytes32) external;
}

interface Token {
    function approve(address spender, uint256 amount) external returns (bool);
}

contract OrgV2FactoryTest is DSTest {
    address constant SAFE_FACTORY = 0x76E2cFc1F5Fa8F6a5b3fC4c8F4788F0116861F9B;
    address constant SAFE_MASTER_COPY = 0x34CfAC646f301356fAa8B21e94227e3583Fe3F5F;
    address constant RAD = 0x31c8EAcBFFdD875c74b94b077895Bd78CF1E64A3;

    Hevm hevm = Hevm(HEVM_ADDRESS);
    OrgV2Factory factory;

    function setUp() public {
        factory = new OrgV2Factory(SAFE_FACTORY, SAFE_MASTER_COPY);

        // Give this contract lots of $RAD.
        hevm.store(
            RAD,
            keccak256(abi.encode(address(this), uint256(2))),
            bytes32(uint(100_000_000e18))
        );
    }

    function testRegisterAndCreateEnsOrg() public {
        Registrar registrar = Registrar(0x37723287Ae6F34866d82EE623401f92Ec9013154);
        ENS ens = ENS(registrar.ens());

        string memory name = "test-0r9481bv2lzka"; // Some random name.
        uint256 salt = 42; // Commitment salt.

        // Approve the registrar for spending the registration fee.
        Token(RAD).approve(address(registrar), registrar.registrationFeeRad());

        // Commit to a name.
        {
            address owner = address(factory);
            bytes32 commitment = keccak256(abi.encodePacked(name, owner, salt));

            registrar.commit(commitment);
            hevm.roll(block.number + registrar.minCommitmentAge() + 1);
        }

        bytes[] memory data = new bytes[](0);

        (OrgV1 org, bytes32 node) = factory.registerAndCreateEnsOrg(
            address(this), // This will be the final owner of the org.
            data,
            name,
            salt,
            registrar
        );
        assertTrue(address(org) != address(0));
        assertEq(org.owner(), address(this));
        assertEq(ens.owner(node), org.owner());

        // Test ENS reverse record.
        {
            ReverseRegistrar reverse = ReverseRegistrar(ens.owner(org.ADDR_REVERSE_NODE()));
            bytes32 orgNode = reverse.node(address(org));

            Resolver resolver = Resolver(ens.resolver(orgNode));
            assertEq(resolver.name(orgNode), string(abi.encodePacked(name, ".radicle.eth")));
        }

        // Test ENS forward record.
        {
            Resolver resolver = Resolver(ens.resolver(node));
            assertEq(resolver.addr(node), address(org));
        }
    }

    function testRegisterAndCreateEnsOrgMultisig() public {
        Registrar registrar = Registrar(0x37723287Ae6F34866d82EE623401f92Ec9013154);
        ENS ens = ENS(registrar.ens());

        string memory name = "test-8gajk2b108fs";
        uint256 salt = 42; // Commitment salt.

        // Approve the registrar for spending the registration fee.
        Token(RAD).approve(address(registrar), registrar.registrationFeeRad());

        // Commit to a name.
        {
            // The factory must be the initial owner of the name.
            address owner = address(factory);
            bytes32 commitment = keccak256(abi.encodePacked(name, owner, salt));

            registrar.commit(commitment);
            hevm.roll(block.number + registrar.minCommitmentAge() + 1);
        }

        address[] memory owners = new address[](1);
        owners[0] = address(this);

        bytes[] memory data = new bytes[](0);

        (OrgV1 org, bytes32 node) = factory.registerAndCreateEnsOrg(
            owners,
            1,
            data,
            name,
            salt,
            registrar
        );
        Safe safe = Safe(org.owner());

        assertTrue(address(org) != address(0));
        assertEq(ens.owner(node), org.owner());
        assertEq(safe.getThreshold(), 1, "Threshold should be 1");
        assertTrue(safe.isOwner(address(this)), "We must be an owner");
    }
}
