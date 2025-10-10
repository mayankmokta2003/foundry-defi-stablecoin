// SPDX-License-Identifier:MIT

// Handler is going to narrow down the way we call function

pragma solidity ^0.8.18;

import {Test} from "forge-std/Test.sol";
import {DSCEngine} from "../../src/DSCEngine.sol";
import {DecentralizedStableCoin} from "../../src/DecentralizedStableCoin.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";
import {MockV3Aggregator} from "../mocks/MockV3Aggregator.sol";

contract Handler is Test {
    DSCEngine dsce;
    DecentralizedStableCoin dsc;
    ERC20Mock weth;
    ERC20Mock wbtc;
    uint256 public constant MAX_DEPOSIT_SIZE = type(uint96).max;

    uint256 public timesMintedIsCalled;
    address[] public usersWithCollateralDeposited;
    MockV3Aggregator public ethUsdPriceFeed;

    constructor(DSCEngine dscEngine, DecentralizedStableCoin _dsc) {
        dsce = dscEngine;
        dsc = _dsc;

        address[] memory collateralTokens = dsce.getCollateralTokens();
        weth = ERC20Mock(collateralTokens[0]);
        wbtc = ERC20Mock(collateralTokens[1]);

        ethUsdPriceFeed = MockV3Aggregator(dsce.getCollateralTokenPriceFeed(address(weth)));
    }

    function depositCollateral(uint256 collateralSeed, uint256 amountCollateral) public {
        ERC20Mock collateral = _getCollateralSeedFrom(collateralSeed);
        uint256 amountCollateral = bound(amountCollateral, 1, MAX_DEPOSIT_SIZE);
        // vm.assume(amountCollateral > 1 && amountCollateral < MAX_DEPOSIT_SIZE);

        vm.startPrank(msg.sender);
        collateral.mint(msg.sender, amountCollateral);
        collateral.approve(address(dsce), amountCollateral);
        dsce.depositCollateral(address(collateral), amountCollateral);
        vm.stopPrank();

        usersWithCollateralDeposited.push(msg.sender);
    }

    // // this function updates pricefeed for 1eth in usd we can say but it will always fail beacause it will
    // // give value for 1eth in usd like 200usd which is unacceptable
    // function updateCollateralPrice(uint96 newPrice) public {
    //     int256 newPriceInt = int256(uint(newPrice));
    //     ethUsdPriceFeed.updateAnswer(newPriceInt);
    // }

    function redeemCollateral(uint256 collateralSeed, uint256 amountCollateral) public {
        ERC20Mock collateral = _getCollateralSeedFrom(collateralSeed);
        uint256 maxCollateralToRedeem = dsce.getCollateralBalanceOfUser(address(collateral), msg.sender);

        // amountCollateral = bound(amountCollateral,0,maxCollateralToRedeem);
        // if(amountCollateral == 0){
        //     return;
        // }

        vm.assume(amountCollateral > 0 && amountCollateral <= maxCollateralToRedeem);

        dsce.redeemCollateral(address(collateral), amountCollateral);
    }

    // this code didnot work because it doesnt know if the user has collateral or not we need to give info
    // about user we need to tell the max amount of collaterall user paid
    // function mindDsc(uint256 amount) public {
    //     amount = bound(amount,1,MAX_DEPOSIT_SIZE);
    //     vm.startPrank(msg.sender);
    //     dsce.mintDsc(amount);
    //     vm.stopPrank();
    // }

    // function mindDsc(uint256 amount, uint256 addressSeed) public{
    //     (uint256 totalDscMinted, uint256 collateralValueInUsd) = dsce.getAccountInfomation(msg.sender);
    //     int256 maxDscToMint = (int256(collateralValueInUsd / 2) - int256(totalDscMinted));
    //     if(maxDscToMint < 0){
    //         return;
    //     }
    //     vm.assume(amount > 0 && amount <= uint256(maxDscToMint));
    //     vm.startPrank(msg.sender);
    //     dsce.mintDsc(amount);
    //     vm.stopPrank();
    //     timesMintedIsCalled++;
    // }
    // here it was not actually calling dsce.mintDsc because its randomly generating diff address everytime for
    // diff users so firse we made usersWithCollateralDeposited and in depositCollateral we pushed msg.sender in it.

    function mindDsc(uint256 amount, uint256 addressSeed) public {
        if (usersWithCollateralDeposited.length == 0) {
            return;
        }

        address sender = usersWithCollateralDeposited[addressSeed % usersWithCollateralDeposited.length];

        (uint256 totalDscMinted, uint256 collateralValueInUsd) = dsce.getAccountInfomation(sender);

        int256 maxDscToMint = (int256(collateralValueInUsd / 2) - int256(totalDscMinted));
        if (maxDscToMint < 0) {
            return;
        }

        vm.assume(amount > 0 && amount <= uint256(maxDscToMint));

        vm.startPrank(sender);
        dsce.mintDsc(amount);
        vm.stopPrank();
        timesMintedIsCalled++;
    }

    // HELPER FUNCTIONS //

    function _getCollateralSeedFrom(uint256 collateralSeed) private view returns (ERC20Mock) {
        if (collateralSeed % 2 == 0) {
            return weth;
        }
        return wbtc;
        // //////////////////////////////////////////else use
    }
}
