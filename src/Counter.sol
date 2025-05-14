// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {IERC20} from "@openzeppelin-contracts/interfaces/IERC20.sol";
import {ERC20} from "@openzeppelin-contracts/token/ERC20/ERC20.sol";
import {ERC20Permit} from "@openzeppelin-contracts/token/ERC20/extensions/ERC20Permit.sol";
import {ERC20Wrapper} from "@openzeppelin-contracts/token/ERC20/extensions/ERC20Wrapper.sol";
import {Memberlist} from "src/Memberlist.sol";
import {Auth} from "lib/liquidity-pools/src/Auth.sol";

/// @title ERC20PermissionedBase
/// @author Morpho Labs
/// @custom:contact security@morpho.org
/// @notice ERC20Permissioned contract to wrap/unwrap permissionless tokens and add a permissioning scheme.
/// @dev Inherit this contract and override the `hasPermission` and `_update` functions to change the permissioning
/// scheme.
contract ERC20PermissionedBase is ERC20Wrapper, ERC20Permit {

    /// @notice Error thrown when an account does not have permission to perform an action
    /// @param account The address that lacks permission
    error NoPermission(address account);

    /// @notice Schema UID for verified country attestations
    bytes32 public constant verifiedCountrySchemaUid = 0x1801901fabd0e6189356b4fb52bb0ab855276d84f7ec140839fbd1f6801ca065;
    
    /// @notice Schema UID for verified account attestations
    bytes32 public constant verifiedAccountSchemaUid = 0xf8b05c79f090979bf4a80270aba232dff11a10d9ca55c4f88de95317970f0de9;
    
    /// @notice The memberlist contract that manages member permissions
    Memberlist public memberlist;
    
    /// @notice The attestation service contract
    IAttestationService public attestationService;
    
    /// @notice The attestation indexer contract
    IAttestationIndexer public attestationIndexer;

    /// @notice Event emitted when a parameter is updated
    /// @param what The parameter being updated
    /// @param data The new value of the parameter
    event File(bytes32 indexed what, address data);

    /// @notice The Morpho contract address
    address public immutable MORPHO;
    
    /// @notice The Bundler contract address
    address public immutable BUNDLER;

    /// @notice Constructs the contract
    /// @param name_ The name of the token
    /// @param symbol_ The symbol of the token
    /// @param underlyingToken_ The address of the underlying token
    /// @param morpho_ The address of the Morpho contract (can be zero address)
    /// @param bundler_ The address of the Bundler contract (can be zero address)
    /// @param attestationService_ The address of the attestation service
    /// @param attestationIndexer_ The address of the attestation indexer
    /// @param memberlist_ The address of the memberlist contract
    constructor(
        string memory name_,
        string memory symbol_,
        IERC20 underlyingToken_,
        address morpho_,
        address bundler_,
        address attestationService_,
        address attestationIndexer_,
        address memberlist_)
        ERC20Wrapper(underlyingToken)
        ERC20Permit(name_)
        ERC20(name_, symbol_)
    {
        MORPHO = morpho;
        BUNDLER = bundler;

        attestationService = IAttestationService(attestationService_);
        attestationIndexer = IAttestationIndexer(attestationIndexer_);
        memberlist = Memberlist(memberlist_);

        wards[msg.sender] = 1;
        emit Rely(msg.sender);
    }

    /// @notice Checks if an account has permission to interact with the contract
    /// @param account The address to check permissions for
    /// @return attested Whether the account has permission
    function hasPermission(address account) public view virtual returns (bool) {
        return account == address(0) || account == MORPHO || account == BUNDLER;
    }

    /// @notice Updates contract parameters
    /// @param what The parameter to update
    /// @param data The new value for the parameter
    function file(bytes32 what, address data) external auth {
        if (what == "indexer") attestationIndexer = IAttestationIndexer(data);
        else if (what == "service") attestationService = IAttestationService(data);
        else if (what == "memberlist") memberlist = Memberlist(data);
        else revert("PermissionedERC20Wrapper/file-unrecognized-param");
        emit File(what, data);
    }

    /// @notice Checks if an account has permission based on attestations and memberlist
    /// @param account The address to check permissions for
    /// @return attested Whether the account has permission
    function hasPermission(address account) public view override returns (bool attested) {
        if (super.hasPermission(account) || memberlist.isMember(account)) {
            return true;
        }

        Attestation memory verifiedAccountAttestation = getAttestation(account, verifiedAccountSchemaUid);
        Attestation memory verifiedCountryAttestation = getAttestation(account, verifiedCountrySchemaUid);

        return keccak256(verifiedAccountAttestation.data) == keccak256(abi.encodePacked(uint256(1)))
            && keccak256(abi.encodePacked(parseCountryCode(verifiedCountryAttestation.data)))
                != keccak256(abi.encodePacked("US"));
    }

    /// @notice Retrieves an attestation for a given account and schema
    /// @param account The address to get the attestation for
    /// @param schemaUid The schema UID to check
    /// @return attestation The attestation data
    function getAttestation(address account, bytes32 schemaUid) public view returns (Attestation memory attestation) {
        bytes32 attestationUid = attestationIndexer.getAttestationUid(account, schemaUid);
        require(attestationUid != 0, "PermissionedERC20Wrapper/no-attestation-found");
        attestation = attestationService.getAttestation(attestationUid);
        require(attestation.expirationTime == 0, "PermissionedERC20Wrapper/attestation-expired");
        require(attestation.revocationTime == 0, "PermissionedERC20Wrapper/attestation-revoked");
    }

    /// @notice Recovers tokens for a given account
    /// @param account The address to recover tokens for
    /// @return The amount of tokens recovered
    function recover(address account) public auth returns (uint256) {
        if (account == address(this)) {
            revert ERC20InvalidReceiver(account);
        }
        return _recover(account);
    }

    /// @notice Parses the country code from attestation data
    /// @param data The attestation data to parse
    /// @return The country code as a string
    function parseCountryCode(bytes memory data) internal pure returns (string memory) {
        require(data.length >= 66, "PermissionedERC20Wrapper/invalid-attestation-data");
        // Country code is two bytes long and begins at the 65th byte
        bytes memory countryBytes = new bytes(2);
        for (uint256 i = 0; i < 2; i++) {
            countryBytes[i] = data[i + 64];
        }
        return string(countryBytes);
    }

    /// @notice Returns the number of decimals used to get its user representation
    /// @return The number of decimals
    function decimals() public view virtual override(ERC20, ERC20Wrapper) returns (uint8) {
        return ERC20Wrapper.decimals();
    }

    /// @notice Updates token balances and checks permissions
    /// @param from The address to transfer from
    /// @param to The address to transfer to
    /// @param value The amount to transfer
    function _update(address from, address to, uint256 value) internal virtual override {
        if (!hasPermission(from)) revert NoPermission(from);
        if (!hasPermission(to)) revert NoPermission(to);

        super._update(from, to, value);
    }
}