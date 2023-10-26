// SPDX-License-Identifier: Apache-2.0

pragma solidity ^0.8.0;

import "../libraries/aeERC20.sol";
import "../ethereum/ICustomToken.sol";
import "../ethereum/gateway/L1CustomGateway.sol";
import "../ethereum/gateway/L1GatewayRouter.sol";
import { IERC20Bridge } from "../libraries/IERC20Bridge.sol";
import "@openzeppelin/contracts/utils/Context.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

interface IL1CustomGateway {
    function registerTokenToL2(
        address _l2Address,
        uint256 _maxGas,
        uint256 _gasPriceBid,
        uint256 _maxSubmissionCost,
        address _creditBackAddress
    ) external payable returns (uint256);
}

interface IL1OrbitCustomGateway {
    function registerTokenToL2(
        address _l2Address,
        uint256 _maxGas,
        uint256 _gasPriceBid,
        uint256 _maxSubmissionCost,
        address _creditBackAddress,
        uint256 _feeAmount
    ) external returns (uint256);
}

interface IGatewayRouter2 {
    function setGateway(
        address _gateway,
        uint256 _maxGas,
        uint256 _gasPriceBid,
        uint256 _maxSubmissionCost,
        address _creditBackAddress
    ) external payable returns (uint256);
}

interface IOrbitGatewayRouter {
    function setGateway(
        address _gateway,
        uint256 _maxGas,
        uint256 _gasPriceBid,
        uint256 _maxSubmissionCost,
        address _creditBackAddress,
        uint256 _feeAmount
    ) external returns (uint256);

    function inbox() external returns (address);
}

contract TestCustomTokenL1 is aeERC20, ICustomToken {
    address public gateway;
    address public router;
    bool internal shouldRegisterGateway;

    constructor(address _gateway, address _router) {
        gateway = _gateway;
        router = _router;
        aeERC20._initialize("TestCustomToken", "CARB", uint8(18));
    }

    function mint() external {
        _mint(msg.sender, 50000000);
    }

    function transferFrom(
        address sender,
        address recipient,
        uint256 amount
    ) public virtual override(IERC20Upgradeable, ERC20Upgradeable, ICustomToken) returns (bool) {
        return ERC20Upgradeable.transferFrom(sender, recipient, amount);
    }

    function balanceOf(
        address account
    )
        public
        view
        virtual
        override(IERC20Upgradeable, ERC20Upgradeable, ICustomToken)
        returns (uint256)
    {
        return ERC20Upgradeable.balanceOf(account);
    }

    /// @dev we only set shouldRegisterGateway to true when in `registerTokenOnL2`
    function isArbitrumEnabled() external view override returns (uint8) {
        require(shouldRegisterGateway, "NOT_EXPECTED_CALL");
        return uint8(0xb1);
    }

    function registerTokenOnL2(
        address l2CustomTokenAddress,
        uint256 maxSubmissionCostForCustomGateway,
        uint256 maxSubmissionCostForRouter,
        uint256 maxGasForCustomGateway,
        uint256 maxGasForRouter,
        uint256 gasPriceBid,
        uint256 valueForGateway,
        uint256 valueForRouter,
        address creditBackAddress
    ) public payable virtual override {
        // we temporarily set `shouldRegisterGateway` to true for the callback in registerTokenToL2 to succeed
        bool prev = shouldRegisterGateway;
        shouldRegisterGateway = true;

        IL1CustomGateway(gateway).registerTokenToL2{ value: valueForGateway }(
            l2CustomTokenAddress,
            maxGasForCustomGateway,
            gasPriceBid,
            maxSubmissionCostForCustomGateway,
            creditBackAddress
        );

        IGatewayRouter2(router).setGateway{ value: valueForRouter }(
            gateway,
            maxGasForRouter,
            gasPriceBid,
            maxSubmissionCostForRouter,
            creditBackAddress
        );

        shouldRegisterGateway = prev;
    }
}

contract TestOrbitCustomTokenL1 is TestCustomTokenL1 {
    using SafeERC20 for IERC20;

    constructor(address _gateway, address _router) TestCustomTokenL1(_gateway, _router) {}

    function registerTokenOnL2(
        address l2CustomTokenAddress,
        uint256 maxSubmissionCostForCustomGateway,
        uint256 maxSubmissionCostForRouter,
        uint256 maxGasForCustomGateway,
        uint256 maxGasForRouter,
        uint256 gasPriceBid,
        uint256 valueForGateway,
        uint256 valueForRouter,
        address creditBackAddress
    ) public payable override {
        // we temporarily set `shouldRegisterGateway` to true for the callback in registerTokenToL2 to succeed
        bool prev = shouldRegisterGateway;
        shouldRegisterGateway = true;

        address inbox = IOrbitGatewayRouter(router).inbox();
        address bridge = address(IInbox(inbox).bridge());

        // transfer fees from user to here, and approve router to use it
        {
            address nativeToken = IERC20Bridge(bridge).nativeToken();

            IERC20(nativeToken).safeTransferFrom(
                msg.sender,
                address(this),
                valueForGateway + valueForRouter
            );
            IERC20(nativeToken).approve(router, valueForRouter);
            IERC20(nativeToken).approve(gateway, valueForGateway);
        }

        IL1OrbitCustomGateway(gateway).registerTokenToL2(
            l2CustomTokenAddress,
            maxGasForCustomGateway,
            gasPriceBid,
            maxSubmissionCostForCustomGateway,
            creditBackAddress,
            valueForGateway
        );

        IOrbitGatewayRouter(router).setGateway(
            gateway,
            maxGasForRouter,
            gasPriceBid,
            maxSubmissionCostForRouter,
            creditBackAddress,
            valueForRouter
        );

        // reset allowance back to 0 in case not all approved native tokens are spent
        {
            address nativeToken = IERC20Bridge(bridge).nativeToken();

            IERC20(nativeToken).approve(router, 0);
            IERC20(nativeToken).approve(gateway, 0);
        }

        shouldRegisterGateway = prev;
    }
}

contract MintableTestCustomTokenL1 is L1MintableToken, TestCustomTokenL1 {
    constructor(address _gateway, address _router) TestCustomTokenL1(_gateway, _router) {}

    modifier onlyGateway() {
        require(msg.sender == gateway, "ONLY_l1GATEWAY");
        _;
    }

    function bridgeMint(
        address account,
        uint256 amount
    ) public override(L1MintableToken) onlyGateway {
        _mint(account, amount);
    }

    function balanceOf(
        address account
    ) public view virtual override(TestCustomTokenL1, ICustomToken) returns (uint256 amount) {
        return super.balanceOf(account);
    }

    function transferFrom(
        address sender,
        address recipient,
        uint256 amount
    ) public virtual override(TestCustomTokenL1, ICustomToken) returns (bool) {
        return super.transferFrom(sender, recipient, amount);
    }
}

contract ReverseTestCustomTokenL1 is L1ReverseToken, MintableTestCustomTokenL1 {
    constructor(address _gateway, address _router) MintableTestCustomTokenL1(_gateway, _router) {}

    function bridgeBurn(
        address account,
        uint256 amount
    ) public override(L1ReverseToken) onlyGateway {
        _burn(account, amount);
    }

    function balanceOf(
        address account
    ) public view override(MintableTestCustomTokenL1, ICustomToken) returns (uint256 amount) {
        return super.balanceOf(account);
    }

    function transferFrom(
        address sender,
        address recipient,
        uint256 amount
    ) public override(MintableTestCustomTokenL1, ICustomToken) returns (bool) {
        return super.transferFrom(sender, recipient, amount);
    }
}
