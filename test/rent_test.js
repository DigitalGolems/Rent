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
    let conservation;
    let card;
    let rent;
    let assets;
    let DIG;
    let psycho;
    let DBT;
    let inventory;
    let fedDeposit;
    let secondsInADay = 86400;
    let psychoCombining = ["0","1","2","3"];
    let user = accounts[9];
    let userRenter = accounts[8];
    let owner = accounts[0];
    let things = ["1","2","8","10","110"]
    let resources = ["2","3","1","4"]
    let augment = ["3","2","6","0","8","0","6","9","1"]
    let someURLOfCombinedPicture = "someURL"
    before(async () => {
        lab = await Laboratory.new()
        game = await GameContract.new()
        inventory = await Inventory.new()
        card = await Card.new()
        assets = await AssetsContract.new()
        DIG = await DigitalGolems.new()
        DBT = await Digibytes.new()
        psycho = await Psychospheres.new()
        rent = await Rent.new()
        conservation = await Conservation.new()
        await card.setDIGAddress(DIG.address)
        await card.setGameAddress(game.address)
        await DIG.setCard(card.address)
        await game.setDBT(DBT.address, {from: owner})
        await game.setDIG(DIG.address, {from: owner})
        await game.setInventory(inventory.address, {from: owner})
        await game.setAssets(assets.address, {from: owner})
        await psycho.setGameContract(game.address)
        await psycho.setAssetsContract(assets.address)
        await psycho.setLabContract(lab.address)
        await DIG.setLabAddress(lab.address, {from: owner})
        await lab.setAssets(assets.address, {from: owner})
        await lab.setDBT(DBT.address, {from: owner})
        await lab.setDIG(DIG.address, {from: owner})
        await lab.setPsycho(psycho.address)
        await assets.setLab(lab.address)
        await psycho.addPsychosphereByOwner(user, 16, 0, {from: owner})
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
        await rent.createOrder(
            "1", // cardID
            web3.utils.toWei("1"), //priceByDay
            "7",//days
            {from: user}
        )
        //fetching all card on market
        //length should be 1, because before we added one
        assert.equal(
            (await rent.fetchCardOnMarket()).length,
            1,
            "All card on market"
        )
        //get all user market card
        let allUserMarketCard = await rent.fetchUserCardOnMarket(user)
        assert.equal(
            allUserMarketCard.length,
            1,
            "All user card on market"
        )
        //check if this card really user
        for (let i = 0; i < allUserMarketCard.length; i++){
            assert.equal(
                (await card.cardOwner((allUserMarketCard[0][1]).toString())).toString(),
                user,
                "Really user"
            )
        }
    })

    it("Should rent market item", async () => {
        fedDeposit = parseInt((await card.getMaxAbility(1)).max.toString()) * parseInt((await conservation.getFeedingPrice()).toString())
        await DBT.approve(rent.address, web3.utils.toWei("7") + fedDeposit, {from: userRenter})
        await rent.rentOrder(0, {from: userRenter})
        //checks renter items
        let renterItems = await rent.fetchRenterCardOnMarket(userRenter)
        for (let i = 0; i < renterItems.length; i++){
            assert.equal(
                (renterItems[0][2]).toString(),
                userRenter,
                "Really userRenter"
            )
        }
        //because rent not ended
        catchRevert(
            rent.endRentAndWithdrawOwner(0, {from: user})
        )
        //user seller has 99,7% because we take 0,3% comission
        assert.equal(
            (await rent.getUserDeposit(0, {from: user})).toString(),
            web3.utils.toWei("7") * 997 / 1000,
            "Really 99,7%"
        ) 
        assert.equal(
            (await rent.getThisDBTBalance()).toString(),
            web3.utils.toWei("7") * 3 / 1000,
            "Really 0,3%"
        )
    })

    it("Card Owner Should end rent item", async ()=>{
        let newTime = (Math.trunc(Date.now()/ 1000) - secondsInADay * 8).toString();
        assert.isFalse(
            await rent.isRentEnded(0)
        )
        await rent.mockTime(0, newTime)
        assert.isTrue(
            await rent.isRentEnded(0)
        )
        await rent.endRentAndWithdrawOwner(0, {from: user})
        assert.isAtLeast(
            parseInt((await DBT.balanceOf(userRenter)).toString()),
            fedDeposit,
            "Renter take fed deposit back"
        )
        assert.equal(
            (await DBT.balanceOf(user, {from: user})).toString(),
            web3.utils.toWei("7") * 997 / 1000,
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
    })

}
)