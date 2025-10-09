// SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

import {Test} from "forge-std/Test.sol";
import {DSCEngine} from "../../src/DSCEngine.sol";
import {DecentralizedStableCoin} from "../../src/DecentralizedStableCoin.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {DeployDSC} from "../../script/DeployDSC.s.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";


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

    function setUp() public {
        deployer = new DeployDSC();
        // as our deployer returns dsc and dsce so 
        (dsc,dsce,config) = deployer.run();
        (ethUsdPriceFeed,btcUsdPriceFeed,weth,,) = config.activeNetworkConfig();
        ERC20Mock(weth).mint(USER,STARTING_ERC20_BALANCE);
       
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
        new DSCEngine(tokenAddresses,priceFeedAddresses,address(dsc));

    }






    

    ///////////////////
    //  PRICE TESTS  //
    ///////////////////

    function testGetUsdValue() public {
        uint256 ethAmount = 15e18;
        // 15e18 * 2000e18 = 30000e18
        uint256 expectedUsd = 30000e18;
        uint256 actualUsd = dsce.getUsdValue(weth,ethAmount);
        assertEq(expectedUsd,actualUsd);
    }


    function testgetTokenAmountFromUsd() public {
        uint256 usdAmount = 100 ether;
        // 2000/100 = 0.05
        uint256 expectedWeth = 0.05 ether;

        uint256 actualWeth = dsce.getTokenAmountFromUsd(weth,usdAmount);
        assertEq(expectedWeth,actualWeth);
    }

    ////////////////////////////////
    //  DEPOSIT COLLATERAL TESTS  //
    ////////////////////////////////

    function testRevertsIfCollateralIsZero() public {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(dsce),AMOUNT_COLLATERAL);

        vm.expectRevert(DSCEngine.DSCEngine__NeedsMoreThanZero.selector);
        dsce.depositCollateral(weth,0);
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

    modifier deplositCollateral(){
        vm.startPrank(USER);
        ERC20Mock(weth).transfer(address(dsce),AMOUNT_COLLATERAL);
        dsce.depositCollateral(weth,AMOUNT_COLLATERAL);
        vm.stopPrank();
        _;
    }
    

    // function testCanDepositCollateralAndGetAccountInfo() public deplositCollateral{

    //     (uint256 totalDscMinted, uint256 collateralValueInUsd) = dsce.getAccountInfomation(USER);

    //     uint256 expectedTotalDscMinted = 0;
    //     uint256 expectedCollateralValueInUsd = dsce.getTokenAmountFromUsd(weth,collateralValueInUsd);

    //     assertEq(totalDscMinted, expectedTotalDscMinted);
    //     assertEq(AMOUNT_COLLATERAL, expectedCollateralValueInUsd);

    
    // }




}