// SPDX-License-Identifier: MIT
pragma solidity ^0.8.3;

import "./vault.sol";


contract VaultFactory {

    event VaultDeployed(address indexed vaultAddress, address indexed owner);

    address[] vaults;
    function createVault(address _owner, address _depositToken, uint _maintenanceFeePercentage, string memory name) external {
        Vault newVault = new Vault(_owner, _depositToken, _maintenanceFeePercentage, name);

        address newVaultAddress = address(newVault);
        vaults.push(newVaultAddress);

        emit VaultDeployed(newVaultAddress, _owner);
    }

    function getVaultCount() external view returns (uint) {
        return vaults.length;
    }

    function getAllVaults() external view returns (address[] memory){
        return vaults;
    }

}
