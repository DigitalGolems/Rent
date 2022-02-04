const Laboratory = artifacts.require("Laboratory");
const GameContract = artifacts.require("Game")
const Inventory = artifacts.require("Inventory")
const DigitalGolems = artifacts.require("DigitalGolems")
const Digibytes = artifacts.require("Digibytes")
const AssetsContract = artifacts.require("Assets");
const Psychospheres = artifacts.require("Psychospheres")
const Rent = artifacts.require("Rent")
const Card = artifacts.require("Card")
const Conservation = artifacts.require("./Conservation.sol")

const { assert } = require("chai");
const {
    catchRevert,            
    catchOutOfGas,          
    catchInvalidJump,       
    catchInvalidOpcode,     
    catchStackOverflow,     
    catchStackUnderflow,   
    catchStaticStateChange
} = require("../../utils/catch_error.js")


contract('Card rent', async (accounts)=>{
    let game;
    let lab;
    let rent;
    let conservation;
    let card;
    let assets;
    let DIG;
    let psycho;
    let DBT;
    let inventory;
    let secondsInADay = 86400;
    let psychoCombining = ["0","1","2","3"];
    let user = accounts[9];
    let userRenter = accounts[8];
    let owner = accounts[0];
    let things = ["1","2","8","10","110"]
    let resources = ["2","3","1","4"]
    let augment = ["3","2","6","0","8","0","6","9","1"]
    const psychospheres = ["2", "3"]
    let fedDeposit;
    let someURLOfCombinedPicture = "someURL"
    before(async () => {
        lab = await Laboratory.new()
        game = await GameContract.new()
        inventory = await Inventory.new()
        assets = await AssetsContract.new()
        DIG = await DigitalGolems.new()
        card = await Card.new()
        conservation = await Conservation.new()
        
        DBT = await Digibytes.new()
        psycho = await Psychospheres.new()
        rent = await Rent.new()
        await card.setDIGAddress(DIG.address)
        await card.setGameAddress(game.address)
        await card.setRentAddress(rent.address)
        await DIG.setCard(card.address)
        await game.setInventory(inventory.address, {from: owner})
        await game.setAssets(assets.address, {from: owner})
        await game.setRent(rent.address)
        await game.setPsycho(psycho.address)
        await game.setCard(card.address)
        await psycho.setGameContract(game.address)
        await DIG.setLabAddress(lab.address, {from: owner})
        await inventory.setGameContract(game.address)
        await rent.setDBT(DBT.address)
        await rent.setCard(card.address)
        await rent.setConserve(conservation.address)
        await DBT.transfer(userRenter, web3.utils.toWei("17"))
        //adding assets
        await DIG.ownerMint(
                user,
                "some uri",
                "0",
                "0",
                {from: owner}
        )
    })

    it("Should create market item", async ()=>{
        fedDeposit = parseInt((await card.getMaxAbility(1)).max.toString()) * parseInt((await conservation.getFeedingPrice()).toString())
        await rent.createOrder(
            "1", // cardID
            web3.utils.toWei("1"), //priceByDay
            "7",//days
            {from: user}
        )
        await DBT.approve(rent.address, web3.utils.toWei("7") + fedDeposit, {from: userRenter})
        await rent.rentOrder(0, {from: userRenter})
        await game.sessionResult(
            things,
            resources,
            augment,
            psychospheres,
            "1",
            userRenter,
            {from: userRenter}
        )
    })

    it("Should cant be transfered because rented", async () => {
        catchRevert(
            DIG.transferFrom(user, owner, 1, {from: user})
        ) 
    })

    it("End Rent should be called by renter", async () => {
        let newTime = (Math.trunc(Date.now()/ 1000) - secondsInADay * 8).toString();
        assert.isFalse(
            await rent.isRentEnded(0)
        )
        await rent.mockTime(0, newTime)
        //revert because still rented
        catchRevert(
            rent.closeOrder(0, {from: owner})
        )
        await rent.endRentAndWithdrawFeedDepositRenter(0, {from: userRenter})
        assert.isAtLeast(
            parseInt((await DBT.balanceOf(userRenter)).toString()),
            fedDeposit
            -
            parseInt((await conservation.getFeedingPrice()).toString()),
            "Renter take fed deposit back"
        )
        assert.equal(
            parseInt((await DBT.balanceOf(user, {from: user})).toString()),
            web3.utils.toWei("7") * 997 / 1000
            + //+ means that after session renter didnt fed golem, so we took from his fed deposit 
            parseInt((await conservation.getFeedingPrice()).toString()),
            "Really 99,7%"
        )
        let renterItems = await rent.fetchRenterCardOnMarket(userRenter)
        //already not renter
        assert.equal(
            renterItems.length,
            0
        )
        assert.equal(
            (await DBT.balanceOf(rent.address)).toString(),
            web3.utils.toWei("7") * 3 / 1000,
            "Really 0,3%"
        )
        //revert because already ended by renter
        catchRevert(
            rent.endRentAndWithdrawOwner(0, {from: user})
        ) 
    })

    it("Should close order", async () => {
        await rent.closeOrder(0, {from: user})
        let marketCards = await rent.fetchCardOnMarket()
        //length equal 0 because we close our order
        assert.equal(
            marketCards.length,
            0,
            "We closed item"
        )
    })

}
)