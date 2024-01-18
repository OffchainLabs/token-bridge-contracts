// SPDX-License-Identifier: GPL-3.0-only
pragma solidity >=0.8.4 <0.9.0;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IXERC20 } from "./IXERC20.sol";

interface IXERC20Lockbox {
    /**
     * @notice Emitted when tokens are deposited into the lockbox
     */
    event Deposit(address _sender, uint256 _amount, uint256 _share);

    /**
     * @notice Emitted when tokens are withdrawn from the lockbox
     */
    event Withdraw(address _sender, uint256 _amount, uint256 _share);

    /**
     * @notice Emitted when exchange rate updated
     */
    event ExchangeRateUpdate(uint256 oldVaule, uint256 newVaule);

    /**
     * @notice Emitted during rescueERC20()
     * @param token The address of the token
     * @param to The address of the recipient
     * @param amount The amount being rescued
     **/
    event RescueERC20(address indexed token, address indexed to, uint256 amount);

    /**
     * @notice Reverts when a user tries to deposit native tokens on a non-native lockbox
     */

    error IXERC20Lockbox_NotGasToken();

    /**
     * @notice Reverts when a user tries to deposit non-native tokens on a native lockbox
     */

    error IXERC20Lockbox_GasToken();

    /**
     * @notice Reverts when a user tries to withdraw and the call fails
     */

    error IXERC20Lockbox_WithdrawFailed();

    /**
     * @notice Deposit ERC20 tokens into the lockbox
     *
     * @param _amount The amount of tokens to deposit
     */

    function deposit(uint256 _amount) external;

    /**
     * @notice Deposit ERC20 tokens into the lockbox, and send the XERC20 to a user
     *
     * @param _user The user to send the XERC20 to
     * @param _amount The amount of tokens to deposit
     */

    function depositTo(address _user, uint256 _amount) external;

    /**
     * @notice Deposit the native asset into the lockbox, and send the XERC20 to a user
     *
     * @param _user The user to send the XERC20 to
     */

    function depositGasTokenTo(address _user) external payable;

    /**
     * @notice Withdraw ERC20 tokens from the lockbox
     *
     * @param _amount The amount of tokens to withdraw
     */

    function withdraw(uint256 _amount) external;

    /**
     * @notice Withdraw ERC20 tokens from the lockbox
     *
     * @param _user The user to withdraw to
     * @param _amount The amount of tokens to withdraw
     */

    function withdrawTo(address _user, uint256 _amount) external;

    /**
     * @notice Get underlying ERC20 token address
     *
     */
    function ERC20() external view returns (IERC20);

    /**
     * @notice Get xERC20 token address
     *
     */
    function XERC20() external view returns (IXERC20);

    /**
     * @notice Check if underlying token is gas token
     *
     */
    function IS_GAS_TOKEN() external view returns (bool);

    function exchangeRate() external view returns (uint256);
}
