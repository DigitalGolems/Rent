// SPDX-License-Identifier: MIT

pragma experimental ABIEncoderV2;
pragma solidity 0.8.10;

import "../../DigitalGolems/DigitalGolems.sol";
import "../../Digibytes/Digibytes.sol";
import "../../Utils/SafeMath.sol";
import "../../Utils/Owner.sol";
import "@openzeppelin/contracts/utils/Counters.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

contract Rent is Card, Owner {
    using Counters for Counters.Counter;

    Counters.Counter private _itemsListedForRent;
    Counters.Counter private _itemsClosedRent;
    Counters.Counter private _itemsRented;
    Counters.Counter private _items;

    uint32 secondsInADay = 86400;

    using SafeMath for uint;
    using SafeMath32 for uint32;
    using SafeMath16 for uint16;

    struct CardForRent {
        uint256 itemID;
        uint256 cardID;
        address cardOwner;
        address cardRenter;
        uint8 timeToRent; // for example user can use it 7 days - secondsInADay * 7 days
        uint256 timeWhenRentStarted;
        uint256 priceByDay;
        bool rented;
        bool closed; //deleted from market
    }

    CardForRent[] marketItems;
    mapping(uint256 => uint256) itemIDToDeposit;
    uint256 thisDBTBalance;

    DigitalGolems public DIG;
    Digibytes public DBT;

    function setDIG(address _dig) public isOwner {
        DIG = DigitalGolems(_dig);
    }

    function setDBT(address _dbt) public isOwner {
        DBT = Digibytes(_dbt);
    }

    function createMarketRent(
        uint256 cardID,
        uint256 price,
        uint8 timeInDays
    ) external onlyIfCardNotAlreadyAdded(cardID) {
        require(msg.sender == DIG.ownerOf(cardID), "Your not owner");
        require(price > 0, "Price is zero");
        require(timeInDays > 0, "Time is zero");
        marketItems.push(CardForRent(
            _items.current(),
            cardID,     //cardID
            msg.sender, //cardOwner,
            address(0), //cardRenter,
            timeInDays, //timeToRent,
            0,          //timeWhenRentStarted,
            price,      //priceByDay,
            false,      //rented,
            false       //closed
        ));
        _itemsListedForRent.increment();
        _items.increment();
    }

    function changeMarketItemTimeToRent(
        uint256 itemID,
        uint8 _newTimeToRent
    )
        public
        onlyItemOwner(itemID) 
        itemExistOrNotRented(itemID) 
    {
        marketItems[itemID].timeToRent = _newTimeToRent;
    }

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
        CardForRent[] memory userListed = new CardForRent[](DIG.balanceOf(user));
        for (uint256 i = 0; i < marketItems.length; i++) {
            if (marketItems[i].cardOwner == user){
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

    function closeMarketRent(
        uint256 itemID
    ) external {
        require(marketItems[itemID].cardOwner == msg.sender, "Your not owner");
        require(
            block.timestamp > marketItems[itemID].timeWhenRentStarted + (marketItems[itemID].timeToRent * secondsInADay),
            "Rent not ended"
            );
        _itemsListedForRent.decrement(); 
        _itemsClosedRent.increment();
        _itemsRented.decrement();
        marketItems[itemID].rented = false;
        marketItems[itemID].timeWhenRentStarted = 0;
        marketItems[itemID].cardRenter = address(0);
        marketItems[itemID].closed = true;
    }

    //here commision 0,3%
    function buyMarketRent(
        uint256 itemID
    ) external itemExistOrNotRented(itemID) {
        uint256 amount = marketItems[itemID].priceByDay * marketItems[itemID].timeToRent;
        require(DBT.balanceOf(msg.sender) >= amount, "Balance too small");
        require(DBT.allowance(msg.sender, address(this)) >= amount, "Contract cant use your money");
        _itemsRented.increment();
        marketItems[itemID].cardRenter = msg.sender;
        marketItems[itemID].rented = true;
        marketItems[itemID].timeWhenRentStarted = block.timestamp;
        DBT.transferFrom(msg.sender, address(this), amount);
        itemIDToDeposit[itemID] = amount * 997 / 1000; //99,7% because we get commision 0,3%
        thisDBTBalance = amount - (amount * 997 / 1000);
    }

    function endRentAndWithdraw(
        uint256 itemID
    ) external onlyItemOwner(itemID) {
        require(isRentEnded(itemID) == true, "Rent not ended");
        marketItems[itemID].cardRenter = address(0);
        marketItems[itemID].timeWhenRentStarted = 0;
        marketItems[itemID].rented = false;
        _itemsListedForRent.decrement();
        _itemsClosedRent.increment();
        _itemsRented.decrement();
        DBT.transfer(marketItems[itemID].cardOwner, itemIDToDeposit[itemID]);
    }

    function withdrawDBTOwner() public isOwner {
        DBT.transfer(msg.sender, thisDBTBalance);
    }

    function getThisDBTBalance() public view isOwner returns(uint256) {
        return thisDBTBalance;
    }

    function getUserDeposit(uint256 itemID) public view onlyItemOwner(itemID) returns(uint256) {
        return itemIDToDeposit[itemID];
    }

    function isRentEnded(uint256 itemID) public view returns(bool) {
        return (
            block.timestamp >
             marketItems[itemID].timeWhenRentStarted + (marketItems[itemID].timeToRent * secondsInADay)
        );
    }

    function isRented(uint256 itemID) public view returns(bool) {
        return marketItems[itemID].rented;
    }

    function getUserRenter(uint256 itemID) public view returns(address) {
        return marketItems[itemID].cardRenter;
    }

    function getItemIDByCardID(uint256 cardID) public view returns(uint256) {
        uint256 _itemID;
        for (uint256 i = 0; i < marketItems.length; i++) {
            if (marketItems[i].cardID == cardID) {
                _itemID = marketItems[i].itemID;
            }
        }
        return _itemID;
    }

    function mockTime(uint256 itemID, uint256 _newTime) public isOwner {
        marketItems[itemID].timeWhenRentStarted = _newTime;
    }

    modifier onlyIfCardNotAlreadyAdded(uint256 _cardID) {
        for (uint256 i = 0; i < _items.current(); i++){
            require(marketItems[i].cardID != _cardID, "Already exist");
        }
        _;
    }

    modifier onlyItemOwner(uint256 _itemID) {
        require(marketItems[_itemID].cardOwner == msg.sender, "You not owner of item");
        _;
    }

    modifier itemExistOrNotRented(uint256 _itemID) {
        require(marketItems[_itemID].cardOwner != address(0), "Item doesn exist");
        require(marketItems[_itemID].rented == false, "Item already rented");
        require(marketItems[_itemID].closed == false, "Item closed");
        _;
    }

}