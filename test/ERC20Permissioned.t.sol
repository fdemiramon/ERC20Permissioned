// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";
import {ERC20Permissioned} from "../src/ERC20Permissioned.sol";
import {IERC20} from "@openzeppelin-contracts/interfaces/IERC20.sol";
import {ERC20} from "@openzeppelin-contracts/token/ERC20/ERC20.sol";
import {Memberlist} from "../src/Memberlist.sol";

contract MockERC20 is ERC20 {
    constructor() ERC20("Mock Token", "MTK") {
        _mint(msg.sender, 1000000 * 10 ** 18);
    }
}

contract MockAttestationService {
    struct Attestation {
        bytes data;
        uint256 expirationTime;
        uint256 revocationTime;
    }

    mapping(bytes32 => Attestation) public attestations;

    function getAttestation(bytes32 uid) external view returns (Attestation memory) {
        return attestations[uid];
    }

    function setAttestation(bytes32 uid, bytes memory data) external {
        attestations[uid] = Attestation({data: data, expirationTime: 0, revocationTime: 0});
    }
}

contract MockAttestationIndexer {
    mapping(address => mapping(bytes32 => bytes32)) public attestationUids;

    function getAttestationUid(address account, bytes32 schemaUid) external view returns (bytes32) {
        return attestationUids[account][schemaUid];
    }

    function setAttestationUid(address account, bytes32 schemaUid, bytes32 uid) external {
        attestationUids[account][schemaUid] = uid;
    }
}

