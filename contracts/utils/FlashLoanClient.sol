// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IERC3156FlashBorrower } from "../interfaces/flashloan/IERC3156FlashBorrower.sol";
import { IERC3156FlashLender } from "../interfaces/flashloan/IERC3156FlashLender.sol";


/**
 *  @title A basic ERC20 token
 *  @author Carlo Pascoli
 */
contract FlashLoanClient is IERC3156FlashBorrower {

    IERC3156FlashLender public lender;

    constructor(address _lender) {
        lender = IERC3156FlashLender(_lender);
    }

    /// @notice Perform a flashloan for the token and amount provided.
    /// Returns true if the loan wos successful, false otherwise
    function flashLoan(address token, uint256 amount) external returns (bool) {

        uint256 maxLoan = lender.maxFlashLoan(token);
        if (amount > maxLoan) {
            return false;
        }

        lender.flashLoan(IERC3156FlashBorrower(this), token, amount, bytes(""));

        return true;
    }


    /**
     * @dev Receive a flash loan.
     * @param initiator The initiator of the loan.
     * @param token The loan currency.
     * @param amount The amount of tokens lent.
     * @param fee The additional amount of tokens to repay.
     * @param data Arbitrary data structure, intended to contain user-defined parameters.
     * @return The keccak256 hash of "ERC3156FlashBorrower.onFlashLoan"
     */
    function onFlashLoan(
        address initiator,
        address token,
        uint256 amount,
        uint256 fee,
        bytes calldata data
    ) external returns (bytes32) {
        require(msg.sender == address(lender), "FlashBorrower: Untrusted lender");
        require(initiator == address(this), "FlashBorrower: Untrusted loan initiator");

        // approve loan repayment
        SafeERC20.safeApprove(IERC20(token), address(lender), amount + fee);

        return keccak256("ERC3156FlashBorrower.onFlashLoan");
    }


}