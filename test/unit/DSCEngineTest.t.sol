// SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

import {Test} from "forge-std/Test.sol";
import {DSCEngine} from "../../src/DSCEngine.sol";
import {DecentralizedStableCoin} from "../../src/DecentralizedStableCoin.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {DeployDSC} from "../../script/DeployDSC.s.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";
import {MockV3Aggregator} from "../mocks/MockV3Aggregator.sol";

contract DSCEngineTest is Test {
    DeployDSC deployer;
    DecentralizedStableCoin dsc;
    DSCEngine dsce;
    HelperConfig config;
    address ethUsdPriceFeed;
    address weth;
    address btcUsdPriceFeed;

    address public USER = makeAddr("user");
    uint256 public constant AMOUNT_COLLATERAL = 10 ether;
    uint256 public constant STARTING_ERC20_BALANCE = 10 ether;
    uint256 amountToMint = 100 ether;

    function setUp() public {
        deployer = new DeployDSC();
        // as our deployer returns dsc and dsce so
        (dsc, dsce, config) = deployer.run();
        (ethUsdPriceFeed, btcUsdPriceFeed, weth,,) = config.activeNetworkConfig();
        ERC20Mock(weth).mint(USER, STARTING_ERC20_BALANCE);
    }

    ////////////////////////////////
    //  CONSTRUCTOR TESTS  /////////
    ////////////////////////////////

    address[] private tokenAddresses;
    address[] private priceFeedAddresses;

    function testRevertsIfTokenLengthDoesntMatchPriceFeed() public {
        tokenAddresses.push(weth);
        priceFeedAddresses.push(ethUsdPriceFeed);
        priceFeedAddresses.push(btcUsdPriceFeed);

        vm.expectRevert(DSCEngine.DSCEngine__TokenFeedAndPriceFeedAddressesMustBeOfSamelength.selector);
        new DSCEngine(tokenAddresses, priceFeedAddresses, address(dsc));
    }

    ///////////////////
    //  PRICE TESTS  //
    ///////////////////

    function testGetUsdValue() public {
        uint256 ethAmount = 15e18;
        // 15e18 * 2000e18 = 30000e18
        uint256 expectedUsd = 30000e18;
        uint256 actualUsd = dsce.getUsdValue(weth, ethAmount);
        assertEq(expectedUsd, actualUsd);
    }

    function testgetTokenAmountFromUsd() public {
        uint256 usdAmount = 100 ether;
        // 2000/100 = 0.05
        uint256 expectedWeth = 0.05 ether;

        uint256 actualWeth = dsce.getTokenAmountFromUsd(weth, usdAmount);
        assertEq(expectedWeth, actualWeth);
    }

    ////////////////////////////////
    //  DEPOSIT COLLATERAL TESTS  //
    ////////////////////////////////

    function testRevertsIfCollateralIsZero() public {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(dsce), AMOUNT_COLLATERAL);

        vm.expectRevert(DSCEngine.DSCEngine__NeedsMoreThanZero.selector);
        dsce.depositCollateral(weth, 0);
        vm.stopPrank();
    }

    // function testRevertsWithUnapprovedCollateral() public {
    //     // ERC20Mock ranToken = new ERC20Mock("RAN","RAN",USER,AMOUNT_COLLATERAL);
    //     ERC20Mock ranToken = new ERC20Mock();
    //     ranToken.mint(USER, AMOUNT_COLLATERAL);

    //     vm.startPrank(USER);
    //     vm.expectRevert(DSCEngine.DSCEngine__TransferFailed.selector);
    //     dsce.depositCollateral(address(ranToken),AMOUNT_COLLATERAL);
    //     vm.stopPrank();

    // }

    // modifier deplositCollateral() {
    //     vm.startPrank(USER);
    //     ERC20Mock(weth).transfer(address(dsce), AMOUNT_COLLATERAL);
    //     dsce.depositCollateral(weth, AMOUNT_COLLATERAL);
    //     vm.stopPrank();
    //     _;
    // }


    modifier depositCollateral() {
    vm.startPrank(USER);
    // Step 1: Make sure USER has enough tokens
    ERC20Mock(weth).mint(USER, AMOUNT_COLLATERAL); // Only if testing mock
    // Step 2: Approve DSCEngine
    ERC20Mock(weth).approve(address(dsce), AMOUNT_COLLATERAL);
    // Step 3: Deposit via DSCEngine
    dsce.depositCollateral(weth, AMOUNT_COLLATERAL);
    vm.stopPrank();
    _;
}

    function testCanDepositCollateralAndGetAccountInfo() public depositCollateral{

        (uint256 totalDscMinted, uint256 collateralValueInUsd) = dsce.getAccountInfomation(USER);

        uint256 expectedTotalDscMinted = 0;
        uint256 expectedCollateralValueInUsd = dsce.getTokenAmountFromUsd(weth,collateralValueInUsd);

        assertEq(totalDscMinted, expectedTotalDscMinted);
        assertEq(AMOUNT_COLLATERAL, expectedCollateralValueInUsd);

    }

    function testGetDsc() public {
        address dscAddress = dsce.getDsc();
        assertEq(dscAddress,address(dsc));
    }

    // function testCanMintDsc() public depositCollateral{
    //     vm.startPrank(USER);
    //     dsce.mintDsc(amount);

    //     vm.stopPrank();

    // }

    function testCanMintDsc() public depositCollateral {
        uint256 amountToMint = 100 ether;
        vm.prank(USER);
        dsce.mintDsc(amountToMint);

        uint256 userBalance = dsc.balanceOf(USER);
        assertEq(userBalance, amountToMint);
    }

    // function testRevertsIfMintAmountIsZero() public {
    //     uint256 amountToMint = 100 ether;
    //     vm.startPrank(USER);
    //     ERC20Mock(weth).approve(address(dsce),AMOUNT_COLLATERAL);
    //     dsce.depositCollateralAndMintDsc(weth,AMOUNT_COLLATERAL,amountToMint);
    //     vm.expectRevert(DSCEngine.DSCEngine__NeedsMoreThanZero.selector);
    //     dsce.mintDsc(0);
    //     vm.stopPrank();
    // }

    modifier depositedCollateralAndMintedDsc(){
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(dsce),AMOUNT_COLLATERAL);
        dsce.depositCollateralAndMintDsc(weth,AMOUNT_COLLATERAL,amountToMint);
        vm.stopPrank();
        _;
    }

   

    function testRevertsIfBurnAmountIsZero() public{
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(dsce),AMOUNT_COLLATERAL);
        dsce.depositCollateralAndMintDsc(weth,AMOUNT_COLLATERAL,amountToMint);
        vm.expectRevert(DSCEngine.DSCEngine__NeedsMoreThanZero.selector);
        dsce.burnDsc(0);
        vm.stopPrank();
    }

    function testCantBurnMoreThanUserHas() public {
        vm.prank(USER);
        vm.expectRevert();
        dsce.burnDsc(1);
    }

    function testRevertsIfRedeemAmountIsZero() public {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(dsce),AMOUNT_COLLATERAL);
        dsce.depositCollateralAndMintDsc(weth,AMOUNT_COLLATERAL,amountToMint);
        vm.expectRevert(DSCEngine.DSCEngine__NeedsMoreThanZero.selector);
        dsce.redeemCollateral(weth,0);
        vm.stopPrank();
    }

    function testMustRedeemMoreThanZero() public{
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(dsce),AMOUNT_COLLATERAL);
        dsce.depositCollateralAndMintDsc(weth,AMOUNT_COLLATERAL,amountToMint);
        vm.expectRevert(DSCEngine.DSCEngine__NeedsMoreThanZero.selector);
        dsce.redeemCollateralForDsc(weth,0,amountToMint);
        vm.stopPrank();
    }

    function testCanRedeemDepositedCollateral() public {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(dsce), AMOUNT_COLLATERAL);
        dsce.depositCollateralAndMintDsc(weth, AMOUNT_COLLATERAL, amountToMint);
        dsc.approve(address(dsce), amountToMint);
        dsce.redeemCollateralForDsc(weth, AMOUNT_COLLATERAL, amountToMint);
        vm.stopPrank();

        uint256 userBalance = dsc.balanceOf(USER);
        assertEq(userBalance, 0);
    }

    function testProperlyReportsHealthFactor() public depositedCollateralAndMintedDsc{

        uint256 expectedHealthFactor = 100 ether;
        uint256 actualHealthFactor = dsce.getHealthFactor(USER);
        assertEq(expectedHealthFactor,actualHealthFactor);

    }

     function testHealthFactorCanGoBelowOne() public depositedCollateralAndMintedDsc{

        int256 ethUsdPrice = 1e8;
        MockV3Aggregator(ethUsdPriceFeed).updateAnswer(ethUsdPrice);
        uint256 actualHealthFactor = dsce.getHealthFactor(USER);
        assert(actualHealthFactor < 1 ether);

     }
     
     
    



    



    

}
