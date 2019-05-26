pragma solidity ^0.4.25;
import "./IToken.sol";
import "./LSafeMath.sol";
contract CpublicDex{
  using LSafeMath for uint;
  address public admin;
  address public feeAccount;
  uint public feeTake;
  uint public freeUntilDate;
  bool private depositingTokenFlag;
  mapping (address => mapping (address => uint)) public tokens;
  mapping (address => mapping (bytes32 => bool)) public orders;
  mapping (address => mapping (bytes32 => uint)) public orderFills;
  address public predecessor;
  address public successor;
  uint16 public version;
  event Order(address tokenGet, uint amountGet, address tokenGive, uint amountGive, uint expires, uint nonce, address user);
  event Cancel(address tokenGet, uint amountGet, address tokenGive, uint amountGive, uint expires, uint nonce, address user, uint8 v, bytes32 r, bytes32 s);
  event Trade(address tokenGet, uint amountGet, address tokenGive, uint amountGive, address get, address give);
  event Deposit(address token, address user, uint amount, uint balance);
  event Withdraw(address token, address user, uint amount, uint balance);
  event FundsMigrated(address user, address newContract);
  modifier isAdmin() {
      require(msg.sender == admin);
      _;
  }
  constructor (address admin_, address feeAccount_, uint feeTake_, uint freeUntilDate_, address predecessor_) public {
    admin = admin_;
    feeAccount = feeAccount_;
    feeTake = feeTake_;
    freeUntilDate = freeUntilDate_;
    depositingTokenFlag = false;
    predecessor = predecessor_;
    if (predecessor != address(0)) {
      version = CpublicDex(predecessor).version() + 1;
    } else {
      version = 1;
    }
  }
  function() public {
    revert();
  }
  function changeAdmin(address admin_) public isAdmin {
    require(admin_ != address(0));
    admin = admin_;
  }
  function changeFeeAccount(address feeAccount_) public isAdmin {
    feeAccount = feeAccount_;
  }
  function changeFeeTake(uint feeTake_) public isAdmin {
    require(feeTake_ <= feeTake);
    feeTake = feeTake_;
  }
  function changeFreeUntilDate(uint freeUntilDate_) public isAdmin {
    freeUntilDate = freeUntilDate_;
  }
  function setSuccessor(address successor_) public isAdmin {
    require(successor_ != address(0));
    successor = successor_;
  }
  function deposit() public payable {
    tokens[0][msg.sender] = tokens[0][msg.sender].add(msg.value);
    emit Deposit(0, msg.sender, msg.value, tokens[0][msg.sender]);
  }
  function withdraw(uint amount) public {
    require(tokens[0][msg.sender] >= amount);
    tokens[0][msg.sender] = tokens[0][msg.sender].sub(amount);
    msg.sender.transfer(amount);
    emit Withdraw(0, msg.sender, amount, tokens[0][msg.sender]);
  }
  function depositToken(address token, uint amount) public {
    require(token != 0);
    depositingTokenFlag = true;
    require(IToken(token).transferFrom(msg.sender, this, amount));
    depositingTokenFlag = false;
    tokens[token][msg.sender] = tokens[token][msg.sender].add(amount);
    emit Deposit(token, msg.sender, amount, tokens[token][msg.sender]);
 }
  function withdrawToken(address token, uint amount) public {
    require(token != 0);
    require(tokens[token][msg.sender] >= amount);
    tokens[token][msg.sender] = tokens[token][msg.sender].sub(amount);
    require(IToken(token).transfer(msg.sender, amount));
    emit Withdraw(token, msg.sender, amount, tokens[token][msg.sender]);
  }
  function balanceOf(address token, address user) public constant returns (uint) {
    return tokens[token][user];
  }
  function order(address tokenGet, uint amountGet, address tokenGive, uint amountGive, uint expires, uint nonce) public {
    bytes32 hash = keccak256(abi.encodePacked(this, tokenGet, amountGet, tokenGive, amountGive, expires, nonce));
    orders[msg.sender][hash] = true;
    emit Order(tokenGet, amountGet, tokenGive, amountGive, expires, nonce, msg.sender);
  }
  function trade(address tokenGet, uint amountGet, address tokenGive, uint amountGive, uint expires, uint nonce, address user, uint8 v, bytes32 r, bytes32 s, uint amount) public {
    bytes32 hash = keccak256(abi.encodePacked(this, tokenGet, amountGet, tokenGive, amountGive, expires, nonce));
    require((
      (orders[user][hash] || ecrecover(keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", hash)), v, r, s) == user) &&
      block.number <= expires &&
      orderFills[user][hash].add(amount) <= amountGet
    ));
    tradeBalances(tokenGet, amountGet, tokenGive, amountGive, user, amount);
    orderFills[user][hash] = orderFills[user][hash].add(amount);
    emit Trade(tokenGet, amount, tokenGive, amountGive.mul(amount) / amountGet, user, msg.sender);
  }
  function tradeBalances(address tokenGet, uint amountGet, address tokenGive, uint amountGive, address user, uint amount) private {

    uint feeTakeXfer = 0;

    if (now >= freeUntilDate) {
      feeTakeXfer = amount.mul(feeTake).div(1 ether);
    }

    tokens[tokenGet][msg.sender] = tokens[tokenGet][msg.sender].sub(amount.add(feeTakeXfer));
    tokens[tokenGet][user] = tokens[tokenGet][user].add(amount);
    tokens[tokenGet][feeAccount] = tokens[tokenGet][feeAccount].add(feeTakeXfer);
    tokens[tokenGive][user] = tokens[tokenGive][user].sub(amountGive.mul(amount).div(amountGet));
    tokens[tokenGive][msg.sender] = tokens[tokenGive][msg.sender].add(amountGive.mul(amount).div(amountGet));
  }
  function testTrade(address tokenGet, uint amountGet, address tokenGive, uint amountGive, uint expires, uint nonce, address user, uint8 v, bytes32 r, bytes32 s, uint amount, address sender) public constant returns(bool) {
    if (!(
      tokens[tokenGet][sender] >= amount &&
      availableVolume(tokenGet, amountGet, tokenGive, amountGive, expires, nonce, user, v, r, s) >= amount
      )) {
      return false;
    } else {
      return true;
    }
  }
  function availableVolume(address tokenGet, uint amountGet, address tokenGive, uint amountGive, uint expires, uint nonce, address user, uint8 v, bytes32 r, bytes32 s) public constant returns(uint) {
    bytes32 hash = keccak256(abi.encodePacked(this, tokenGet, amountGet, tokenGive, amountGive, expires, nonce));
    if (!(
      (orders[user][hash] || ecrecover(keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", hash)), v, r, s) == user) &&
      block.number <= expires
      )) {
      return 0;
    }
    uint[2] memory available;
    available[0] = amountGet.sub(orderFills[user][hash]);
    available[1] = tokens[tokenGive][user].mul(amountGet) / amountGive;
    if (available[0] < available[1]) {
      return available[0];
    } else {
      return available[1];
    }
  }
  function cancelOrder(address tokenGet, uint amountGet, address tokenGive, uint amountGive, uint expires, uint nonce, uint8 v, bytes32 r, bytes32 s) public {
    bytes32 hash = keccak256(abi.encodePacked(this, tokenGet, amountGet, tokenGive, amountGive, expires, nonce));
    require ((orders[msg.sender][hash] || ecrecover(keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", hash)), v, r, s) == msg.sender));
    orderFills[msg.sender][hash] = amountGet;
    emit Cancel(tokenGet, amountGet, tokenGive, amountGive, expires, nonce, msg.sender, v, r, s);
  }
  function migrateFunds(address newContract, address[] tokens_) public {
    require(newContract != address(0));
    CpublicDex newExchange = CpublicDex(newContract);
    uint etherAmount = tokens[0][msg.sender];
    if (etherAmount > 0) {
      tokens[0][msg.sender] = 0;
      newExchange.depositForUser.value(etherAmount)(msg.sender);
    }
    for (uint16 n = 0; n < tokens_.length; n++) {
      address token = tokens_[n];
      require(token != address(0));
      uint tokenAmount = tokens[token][msg.sender];
      if (tokenAmount != 0) {
      	require(IToken(token).approve(newExchange, tokenAmount));
      	tokens[token][msg.sender] = 0;
      	newExchange.depositTokenForUser(token, tokenAmount, msg.sender);
      }
    }
    emit FundsMigrated(msg.sender, newContract);
  }
  function depositForUser(address user) public payable {
    require(user != address(0));
    require(msg.value > 0);
    tokens[0][user] = tokens[0][user].add(msg.value);
  }
  function depositTokenForUser(address token, uint amount, address user) public {
    require(token != address(0));
    require(user != address(0));
    require(amount > 0);
    depositingTokenFlag = true;
    require(IToken(token).transferFrom(msg.sender, this, amount));
    depositingTokenFlag = false;
    tokens[token][user] = tokens[token][user].add(amount);
  }
}
