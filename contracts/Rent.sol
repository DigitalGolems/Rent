// SPDX-License-Identifier: MIT

pragma experimental ABIEncoderV2;
pragma solidity 0.8.10;

import "../../DigitalGolems/Card.sol";
import "../../Digibytes/Digibytes.sol";
import "../Laboratory/Conservation.sol";
import "../../Utils/SafeMath.sol";
import "../../Utils/Owner.sol";
import "@openzeppelin/contracts/utils/Counters.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

contract Rent is Owner {
    using Counters for Counters.Counter;

    Counters.Counter private _itemsListedForRent;
    Counters.Counter private _itemsClosedRent;
    Counters.Counter private _itemsRented;
    Counters.Counter private _items;

    uint32 secondsInADay = 86400;

    Card public card;
    Conservation public conservation;

    using SafeMath for uint;
    using SafeMath32 for uint32;
    using SafeMath16 for uint16;

    struct CardForRent {
        uint256 itemID;
        uint256 cardID;
        address cardRenter;
        uint8 timeToRent; // for example user can use it 7 days - secondsInADay * 7 days
        bool rented;
        bool closed; //deleted from market
        uint256 timeWhenRentStarted;
        uint256 priceByDay;
        uint256 deposit;
    }

    CardForRent[] marketItems;
    mapping(uint256 => uint256) itemIDToFeedDeposit;
    uint256 thisDBTBalance;

    Digibytes public DBT;

    //creating market order for our golem to rent it
    //modifier checks if we already create it
    function createOrder(
        uint256 cardID,     //cardID that also equals to NFT ID
        uint256 price,      //price by day in Wei
        uint8 timeInDays    //time in days (MAX = 63 days)
    ) 
        external 
        onlyIfCardNotAlreadyAdded(cardID)
    {
        //checks sender equal to card owner
        require(msg.sender == card.cardOwner(cardID), "Your not owner");
        //checks if golem fed on maximum - all abilities in normal state
        require(card.isAllInitialAbilities(cardID) == true, "Please feed golem");
        //price cant be 0
        require(price > 0, "Price is zero");
        //time in days cant be 0
        require((timeInDays >= 7) && (timeInDays <= 30), "Time is 7 - 30 days");
        //adding to our items
        marketItems.push(CardForRent(
            _items.current(),
            cardID,     //cardID
            address(0), //cardRenter,
            timeInDays, //timeToRent,
            false,      //rented,
            false,      //closed
            0,          //timeWhenRentStarted,
            price,      //priceByDay,
            0           //deposit
        ));
        //listed items +1
        _itemsListedForRent.increment();
        //all items +1
        _items.increment();
    }

    //changing market order time
    //first modifier says - this can do only card owner
    //second checks if item exist and not rented
    function changeOrderTimeToRent(
        uint256 itemID,      //ID of created order
        uint8 _newTimeToRent //new time in days (MAX = 63)
    )
        public
        onlyCardOwner(itemID) 
        itemClosedNorRented(itemID) 
    {
        marketItems[itemID].timeToRent = _newTimeToRent;
    }

    function changeOrderPrice(
        uint256 itemID,     //ID of created order
        uint256 _price      //new price by day in Wei
    )
        public
        onlyCardOwner(itemID) 
        itemClosedNorRented(itemID) 
    {
        marketItems[itemID].priceByDay = _price;
    }

    //closing market item
    //from this time it wouldnt be seen on the market
    //this must be called before transfer
    //modifier checks sender equal to card owner
    function closeOrder(
        uint256 itemID
    ) public onlyCardOwner(itemID) {
        //it should be ended by owner and withdraw
        require(isRented(itemID) == false, "Please end rent");
        //writing data
        _itemsClosedRent.increment();
        _itemsListedForRent.decrement();
        marketItems[itemID].closed = true;
    }

    //reopen closed order
    function openOrder(
        uint256 itemID
    ) public onlyCardOwner(itemID) {
        //it should be closed
        require(marketItems[itemID].closed == true, "Its already open");
        //writing data
        _itemsClosedRent.decrement();
        _itemsListedForRent.increment();
        marketItems[itemID].closed = false;
    }

    //calls by card owner
    //if rent ended we transfer DBT to card owner
    //also it counts fed deposit what and who
    function endRentAndWithdrawOwner(
        uint256 itemID
    ) public onlyCardOwner(itemID) {
        //checks rent is ended
        require(isRentEnded(itemID) == true, "Rent not ended");
        _endRentAndWithdraw(itemID);
    }

    //calls by renter for take back feed deposit
    function endRentAndWithdrawFeedDepositRenter(
        uint256 itemID
    ) public {
        require(isRentEnded(itemID) == true, "Rent not ended");
        require(msg.sender == marketItems[itemID].cardRenter, "You not renter");
        _endRentAndWithdraw(itemID);
    }

    function _endRentAndWithdraw(uint256 _itemID) private {
        //it rented == true
        //means that if renter/owner call it before it call owner/renter
        //owner/renter cant calls it again
        require(isRented(_itemID) == true, "Already ended");
        //sending earned DBT to owner
        DBT.transfer(_getCardOwnerByItemID(_itemID), marketItems[_itemID].deposit);
        //operating fed deposit
        takeFedDeposit(_itemID);
        //writing data
        marketItems[_itemID].cardRenter = address(0);
        marketItems[_itemID].timeWhenRentStarted = 0;
        marketItems[_itemID].rented = false;
        marketItems[_itemID].deposit = 0;
        _itemsRented.decrement();
    }

    //calls by endRent
    //take fed deposit and transfer it to owner or renter
    //direction depends from changing max ability
    function takeFedDeposit(uint256 _itemID) private {
        //if golems abilitis not in normal state (means not in initial)
        if (card.isAllInitialAbilities(marketItems[_itemID].cardID) == false) {
            //counting difference between initial value and actual of max ability
            //that means we should to fed golem to get this max ability
            uint16 _diff = card.diffrenceBetweenInitialAndActualMaxAbilities(marketItems[_itemID].cardID);
            //transfer to card owner fed deposit difference multiplyed by feeding price from fed deposit
            DBT.transfer(_getCardOwnerByItemID(_itemID), conservation.getFeedingPrice() * _diff);
            //changing fed deposit with considering difference
            itemIDToFeedDeposit[_itemID] = itemIDToFeedDeposit[_itemID] - conservation.getFeedingPrice() * _diff;
            //if fed deposit not 0 we send it to renter
            //otherwise will be revert
            if (itemIDToFeedDeposit[_itemID] != 0) {
                DBT.transfer(marketItems[_itemID].cardRenter, itemIDToFeedDeposit[_itemID]);
            }
        } else {
            //all fed deposit sended to renter
            DBT.transfer(marketItems[_itemID].cardRenter, itemIDToFeedDeposit[_itemID]);
        }
    }

    //rent order
    //here contract take commision 0,3% from deposit
    //modifier checks if item exist and not rented
    function rentOrder(
        uint256 itemID
    ) 
        external 
        itemClosedNorRented(itemID) 
    {
        //counting amount to pay for rent priceByDay multiplied by timeToRent(days)
        uint256 amount = marketItems[itemID].priceByDay * marketItems[itemID].timeToRent;
        //counting fed deposit
        uint256 fedDeposit = countFedDeposit(itemID);
        //checks if user has this amount + fed deposit on balance and allowance to us
        require(DBT.balanceOf(msg.sender) >= amount + fedDeposit, "Balance too small");
        require(DBT.allowance(msg.sender, address(this)) >= amount + fedDeposit, "Contract cant use your money");
        //writing data
        _itemsRented.increment();
        marketItems[itemID].cardRenter = msg.sender;
        marketItems[itemID].rented = true;
        marketItems[itemID].timeWhenRentStarted = block.timestamp;
        //transfer to dbt to contract
        DBT.transferFrom(msg.sender, address(this), amount + fedDeposit);
        //deposit(earned money by card owner) = 99,7% of amount because contract take commission 0,3%
        marketItems[itemID].deposit = amount * 997 / 1000;
        //contract balance + 0,3% of amount
        thisDBTBalance = amount - marketItems[itemID].deposit;
        //write fed deposit
        itemIDToFeedDeposit[itemID] = fedDeposit;
    }

    //counting fed deposit for rent order
    function countFedDeposit(uint256 itemID) private view returns(uint256) {
        //getting golems max ability
        (uint16 maxAbility,) = card.getMaxAbility(marketItems[itemID].cardID);
        //max ability multiply by feeding price
        uint256 fedDeposit = conservation.getFeedingPrice() * maxAbility;
        return fedDeposit;
    }

    function _getCardOwnerByItemID(uint256 _itemID) private view returns(address) {
        return card.cardOwner(marketItems[_itemID].cardID);
    }

    function getUserDeposit(uint256 itemID) public view onlyCardOwner(itemID) returns(uint256) {
        return marketItems[itemID].deposit;
    }

    function isRentEnded(uint256 itemID) public view returns(bool) {
        return block.timestamp >
             marketItems[itemID].timeWhenRentStarted + (marketItems[itemID].timeToRent * secondsInADay);
    }

    function isRented(uint256 itemID) public view returns(bool) {
        return marketItems[itemID].rented;
    }

    function isClosed(uint256 itemID) public view returns(bool) {
        return marketItems[itemID].closed;
    }

    function getUserRenter(uint256 itemID) public view returns(address) {
        if (isRented(itemID) == false) {
            return address(0);
        }
        if (isRentEnded(itemID) == true) {

            return address(0);
        }
        return marketItems[itemID].cardRenter;
    }

    function getItemIDByCardID(uint256 cardID) public view returns(uint256, bool) {
        uint256 _itemID;
        bool exist;
        for (uint256 i = 0; i < marketItems.length; i++) {
            if (marketItems[i].cardID == cardID) {
                _itemID = marketItems[i].itemID;
                exist = true;
            }
        }
        return (_itemID, exist);
    }

    //FETCHING BLOCK
    function fetchCardOnMarket() public view returns (CardForRent[] memory) {
        CardForRent[] memory listed = new CardForRent[](_itemsListedForRent.current());
        for (uint256 i = 0; i < marketItems.length; i++) {
            if ((marketItems[i].rented == false) && (marketItems[i].closed == false)){
                listed[i] = marketItems[i];
            }
        }
        return listed;
    }

    function fetchUserCardOnMarket(address user) public view returns (CardForRent[] memory) {
        CardForRent[] memory userListed = new CardForRent[](card.cardCount(user));
        for (uint256 i = 0; i < marketItems.length; i++) {
            if (_getCardOwnerByItemID(i) == user){
                userListed[i] = marketItems[i];
            }
        }
        return userListed;
    }

    function fetchRenterCardOnMarket(address renter) public view returns (CardForRent[] memory) {
        CardForRent[] memory rented = new CardForRent[](_itemsRented.current());
        for (uint256 i = 0; i < marketItems.length; i++) {
            if (marketItems[i].cardRenter == renter) {
                rented[i] = marketItems[i];
            }
        }
        return rented;
    }

    //OWNER FUNCTIONS
    function withdrawDBTOwner() public isOwner {
        DBT.transfer(msg.sender, thisDBTBalance);
    }

    function getThisDBTBalance() public view isOwner returns(uint256) {
        return thisDBTBalance;
    }

    function setDBT(address _dbt) public isOwner {
        DBT = Digibytes(_dbt);
    }

    function setCard(address _card) public isOwner {
        card = Card(_card);
    }

    function setConserve(address _conserve) public isOwner {
        conservation = Conservation(_conserve);
    }

    //TESTING
    function mockTime(uint256 itemID, uint256 _newTime) public isOwner {
        marketItems[itemID].timeWhenRentStarted = _newTime;
    }

    //MODIFIERS
    modifier onlyIfCardNotAlreadyAdded(uint256 _cardID) {
        for (uint256 i = 0; i < _items.current(); i++){
            require(marketItems[i].cardID != _cardID, "Already exist");
        }
        _;
    }

    modifier onlyCardOwner(uint256 _itemID) {
        require(msg.sender == _getCardOwnerByItemID(_itemID), "You not owner of card");
        _;
    }

    modifier itemClosedNorRented(uint256 _itemID) {
        require(marketItems[_itemID].rented == false, "Item already rented");
        require(marketItems[_itemID].closed == false, "Item closed");
        _;
    }

}