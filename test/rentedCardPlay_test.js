const Laboratory = artifacts.require("Laboratory");
const GameContract = artifacts.require("Game")
const Inventory = artifacts.require("Inventory")
const DigitalGolems = artifacts.require("DigitalGolems")
const Digibytes = artifacts.require("Digibytes")
const AssetsContract = artifacts.require("Assets");
const Psychospheres = artifacts.require("Psychospheres")
const Rent = artifacts.require("Rent")
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
    let someURLOfCombinedPicture = "someURL"
    before(async () => {
        lab = await Laboratory.new()
        game = await GameContract.new()
        inventory = await Inventory.new()
        assets = await AssetsContract.new()
        DIG = await DigitalGolems.new()
        DBT = await Digibytes.new()
        psycho = await Psychospheres.new()
        rent = await Rent.new()
        await game.setDBT(DBT.address, {from: owner})
        await game.setDIG(DIG.address, {from: owner})
        await game.setInventory(inventory.address, {from: owner})
        await game.setAssets(assets.address, {from: owner})
        await game.setRent(rent.address)
        await game.setPsycho(psycho.address)
        await psycho.setGameContract(game.address)
        await psycho.setAssetsContract(assets.address)
        await psycho.setLabContract(lab.address)
        await DIG.setGameAddress(game.address, {from: owner})
        await DIG.setLabAddress(lab.address, {from: owner})
        await lab.setAssets(assets.address, {from: owner})
        await lab.setDBT(DBT.address, {from: owner})
        await lab.setDIG(DIG.address, {from: owner})
        await lab.setPsycho(psycho.address)
        await lab.setRent(rent.address)
        await inventory.setGameContract(game.address)
        await assets.setLab(lab.address)
        await psycho.addPsychosphereByOwner(user, 16, 0, {from: owner})
        await rent.setDIG(DIG.address)
        await rent.setDBT(DBT.address)
        await DBT.transfer(userRenter, web3.utils.toWei("7"))
        //adding assets
        await DIG.ownerMint(
                user,
                "some uri",
                "0",
                "0",
                {from: owner}
        )
        await DIG.ownerMint(
            user,
            "some uri",
            "0",
            "0",
            {from: owner}
    )
    })

    it("Should create market item", async ()=>{
        await rent.createMarketRent(
            "1", // cardID
            web3.utils.toWei("1"), //priceByDay
            "7",//days
            {from: user}
        )
        await rent.createMarketRent(
            "2", // cardID
            web3.utils.toWei("1"), //priceByDay
            "7",//days
            {from: user}
        )
        await DBT.approve(rent.address, web3.utils.toWei("7"), {from: userRenter})
        await rent.buyMarketRent(0, {from: userRenter})
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

}
)