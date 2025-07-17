# CrediFi

A simplified decentralized lending protocol built with Solidity that allows users to earn yield on their crypto assets while introducing the foundation for a credit-based borrowing system.

## Overview

CrediFi is a DeFi lending protocol that enables users to deposit ETH, USDC, and MATIC to earn yield through a rebasing token system. The protocol uses share tokens (saTokens) to represent user deposits and automatically adjusts token balances when interest is added to the pools.

## Features

- **Multi-Asset Support**: Deposit ETH, USDC, and MATIC
- **Rebasing Tokens**: Automatic yield distribution through share token rebasing
- **Credit-Based Foundation**: Architecture designed to support future credit-based borrowing
- **Secure**: Built with OpenZeppelin contracts and reentrancy protection
- **Gas Efficient**: Optimized for cost-effective transactions

## Architecture

### Core Contracts

- **`CrediFiProtocol.sol`**: Main protocol contract handling deposits, withdrawals, and interest distribution
- **`SaToken.sol`**: Rebasing ERC20 tokens representing shares in the lending pools

### How It Works

1. **Deposits**: Users deposit assets and receive corresponding saTokens (saETH, saUSDC, saMATIC)
2. **Yield Generation**: Protocol generates yield through lending activities
3. **Rebasing**: When interest is added, saToken balances automatically increase proportionally
4. **Withdrawals**: Users can withdraw their assets by burning saTokens

## Smart Contracts

### CrediFiProtocol

The main protocol contract that manages:
- Asset deposits and withdrawals
- Interest distribution
- Pool reserves tracking
- saToken minting and burning

**Key Functions:**
- `depositETH()` / `depositUSDC()` / `depositMATIC()`: Deposit assets
- `withdrawETH()` / `withdrawUSDC()` / `withdrawMATIC()`: Withdraw assets
- `addETHInterest()` / `addUSDCInterest()` / `addMATICInterest()`: Add interest to pools

### SaToken

Rebasing ERC20 tokens that represent shares in the lending pools:
- Automatic balance adjustments when interest is added
- Share-based accounting system
- Standard ERC20 functionality with rebasing mechanics

## Development

### Prerequisites

- [Foundry](https://getfoundry.sh/)

### Installation

```bash
# Clone the repository
git clone <repository-url>
cd CrediFi

# Install dependencies
forge install
```

### Environment Setup

Create a `.env` file with the following variables:

```env
ETHEREUM_RPC_URL=your_ethereum_rpc_url
POLYGON_RPC_URL=your_polygon_rpc_url
ETHERSCAN_MAINNET_KEY=your_etherscan_key
ETHERSCAN_API_KEY=your_polygonscan_key
```

### Secure Key Management (Keystore)

**Do NOT add your private key to `.env` or commit it to version control.**

Instead, create a secure wallet keystore and use it with Foundry's `cast` and `forge` tools.

_Credits to Patrick Collins for the keystore workflow._

#### Create a new wallet keystore

```bash
cast wallet import myKeystoreName --interactive
```
- Enter your wallet's private key when prompted.
- Provide a password to encrypt the keystore file.

⚠️ **Recommendation:**
Do not use a private key associated with real funds. Create a new wallet for deployment and testing.

### Compilation

```bash
# Compile contracts
forge build
```

### Testing

```bash
# Run all tests
forge test

# Generate HTML coverage report
forge coverage --report lcov && genhtml lcov.info --output-directory coverage
```

## Contributing

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'Add amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## Disclaimer

This software is for educational purposes only. Use at your own risk. The authors are not responsible for any financial losses incurred through the use of this software.