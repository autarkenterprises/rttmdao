// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script} from "forge-std/Script.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {RttmPool} from "../src/RttmPool.sol";

contract DeployRttmPool is Script {
    /// @dev Circle USDC on Ethereum Sepolia (testnet). https://developers.circle.com/stablecoins/usdc-contract-addresses
    address internal constant DEFAULT_SEPOLIA_USDC = 0x1c7D4B196Cb0C7B01d743Fbc6116a902379C7238;

    function run() external {
        vm.startBroadcast();
        IERC20 treasury = IERC20(vm.envOr("TREASURY_TOKEN", DEFAULT_SEPOLIA_USDC));
        address genesisAuthority = vm.envOr("GENESIS_AUTHORITY", address(0));
        if (genesisAuthority == address(0)) {
            genesisAuthority = msg.sender;
        }
        new RttmPool({
            name_: "RttM Pool Share",
            symbol_: "RTTM",
            treasuryToken_: treasury,
            genesisAuthority_: genesisAuthority,
            memberMinimum_: vm.envOr("MEMBER_MIN", uint256(50 * 1e6)),
            joinMinimum_: vm.envOr("JOIN_MIN", uint256(50 * 1e6)),
            votingPeriodBlocks_: vm.envOr("VOTING_PERIOD_BLOCKS", uint256(50400)),
            proposalPassBps_: vm.envOr("PROPOSAL_PASS_BPS", uint256(5000)),
            joinApprovalBps_: vm.envOr("JOIN_APPROVAL_BPS", uint256(5000)),
            duesAmount_: vm.envOr("DUES_AMOUNT", uint256(50 * 1e6)),
            duesPeriodSeconds_: vm.envOr("DUES_PERIOD_SECONDS", uint256(7 days)),
            duesGraceSeconds_: vm.envOr("DUES_GRACE_SECONDS", uint256(1 days))
        });
        vm.stopBroadcast();
    }
}
