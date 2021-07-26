pragma solidity ^0.6.2;
import "./Pool.sol";

struct Options {
    BasicOptionsContract.State state;
    address holder;
    uint strike;
    uint amount;
    uint expiration;
}

contract BasicOptionsContract is Ownable {
    enum State{ Undefined, Active, Released }
    
    Options[] public OptionStorage;
    uint nextOptionsID;
    uint priceDecimals = 1e8;
    
    ILiquidityPool public pool;
    IPriceProvider public priceProvider;
    IUniswapFactory public exchanges;
    
    event OptionsCreated(address indexed account, uint id);
    
    constructor(ILiquidityPool lp, IPriceProvider pp, IUniswapFactory ex) public {
        pool = lp;
        priceProvider = pp;
        exchanges = ex;
    }
    
    function createOptions(uint period, uint amount) public payable returns (uint OptionsID) {
        require(period <= 8 weeks,"Period is too large");
        (uint strike, uint premium, uint fee) = fees(period, amount);
        require(msg.value >= fee + premium, "Value is too low");
        if(msg.value > fee + premium)
            msg.sender.transfer(msg.value - fee - premium);
        
        exchanges.getExchange(pool.token())
            .ethToTokenTransferInput.value(premium)(1, now + 1 minutes, address(pool));
        
        payable( owner() ).transfer(fee);
        
        pool.lock(strike);
        OptionsID = OptionStorage.length;
        OptionStorage.push(
            Options(State.Active, msg.sender, strike, amount, now + period)
        );
        emit OptionsCreated(msg.sender, OptionsID);
    }

    function release(uint OptionsID) public payable {
        Options storage Options = OptionStorage[OptionsID];
        require(Options.expiration >= now, 'Options has expired');
        require(Options.holder == msg.sender);
        require(Options.state == State.Active);
        require(Options.amount == msg.value);
        
        exchanges.getExchange(pool.token())
            .ethToTokenTransferInput.value(msg.value)(1, now + 1 minutes, address(pool));
            
        pool.send(Options.holder, Options.strike);
        
        Options.state = State.Released;
    }
    
    function fees(uint period, uint amount) public view returns (uint strike, uint premium, uint fee) {
        uint price = priceProvider.currentAnswer();
        strike = amount * price / priceDecimals;
        premium = amount * period / 7 days * 2/100; // 2% weekly
        fee = amount / 100; // 1%
    }
    
    function unlock(uint OptionsID) public {
        Options storage Options = OptionStorage[OptionsID];
        require(Options.expiration < now);
        require(Options.state == State.Active);
        pool.unlock(Options.strike);
        Options.state = State.Released;
    }    
}

contract OptionsContract is BasicOptionsContract {
    constructor(IERC20 token, IPriceProvider pp, IUniswapFactory ex) BasicOptionsContract(new Pool(token), pp, ex) public {}
}