pragma solidity ^0.6.12;
// SPDX-License-Identifier: Unlicensed

import {SafeMath} from "./../common/SafeMath.sol";
import {Address} from "./../common/Address.sol";
import {Context} from "./../common/Context.sol";
import {Ownable} from "./../common/Ownable.sol";
import {OldDiscreet} from "./discreet_old.sol";

import {IUniswapV2Router02} from "./swap/IUniswapV2Router02.sol";

contract DiscreetIDO2 is Context, Ownable {
	using SafeMath for uint256;
	using Address for address;

	mapping (address => uint256) private _purchases;

    uint256 private valSinceLastPayout = 0;
    uint256 private _idoRate;

    uint256 public idoStartDate = 0;
    uint256 public idoEndDate = 0;

    uint256 public minTokenBuy = 5 * 10**16;
    uint256 public maxTokenBuy = 25 * 10**18;

    uint256 public totalTokensToSell = 0;
    uint256 public totalTokensToPair = 20 * 10**6 * 10**18;

    IUniswapV2Router02 public immutable uniswapV2Router;
    address public immutable uniswapV2Pair;

    OldDiscreet _Discreet;

    event TokenSaleBuy(address indexed buyer, uint256 amount);

    constructor (uint256 _startRate, uint256 _totalTokensToSell) public {
        idoStartDate = now;
        idoEndDate = idoStartDate + 365 days;
        _idoRate = _startRate;
        totalTokensToSell = _totalTokensToSell;
        _Discreet = OldDiscreet(0x153ab47326A18209Cd24bBCDA4c5933714549e5E);

        uniswapV2Router = IUniswapV2Router02(0x05fF2B0DB69458A0750badebc4f9e13aDd608C7F);

        uniswapV2Pair = address(0x95eD635f91165764627fc659C0729d7E6F963E78);
    }

    function idoRate() public view returns (uint256) {
        return _idoRate;
    }

    function changeIDORate(uint256 _rate) public onlyOwner() {
        _idoRate = _rate;
    }

    function extendIDODate(uint256 _days) public onlyOwner() {
        idoEndDate += _days * 1 days;
    }

    function changeMinTokenBuy(uint256 _minTokenBuy) public onlyOwner() {
        minTokenBuy = _minTokenBuy;
    }

    function changeMaxTokenBuy(uint256 _maxTokenBuy) public onlyOwner() {
        maxTokenBuy = _maxTokenBuy;
    }

    function tokenSaleBuy() public payable {
        require(now >= idoStartDate);
	    require(now <= idoEndDate);
	    require(msg.value >= minTokenBuy, "TokenSaleBuy: Value must be >=0.05 BNB");
	    require(msg.value <= maxTokenBuy, "TokenSaleBuy: Value must be <=25 BNB");
	    require(_purchases[_msgSender()] <= maxTokenBuy, "TokenSaleBuy: Already purchased maximum amount");
    
        uint256 tokensToGive = _idoRate * msg.value;
        uint256 _val = msg.value;

        if(_purchases[_msgSender()] + msg.value > maxTokenBuy) {
            _val = maxTokenBuy - _purchases[_msgSender()];
            _msgSender().transfer(msg.value.sub(_val));
            tokensToGive = _idoRate * _val;
        }

        bool isSoldOut = false;

        if(tokensToGive > totalTokensToSell) {
            _val = totalTokensToSell.sub(totalTokensToSell % _idoRate).div(_idoRate);
            _msgSender().transfer(msg.value - _val);
            tokensToGive = totalTokensToSell;
            isSoldOut = true;
        }

        _Discreet.transfer(_msgSender(), tokensToGive);

        emit TokenSaleBuy(_msgSender(), tokensToGive);

        valSinceLastPayout = valSinceLastPayout.add(_val);
        totalTokensToSell = totalTokensToSell.sub(tokensToGive);

        _purchases[_msgSender()] = _purchases[_msgSender()].add(_val);

        if (valSinceLastPayout >= 2 * 10**18 || isSoldOut) {
            payable(owner()).transfer(valSinceLastPayout.sub(valSinceLastPayout % 4).mul(3).div(4));
	        valSinceLastPayout = 0;
        }
    }

    function burnTokens() public onlyOwner() {
        if (totalTokensToSell == 0) {
            return;
        }

        //we need to burn two amounts: from the LP, and from remaining IDO tokens.
        //totalIDO = 60mil, totalLP = 20mil, rate=DISperBNB.
        //burnamt = totalLP - rate*balance - valSinceLastPayout*0.75*rate

        uint256 burnAmount1 = address(this).balance.mul(_idoRate);
        uint256 burnAmount2 = valSinceLastPayout.mul(3) % 4;
        burnAmount2 = burnAmount2.div(4);
        burnAmount2 = burnAmount2.mul(_idoRate);

        uint256 totalBurnAmount = 20 * 10**6 * 10**18;
        totalBurnAmount = totalBurnAmount.sub(burnAmount1);
        totalBurnAmount = totalBurnAmount.sub(burnAmount2);
        totalBurnAmount = totalBurnAmount.add(totalTokensToSell);

        //burning is basically just sending to null address
        _Discreet.transfer(payable(address(0)), totalBurnAmount);
    }

    function claimTokens() public {
        _Discreet.claimTokens();
    }

    function launchMainnet() public onlyOwner() {
        _Discreet.launchMainnet();
    }

    function endIDO() public onlyOwner() {
        burnTokens();
        idoEndDate = now;
        addLiquidity();
    }

    function emergencyDrainContract() public payable onlyOwner() {
	    // DO NOT CALL. EMERGENCY ONLY.
	    payable(owner()).transfer(address(this).balance);
	    _Discreet.transfer(_msgSender(), _Discreet.balanceOf(address(this)));
    }

    receive() external payable {}

    function addLiquidity() private {
        // approve token transfer to cover all possible scenarios
        _Discreet.approve(address(uniswapV2Router), _Discreet.balanceOf(address(this)));
 
        // add the liquidity
        uniswapV2Router.addLiquidityETH{value: address(this).balance}(
            address(this),
            _Discreet.balanceOf(address(this)),
            0, 
            0, 
            owner(),
            block.timestamp
        );
    }
}