contract ERC20PermissionedTest is Test {
    ERC20Permissioned public permissionedToken;
    MockERC20 public underlyingToken;
    Memberlist public memberlist;
    MockAttestationService public attestationService;
    MockAttestationIndexer public attestationIndexer;

    address public constant MORPHO = address(0x1234);
    address public constant BUNDLER = address(0x5678);
    address public alice = makeAddr("alice");
    address public bob = makeAddr("bob");
    address public charlie = makeAddr("charlie");

    bytes32 public constant VERIFIED_COUNTRY_SCHEMA_UID =
        0x1801901fabd0e6189356b4fb52bb0ab855276d84f7ec140839fbd1f6801ca065;
    bytes32 public constant VERIFIED_ACCOUNT_SCHEMA_UID =
        0xf8b05c79f090979bf4a80270aba232dff11a10d9ca55c4f88de95317970f0de9;

    function setUp() public {
        underlyingToken = new MockERC20();
        memberlist = new Memberlist();
        attestationService = new MockAttestationService();
        attestationIndexer = new MockAttestationIndexer();

        permissionedToken = new ERC20Permissioned(
            "Permissioned Token",
            "PTK",
            underlyingToken,
            MORPHO,
            BUNDLER,
            address(attestationService),
            address(attestationIndexer),
            address(memberlist)
        );

        // Transfer some underlying tokens to test addresses
        underlyingToken.transfer(alice, 1000 * 10 ** 18);
        underlyingToken.transfer(bob, 1000 * 10 ** 18);
        underlyingToken.transfer(charlie, 1000 * 10 ** 18);
    }

    function test_Constructor() public {
        assertEq(permissionedToken.name(), "Permissioned Token");
        assertEq(permissionedToken.symbol(), "PTK");
        assertEq(address(permissionedToken.underlying()), address(underlyingToken));
        assertEq(permissionedToken.MORPHO(), MORPHO);
        assertEq(permissionedToken.BUNDLER(), BUNDLER);
    }

    function test_WrapAndUnwrap() public {
        // Add alice to memberlist
        memberlist.rely(alice);
        memberlist.addMember(alice);

        // Alice wraps tokens
        vm.startPrank(alice);
        underlyingToken.approve(address(permissionedToken), 100 * 10 ** 18);
        permissionedToken.depositFor(alice, 100 * 10 ** 18);
        assertEq(permissionedToken.balanceOf(alice), 100 * 10 ** 18);

        // Alice unwraps tokens
        permissionedToken.withdrawTo(alice, 50 * 10 ** 18);
        assertEq(permissionedToken.balanceOf(alice), 50 * 10 ** 18);
        assertEq(underlyingToken.balanceOf(alice), 950 * 10 ** 18);
        vm.stopPrank();
    }

    function test_TransferWithMemberlist() public {
        // Add alice and bob to memberlist
        memberlist.rely(alice);
        memberlist.addMember(alice);
        memberlist.addMember(bob);

        // Alice wraps tokens
        vm.startPrank(alice);
        underlyingToken.approve(address(permissionedToken), 100 * 10 ** 18);
        permissionedToken.depositFor(alice, 100 * 10 ** 18);

        // Alice transfers to bob
        permissionedToken.transfer(bob, 50 * 10 ** 18);
        assertEq(permissionedToken.balanceOf(alice), 50 * 10 ** 18);
        assertEq(permissionedToken.balanceOf(bob), 50 * 10 ** 18);
        vm.stopPrank();
    }

    function test_TransferWithAttestations() public {
        // Set up attestations for alice
        bytes32 attestationUid = keccak256("test-attestation");
        bytes memory verifiedAccountData = abi.encodePacked(uint256(1));
        bytes memory verifiedCountryData = abi.encodePacked(bytes32(0), "FR"); // France

        attestationIndexer.setAttestationUid(alice, VERIFIED_ACCOUNT_SCHEMA_UID, attestationUid);
        attestationService.setAttestation(attestationUid, verifiedAccountData);

        bytes32 countryAttestationUid = keccak256("country-attestation");
        attestationIndexer.setAttestationUid(alice, VERIFIED_COUNTRY_SCHEMA_UID, countryAttestationUid);
        attestationService.setAttestation(countryAttestationUid, verifiedCountryData);

        // Alice wraps tokens
        vm.startPrank(alice);
        underlyingToken.approve(address(permissionedToken), 100 * 10 ** 18);
        permissionedToken.depositFor(alice, 100 * 10 ** 18);

        // Alice transfers to bob (should fail as bob has no permissions)
        vm.expectRevert(abi.encodeWithSelector(ERC20Permissioned.NoPermission.selector, bob));
        permissionedToken.transfer(bob, 50 * 10 ** 18);
        vm.stopPrank();
    }

    function test_TransferToMorpho() public {
        // Add alice to memberlist
        memberlist.rely(alice);
        memberlist.addMember(alice);

        // Alice wraps tokens
        vm.startPrank(alice);
        underlyingToken.approve(address(permissionedToken), 100 * 10 ** 18);
        permissionedToken.depositFor(alice, 100 * 10 ** 18);

        // Alice transfers to Morpho (should succeed as Morpho is whitelisted)
        permissionedToken.transfer(MORPHO, 50 * 10 ** 18);
        assertEq(permissionedToken.balanceOf(MORPHO), 50 * 10 ** 18);
        vm.stopPrank();
    }

    function test_File() public {
        address newIndexer = makeAddr("newIndexer");
        address newService = makeAddr("newService");
        address newMemberlist = makeAddr("newMemberlist");

        vm.startPrank(address(this));
        permissionedToken.file("indexer", newIndexer);
        permissionedToken.file("service", newService);
        permissionedToken.file("memberlist", newMemberlist);

        assertEq(address(permissionedToken.attestationIndexer()), newIndexer);
        assertEq(address(permissionedToken.attestationService()), newService);
        assertEq(address(permissionedToken.memberlist()), newMemberlist);
        vm.stopPrank();
    }

    function test_Recover() public {
        // Add alice to memberlist
        memberlist.rely(alice);
        memberlist.addMember(alice);

        // Alice wraps tokens
        vm.startPrank(alice);
        underlyingToken.approve(address(permissionedToken), 100 * 10 ** 18);
        permissionedToken.depositFor(alice, 100 * 10 ** 18);
        vm.stopPrank();

        // Recover tokens
        vm.startPrank(address(this));
        uint256 recovered = permissionedToken.recover(alice);
        assertEq(recovered, 100 * 10 ** 18);
        assertEq(underlyingToken.balanceOf(alice), 1000 * 10 ** 18);
        vm.stopPrank();
    }
}
