// test/presale-flow.js (Hardhat v2.19.0 ve CommonJS Uyumlu)

// 1. GEREKLİ MODÜLLER (HEPSİ CommonJS 'require' ile alınıyor)
const hre = require("hardhat");
const { expect } = require("chai");
const helpers = require("@nomicfoundation/hardhat-network-helpers");

// --- SABİT DEĞERLER ---
const GRX_DECIMALS = 18;
// Hardhat'in Ethers v6'yı kullanma olasılığına karşı BigInt (n) kullanıyoruz
const BNB_PRICE_USD = 30000000000n; 
const GRX_PRICE_USD = 10000000000000000n; // 0.01 USD (18 ondalık)

describe("GRX Presale ve Vesting Akış Testi", function () {
    let grxToken, vesting, presale, priceFeed;
    let owner, dailyWallet, investor1;
    
    let MockAggregatorV3; 

    before(async function () {
        // ethers, Hardhat v2.x'te hre'nin içinden güvenilir bir şekilde alınır.
        const { ethers } = hre;
        
        // Test hesaplarını ayarlama
        // Bu satırın artık "getSigners undefined" hatası vermemesi gerekir.
        [owner, dailyWallet, investor1] = await ethers.getSigners();
        
        // --- 1. MOCK Chainlink Oracle Kurulumu ---
        MockAggregatorV3 = await ethers.getContractFactory("MockAggregatorV3"); 
        // 8 ondalıklı ve 3000 USD (3000 * 10^8)
        priceFeed = await MockAggregatorV3.deploy(8, BNB_PRICE_USD); 
        
        // Kontrat dağıtımını test için ayarlayalım
        const currentTimestamp = await helpers.time.latest(); 
        const startTime = currentTimestamp + 3600; // 1 saat sonra başla
        const endTime = startTime + 7 * 24 * 3600; // 7 gün sürsün
        const softCap = ethers.parseUnits("100000", GRX_DECIMALS); 
        const hardCap = ethers.parseUnits("500000", GRX_DECIMALS); 

        // --- 2. Kontratları Dağıtma (Deploy) ---
        const GRXTokenFactory = await ethers.getContractFactory("GRXToken");
        grxToken = await GRXTokenFactory.deploy(ethers.parseUnits("1000000000", GRX_DECIMALS)); 

        const VestingFactory = await ethers.getContractFactory("GRXVesting");
        vesting = await VestingFactory.deploy(grxToken.target, owner.address); 

        const PresaleFactory = await ethers.getContractFactory("GRXPresale");
        presale = await PresaleFactory.deploy(
            grxToken.target,
            vesting.target, 
            dailyWallet.address, 
            owner.address, 
            priceFeed.target, 
            owner.address, 
            startTime,
            endTime,
            softCap,
            hardCap,
            GRX_PRICE_USD
        );

        // --- 3. Kurulum Sonrası Kritik Yetkilendirmeler ---
        // Presale için 100 milyon GRX tahsis et
        const PRESALE_ALLOCATION = ethers.parseUnits("100000000", GRX_DECIMALS); 
        // Tüm tahsisatı Vesting kontratına mint et
        await grxToken.mint(vesting.target, PRESALE_ALLOCATION); 

        console.log(`\n--- KURULUM BAŞARILI ---`);
        console.log(`Presale Başlangıcı: ${new Date(Number(startTime) * 1000)}`);
    });

    it("1 BNB yatırımda doğru komisyonu kesmeli ve Vesting'e doğru tahsisat yapmalıdır", async function () {
        const { ethers } = hre; // Test fonksiyonu içinde de erişilebilir olmasını sağla
        
        // Presale başlangıcına zamanı ilerlet
        const startTime = await presale.startTime();
        await helpers.time.increaseTo(startTime + 1); 

        // --- 1. Parametre Hesaplamaları ---
        const investmentBNB = ethers.parseEther("1"); 
        
        // Hesaplanan Değerler:
        // Komisyon %5
        const expectedCommissionBNB = investmentBNB * 5n / 100n; 
        const netInvestmentBNB = investmentBNB - expectedCommissionBNB;
        
        // 1 BNB yatırımda beklenen GRX: (1 BNB * 3000 USD) / 0.01 USD GRX = 300.000 GRX
        // Komisyon kesildikten sonra net yatırım: 0.95 BNB
        // (0.95 BNB * 3000 USD) / 0.01 USD GRX = 285.000 GRX
        const expectedGRXAmount = ethers.parseUnits("285000", GRX_DECIMALS); 

        // --- 2. İlk Durum Kontrolü ---
        const initialDailyWalletBalance = await ethers.provider.getBalance(dailyWallet.address);

        // --- 3. İşlem (Investor 1, Presale kontratına 1 BNB gönderir) ---
        await expect(presale.connect(investor1).buyTokens({ value: investmentBNB }))
            .to.not.be.reverted;
        
        // --- 4. Kontroller ---

        // a) Komisyon Kontrolü (DailyWallet bakiyesinin artışı)
        const finalDailyWalletBalance = await ethers.provider.getBalance(dailyWallet.address);
        expect(finalDailyWalletBalance).to.be.closeTo(
            initialDailyWalletBalance + expectedCommissionBNB, 
            ethers.parseEther("0.0001"), // Küçük bir sapmaya izin ver
            "Komisyon doğru kesilmedi"
        );
        
        // b) Kontrat Bakiyesi Kontrolü (Net yatırımın kontratta kalması)
        const presaleBalance = await ethers.provider.getBalance(presale.target);
        expect(presaleBalance).to.be.closeTo(
            netInvestmentBNB, 
            ethers.parseEther("0.0001"), 
            "Kontrat bakiyesi yanlış"
        );
        
        // c) Vesting Tahsisat Kontrolü
        const vestingDetails = await vesting.getVestingDetails(investor1.address);
        expect(vestingDetails.totalAmount).to.equal(expectedGRXAmount, "Vesting tahsisatı yanlış");
        
        console.log("TEST BAŞARILI: Komisyon ve Vesting tahsisatı doğrulandı.");
    });
});