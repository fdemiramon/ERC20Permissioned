# ERC20 Permissioned Token

A Solidity smart contract implementation of a permissioned ERC20 token that wraps an underlying token with additional permission controls. This token implements compliance features through both a memberlist and attestation-based verification system.

## Features

- Wraps any ERC20 token with permission controls
- Supports two types of permission mechanisms:
  1. Memberlist-based permissions
  2. Attestation-based verification (e.g., KYC, country verification)
- Special handling for Morpho protocol integration
- Ability to recover tokens in case of lost access
- Configurable attestation service and indexer

## Prerequisites

- [Foundry](https://book.getfoundry.sh/getting-started/installation)
- Node.js and npm/yarn (for development dependencies)

## Installation

1. Clone the repository:

```bash
git clone <repository-url>
cd permissionedToken
```

2. Install dependencies:

```bash
forge install
```

## Usage

### Contract Deployment

The `ERC20Permissioned` contract requires the following parameters for deployment:

```solidity
constructor(
    string memory name,
    string memory symbol,
    IERC20 underlying,
    address morpho,
    address bundler,
    address attestationService,
    address attestationIndexer,
    address memberlist
)
```

- `name`: Token name
- `symbol`: Token symbol
- `underlying`: Address of the underlying ERC20 token
- `morpho`: Address of the Morpho protocol contract
- `bundler`: Address of the bundler contract
- `attestationService`: Address of the attestation service contract
- `attestationIndexer`: Address of the attestation indexer contract
- `memberlist`: Address of the memberlist contract

### Key Functions

#### Token Operations

- `depositFor(address to, uint256 amount)`: Wrap underlying tokens
- `withdrawTo(address to, uint256 amount)`: Unwrap tokens
- `transfer(address to, uint256 amount)`: Transfer tokens (with permission checks)
- `recover(address from)`: Recover tokens from an address

#### Permission Management

- `file(bytes32 what, address data)`: Update contract parameters
- `addMember(address member)`: Add a member to the memberlist
- `removeMember(address member)`: Remove a member from the memberlist

### Permission System

The token implements a dual-layer permission system:

1. **Memberlist-based Permissions**

   - Direct control over who can hold and transfer tokens
   - Managed through the `Memberlist` contract

2. **Attestation-based Verification**
   - Supports verification through attestations (e.g., KYC, country verification)
   - Uses an attestation service and indexer for verification
   - Configurable schema UIDs for different types of verification

### Special Cases

- **Morpho Protocol Integration**: Special handling for transfers to the Morpho protocol address
- **Bundler Integration**: Support for bundler operations
- **Token Recovery**: Ability to recover tokens in case of lost access or compliance issues

## Testing

Run the test suite using Foundry:

```bash
forge test
```

For verbose output:

```bash
forge test -vv
```

## Security

The contract includes several security features:

- Permission checks on all transfers
- Ability to recover tokens in emergency situations
- Configurable parameters through the `file` function
- Integration with external verification systems

## License

This project is licensed under the GPL-2.0-or-later License - see the LICENSE file for details.

## Contributing

1. Fork the repository
2. Create your feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'Add some amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request
