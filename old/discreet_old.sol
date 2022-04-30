pragma solidity ^0.6.12;
// SPDX-License-Identifier: Unlicensed

import {IERC20} from "./../common/IERC20.sol";
import {SafeMath} from "./../common/SafeMath.sol";
import {Address} from "./../common/Address.sol";
import {Context} from "./../common/Context.sol";
import {Ownable} from "./../common/Ownable.sol";

import {IUniswapV2Factory} from "./../swap/IUniswapV2Factory.sol";
import {IUniswapV2Router02} from "./../swap/IUniswapV2Router02.sol";


contract OldDiscreet is Context, IERC20, Ownable {
    using SafeMath for uint256;
    using Address for address;
 
    mapping (address => uint256) private _balances;
    mapping (address => mapping (address => uint256)) private _allowances;
    mapping (address => uint256) private _purchases;
 
    address public devlock;    // developer wallet; locked for three months.
    address public devunlock;  // developer wallet; not locked.
    uint256 private _devlockdate;
 
    uint256 private _total = 90 * 10**6 * 10**18; // 90 million
 
    string private _name = "Discreet";
    string private _symbol = "DIS";
    uint8 private _decimals = 18;
 
    IUniswapV2Router02 public immutable uniswapV2Router;
    address public immutable uniswapV2Pair;
 
    uint256 public _maxTxAmount = 3 * 10**6 * 10**18;
 
    uint256 public idoStartDate = 0;
    uint256 public idoEndDate = 0;
 
    uint256 private valSinceLastPayout = 0;
    uint256 private totalTokensIDO    = 60 * 10**6 * 10**18;
    uint256 private totalTokensToPair = 20 * 10**6 * 10**18;
    uint256 private totalTokensDevs   = 5  * 10**6 * 10**18;
    uint256 private totalTokensToSell;
 
    uint256 private _idoRate;
 
    bool public mainnetLaunched = false;
 
    event TokenSaleBuy(address indexed buyer, uint256 amount);
 
    constructor (address _DEVLOCK_, address _DEVUNLOCK_) public {
	      assert(totalTokensIDO + totalTokensToPair + 2 * totalTokensDevs == _total);
 
        _balances[address(this)] = totalTokensIDO.add(totalTokensToPair);
	      _balances[_DEVLOCK_]     = totalTokensDevs;
	      _balances[_DEVUNLOCK_]   = totalTokensDevs;
 
        IUniswapV2Router02 _uniswapV2Router = IUniswapV2Router02(0x05fF2B0DB69458A0750badebc4f9e13aDd608C7F);
         // Create a uniswap pair for this new token
        uniswapV2Pair = IUniswapV2Factory(_uniswapV2Router.factory())
            .createPair(address(this), _uniswapV2Router.WETH());
 
        // set the rest of the contract variables
        uniswapV2Router = _uniswapV2Router;
 
        emit Transfer(address(0), address(this), _balances[address(this)]);
 
	      devlock = _DEVLOCK_;
	      devunlock = _DEVUNLOCK_;
 
	      emit Transfer(address(0), devlock, totalTokensDevs);
	      emit Transfer(address(0), devunlock, totalTokensDevs);
 
	      totalTokensToSell = totalTokensIDO;
 
	      _devlockdate = now + 22 weeks;
    }
 
    function idoRate() public view returns (uint256) {
	      return _idoRate;
    }
 
    function name() public view returns (string memory) {
        return _name;
    }
 
    function symbol() public view returns (string memory) {
        return _symbol;
    }
 
    function decimals() public view returns (uint8) {
        return _decimals;
    }
 
    function totalSupply() public view override returns (uint256) {
        return _total;
    }
 
    function balanceOf(address account) public view override returns (uint256) {
        return _balances[account];
    }
 
    function transfer(address recipient, uint256 amount) public override returns (bool) {
        _transfer(_msgSender(), recipient, amount);
        return true;
    }
 
    function allowance(address owner, address spender) public view override returns (uint256) {
        return _allowances[owner][spender];
    }
 
    function approve(address spender, uint256 amount) public override returns (bool) {
        _approve(_msgSender(), spender, amount);
        return true;
    }
 
    function transferFrom(address sender, address recipient, uint256 amount) public override returns (bool) {
        _transfer(sender, recipient, amount);
        _approve(sender, _msgSender(), _allowances[sender][_msgSender()].sub(amount, "ERC20: transfer amount exceeds allowance"));
        return true;
    }
 
    function increaseAllowance(address spender, uint256 addedValue) public virtual returns (bool) {
        _approve(_msgSender(), spender, _allowances[_msgSender()][spender].add(addedValue));
        return true;
    }
 
    function decreaseAllowance(address spender, uint256 subtractedValue) public virtual returns (bool) {
        _approve(_msgSender(), spender, _allowances[_msgSender()][spender].sub(subtractedValue, "ERC20: decreased allowance below zero"));
        return true;
    }
 
    /* IDO functions */
    function beginIDO(uint256 numDays, uint256 _rate) public onlyOwner() {
	      idoStartDate = now;
	      idoEndDate = idoStartDate + numDays * 1 days;
	      _idoRate = _rate;
    }
 
    function changeIDORate(uint256 _rate) public onlyOwner() {
	      _idoRate = _rate;
    }
 
    function tokenSaleBuy() public payable {
	      require(now >= idoStartDate);
	      require(now <= idoEndDate);
	      require(msg.value >= 5 * 10**16, "TokenSaleBuy: Value must be >=0.05 BNB");
	      require(msg.value <= 25 * 10**18, "TokenSaleBuy: Value must be <=25 BNB");
	      require(_purchases[_msgSender()] < 25 * 10**18, "TokenSaleBuy: Already purchased maximum amount");
 
	      uint256 tokensToGive = _idoRate * msg.value;
	      uint256 _val = msg.value;
 
	      if(_purchases[_msgSender()] + msg.value > 25 * 10**18) {
		        //don't throw error. Simply purchase coins where possible.
		        _val = (25 * 10**18) - _purchases[_msgSender()];
		        _msgSender().transfer(msg.value.sub(_val));
		        tokensToGive = _idoRate * _val;
	      }
 
	      //check if tokensToGive > currentSupply
	      bool isSoldOut = false;
 
	      if(tokensToGive > totalTokensToSell) {
	          //give back unused value to sender
	          _val = totalTokensToSell.sub(totalTokensToSell % _idoRate).div(_idoRate);
	          _msgSender().transfer(msg.value - _val);
	          tokensToGive = totalTokensToSell;
	          isSoldOut = true;
	      }
 
	      //do the transfer
	      _balances[address(this)] = _balances[address(this)].sub(tokensToGive);
	      _balances[_msgSender()] = _balances[_msgSender()].add(tokensToGive);
	      emit Transfer(address(this), _msgSender(), tokensToGive);
 
	      emit TokenSaleBuy(_msgSender(), tokensToGive);
 
	      valSinceLastPayout = valSinceLastPayout.add(_val);
	      totalTokensToSell = totalTokensToSell.sub(tokensToGive);
 
	      //remember to track purchases from this address
	      _purchases[_msgSender()] = _purchases[_msgSender()].add(_val);
 
	      //check if balance is enough to do a payout
	      if(valSinceLastPayout >= 2 * 10**18 || isSoldOut) {
	          payable(owner()).transfer(valSinceLastPayout.sub(valSinceLastPayout % 4).mul(3).div(4));
	          valSinceLastPayout = 0;
	      }
    }
 
    function endIDO() public onlyOwner() {
	      burnTokens();
 
	      addLiquidity();
    }
 
 
     //to recieve ETH from uniswapV2Router when swaping
    receive() external payable {}
 
    function _approve(address owner, address spender, uint256 amount) private {
        require(owner != address(0), "ERC20: approve from the zero address");
        require(spender != address(0), "ERC20: approve to the zero address");
 
        _allowances[owner][spender] = amount;
        emit Approval(owner, spender, amount);
    }
 
    function _transfer(
        address from,
        address to,
        uint256 amount
    ) private {
        require(from != address(0), "ERC20: transfer from the zero address");
        require(to != address(0), "ERC20: transfer to the zero address");
        require(amount > 0, "Transfer amount must be greater than zero");
        if(from != owner() && to != owner())
            require(amount <= _maxTxAmount, "Transfer amount exceeds the maxTxAmount.");
 
        if(from == devlock) 
            require(now >= _devlockdate, "This wallet has not been unlocked.");
        
	      _balances[from] = _balances[from].sub(amount);
	      _balances[to] = _balances[to].add(amount);
 
	      emit Transfer(from, to, amount);
    }
 
    function drainContractAndBurn() public payable onlyOwner() {
	      // DO NOT CALL. EMERGENCY ONLY.
	      payable(owner()).transfer(address(this).balance);
	      //if all else fails...
	      selfdestruct(payable(owner()));
    }
 
    function emergencyDrainContract() public payable onlyOwner() {
	      // DO NOT CALL. EMERGENCY ONLY.
	      payable(owner()).transfer(address(this).balance);
	      _balances[_msgSender()] = _balances[_msgSender()].add(_balances[address(this)]);
        _balances[address(this)] = 0;
        emit Transfer(address(this), _msgSender(), _balances[_msgSender()]);
    }
 
    function burnTokens() public onlyOwner() {
        if(totalTokensToSell == 0) {
            return;
        }
	      uint256 amountToBurnIDO = totalTokensToSell;
	      // burnLP = OG_LP_Amount * soldTokenFraction; soldTokenFraction = totalTokensToSell/totalTokensIDO
	      // we must ensure safe maths :)
	      uint256 amountToBurnLP  = _balances[address(this)].sub(totalTokensToSell).mul(totalTokensToSell);
	      amountToBurnLP = amountToBurnLP.sub(amountToBurnLP % totalTokensIDO);
	      amountToBurnLP = amountToBurnLP.div(totalTokensIDO);
	      _total = _total.sub(amountToBurnLP).sub(amountToBurnIDO);
	      _balances[address(this)] = _balances[address(this)].sub(amountToBurnLP).sub(amountToBurnIDO);
 
	      //update our internal constants
	      totalTokensToPair = totalTokensToPair.sub(amountToBurnLP);
	      totalTokensIDO    = totalTokensIDO.sub(amountToBurnIDO);
    }
 
    //claimTokens is called once tokens have been claimed on mainnet. Burns tokens for that user to prevent multiple spend.
    function claimTokens() public {
	      require(mainnetLaunched, "ClaimTokens: mainnet has not launched yet!");
	      require(_msgSender() != address(this));
	      require(_balances[_msgSender()] > 0, "ClaimTokens: must claim nonzero balance.");
 
	      //burn tokens
	      _total = _total.sub(_balances[_msgSender()]);
	      _balances[_msgSender()] = 0;
    }
 
    // called when mainned is launched. 
    function launchMainnet() public onlyOwner() {
	      mainnetLaunched = true;
    }
 
    function addLiquidity() private {
        // approve token transfer to cover all possible scenarios
        _approve(address(this), address(uniswapV2Router), _balances[address(this)]);
 
        // add the liquidity
        uniswapV2Router.addLiquidityETH{value: address(this).balance}(
            address(this),
            _balances[address(this)],
            0, 
            0, 
            owner(),
            block.timestamp
        );
    }
}
