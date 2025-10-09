// SPDX-License-Identifier:MIT

pragma solidity ^0.8.18;

import {DecentralizedStableCoin} from "./DecentralizedStableCoin.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.4/interfaces/AggregatorV3Interface.sol";

// import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

contract DSCEngine {
    ///////////////
    //  ERRORS   //
    ///////////////

    error DSCEngine__NeedsMoreThanZero();
    error DSCEngine__TokenFeedAndPriceFeedAddressesMustBeOfSamelength();
    error DSCEngine__NotAllowedToken();
    error DSCEngine__TransferFailed();
    error DSCEngine__BreaksHealthFactor(uint256 userHealthfactor);
    error DSCEngine__MintFailed();
    error DSCEngine__healthFactorOk();
    error DSCEngine__HealthFactorNotImproved();

    //////////////////////
    //  STATE VARIABLES //
    //////////////////////

    uint256 private constant LIQUIDATION_THRESHOLD = 50;
    uint256 private constant MIN_HEALTH_FACTOR = 1;
    mapping(address token => address priceFeed) private s_priceFeeds;
    mapping(address user => mapping(address token => uint256 amount)) private s_collateralDeposited;
    mapping(address user => uint256 amountDscMinted) private s_DSCMinted;

    address[] private s_collateralTokens;

    DecentralizedStableCoin public immutable i_dsc;

    ///////////////
    //  EVENTS   //
    ///////////////

    event CollateralDeposited(address indexed user, address indexed token, uint256 indexed _amount);
    event CollateralRedeemed(address indexed redeemedFrom,address indexed redeemedTo, address indexed token , uint256 amount);

    ///////////////
    // MODIFIERS //
    ///////////////

    modifier moreThanZero(uint256 amount) {
        if (amount <= 0) {
            revert DSCEngine__NeedsMoreThanZero();
            _;
        }
    }

    modifier isAllowedToken(address token){
        if(s_priceFeeds[token] == address(0)){
            revert DSCEngine__NotAllowedToken();
        }
        _;
    }

    ///////////////
    // FUNCTIONS //
    ///////////////

    constructor(address[] memory tokenAddresses, address[] memory priceFeedAddresses, address dscAddress) {
        if (tokenAddresses.length != priceFeedAddresses.length) {
            revert DSCEngine__TokenFeedAndPriceFeedAddressesMustBeOfSamelength();
        }
        for (uint256 i = 0; i < tokenAddresses.length; i++) {
            s_priceFeeds[tokenAddresses[i]] = priceFeedAddresses[i];
            s_collateralTokens.push(tokenAddresses[i]);
        }
        i_dsc = DecentralizedStableCoin(dscAddress);
    }

    function depositCollateral(address tokenCollateralAddress, uint256 amountCollateral) public isAllowedToken(tokenCollateralAddress)
    //  moreThanZero(amountCollateral)
    {
        
        // nonReentrant
        if(amountCollateral == 0){
            revert DSCEngine__NeedsMoreThanZero();
        }

        // this mapping will give us info about the user who sent us which token and how much
        s_collateralDeposited[msg.sender][tokenCollateralAddress] += amountCollateral;
        emit CollateralDeposited(msg.sender, tokenCollateralAddress, amountCollateral);
        bool success = IERC20(tokenCollateralAddress).transferFrom(msg.sender, address(this), amountCollateral);
        if (!success) {
            revert DSCEngine__TransferFailed();
        }
    }

    // check if the collateral value > DSC value
    // in this function user can tell how much he wants to mint
    function mintDsc(uint256 amountDscToMint) public {
        s_DSCMinted[msg.sender] += amountDscToMint;
        // here we will check if the want to mint more than collateral ($100 eth , 150dsc the want)
        _revertIfHealthFactorisBroken(msg.sender);
        bool minted = i_dsc.mint(msg.sender, amountDscToMint);
        if (!minted) {
            revert DSCEngine__MintFailed();
        }
    }

    function depositCollateralAndMintDsc(address tokenCollateralAddress, uint256 amountCollateral, uint256 amountDscToMint) public {
        depositCollateral(tokenCollateralAddress,amountCollateral);
        mintDsc(amountDscToMint);

    }


    function redeemCollateralForDsc(address tokenCollateralAddress , uint256 amountCollateral, uint256 amountDscToBurn) public {
        redeemCollateral(tokenCollateralAddress,amountCollateral);
        burnDsc(amountDscToBurn);

    }

    function redeemCollateral(address tokenCollateralAddress , uint256 amountCollateral) public {

        if(amountCollateral == 0){
            revert DSCEngine__NeedsMoreThanZero();
        }

        _redeemCollateral(msg.sender,msg.sender,tokenCollateralAddress,amountCollateral);

        // s_collateralDeposited[msg.sender][tokenCollateralAddress] -= amountCollateral;
        // emit CollateralRedeemed(msg.sender, tokenCollateralAddress, amountCollateral);
        // (bool success) = IERC20(tokenCollateralAddress).transfer(msg.sender,amountCollateral);
        // if(!success){
        //     revert DSCEngine__TransferFailed();
        // }
       
    }


    function burnDsc(uint256 amount) public {
        if(amount == 0){
            revert DSCEngine__NeedsMoreThanZero();
        }
        // s_DSCMinted[msg.sender] -= amount;
        // (bool success) = i_dsc.transferFrom(msg.sender, address(this), amount);
        // if(!success){
        //     revert DSCEngine__TransferFailed();
        // }
        // i_dsc.burn(amount);
        _burnDsc(amount,msg.sender,msg.sender);
         _revertIfHealthFactorisBroken(msg.sender);

    }



    function liquidate(address collateral, address user, uint256 debtToCover) external {
        if(debtToCover == 0){
            revert DSCEngine__NeedsMoreThanZero();
        }

        uint256 startingUserHealthFactor = _healthFactor(user);

        if(startingUserHealthFactor >= 1){
            revert DSCEngine__healthFactorOk();
        }

        uint256 tokenAmountFromDebtCovered = getTokenAmountFromUsd(collateral,debtToCover);

        uint256 bonusCollateral = (tokenAmountFromDebtCovered * 10)/100 ;

        uint256 totalCollateralToRedeem = (tokenAmountFromDebtCovered + bonusCollateral);

        _redeemCollateral(user, msg.sender, collateral, debtToCover);

        _burnDsc(debtToCover,user,msg.sender);

        uint256 endingUserHealthFactor = _healthFactor(user);
        if(endingUserHealthFactor <= startingUserHealthFactor){
            revert DSCEngine__HealthFactorNotImproved();
        }
        _revertIfHealthFactorisBroken(msg.sender);


        }

    

















    //////////////////////////////////
    //PRIVATE & INTERNAL FUNCTIONS //
    //////////////////////////////////


    function getTokenAmountFromUsd(address token, uint256 usdAmountInWei) public view returns(uint256){

        AggregatorV3Interface priceFeed = AggregatorV3Interface(s_priceFeeds[token]);
        (,int256 price,,,) = priceFeed.latestRoundData();

        return (usdAmountInWei * 1e18) / (uint256(price) * 1e10);

    }





    function _getAccountInformation(address user)
        private
        view
        returns (uint256 totalDscMinted, uint256 collateralValueInUsd)
    {
        totalDscMinted = s_DSCMinted[user];
        collateralValueInUsd = getAccountCollateralValue(user);
    }

    function _healthFactor(address user) private view returns (uint256) {
        // total DSC minted
        // total collateral value value
        (uint256 totalDscMinted, uint256 collateralValueInUsd) = _getAccountInformation(user);
        uint256 collateralAdjustedForThreshold = (collateralValueInUsd * LIQUIDATION_THRESHOLD) / 100;
        return (collateralAdjustedForThreshold * 1e18) / totalDscMinted;
    }

    function _revertIfHealthFactorisBroken(address user) internal view {
        // check health factor (do they have enough collateral)
        // revert if they dont
        uint256 userHealthfactor = _healthFactor(user);
        if (userHealthfactor < MIN_HEALTH_FACTOR) {
            revert DSCEngine__BreaksHealthFactor(userHealthfactor);
        }
    }

    //////////////////////////////////
    //  PUBLIC & EXTERNAL FUNCTIONS //
    //////////////////////////////////


    function _redeemCollateral( address from, address to, address tokenCollateralAddress , uint256 amountCollateral) private {

        s_collateralDeposited[from][tokenCollateralAddress] -= amountCollateral;
        emit CollateralRedeemed(from,to,tokenCollateralAddress,amountCollateral);
        (bool success) = IERC20(tokenCollateralAddress).transfer(to , amountCollateral);
        if(!success){
             revert DSCEngine__TransferFailed();

        }

    }


    function _burnDsc(uint256 amount, address onBehalfOf, address dscFrom) private {

    s_DSCMinted[onBehalfOf] -= amount;

    (bool success) = i_dsc.transferFrom(dscFrom, address(this),amount);
    if(!success){
        revert DSCEngine__TransferFailed();
    }

    i_dsc.burn(amount);

    }










    

    function getAccountCollateralValue(address user) public view returns (uint256 totalCollateralValueInUsd) {
        // loop throw each ccollateral token, get the amount they deposited, map it to
        // the price to get the usd value.
        for (uint256 i = 0; i < s_collateralTokens.length; i++) {
            address token = s_collateralTokens[i];
            uint256 amount = s_collateralDeposited[user][token];
            totalCollateralValueInUsd += getUsdValue(token, amount);
        }
        return totalCollateralValueInUsd;
    }

    function getUsdValue(address token, uint256 amount) public view returns (uint256) {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(s_priceFeeds[token]);
        (, int256 price,,,) = priceFeed.latestRoundData();
        // suppose 1 ETH = $1000
        // the returned value from CL will be 1000 * 1e8

        return ((uint256(price) * 1e10) * amount) / 1e18;
    }
}
