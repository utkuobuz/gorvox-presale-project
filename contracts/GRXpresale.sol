// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";



contract GRXPresale is Ownable {
    // Sabitler
    uint256 public constant GRX_PRICE_USD = 1e6; // 0.01 USD (6 ondalık sayı ile)
    uint256 public constant COMMISSION_RATE = 5; // %5 komisyon
    uint256 public constant REFUND_PENALTY_RATE = 5; // %5 iade cezası
    uint256 public constant REFUND_LOCK_PERIOD = 30 days; // Refund süresi başlangıcı

    // Token ve Kontrat Adresleri
    IERC20 public immutable grxToken;           // GRX Token Kontrat Adresi
    address public immutable dailyWallet;        // %5 komisyonun gideceği cüzdan
    address public immutable treasuryWallet;     // Geri iade cezasının gideceği cüzdan (USDT'ye çevrilen ceza için)
    AggregatorV3Interface public immutable priceFeed; // Chainlink BNB/USD Oracle

    // Presale Durumları ve Limitler
    uint256 public startTime;
    uint256 public endTime;
    uint256 public softCap; // USD cinsinden
    uint256 public hardCap; // USD cinsinden
    uint256 public totalRaised; // USD cinsinden
    bool public presaleCanceled = false;

    // Refund Mekanizması: Yatırımcının NET USD yatırımını tutar (Komisyon düşülmüş hali)
    mapping(address => uint256) public investments; 

    // Constructor: Tüm kritik adresleri ve limitleri alır
    constructor(
        address _grxToken,
        address _dailyWallet,
        address _treasuryWallet,
        address _priceFeed, 
        address _multiSigAddress,
        uint256 _startTime,
        uint256 _endTime,
        uint256 _softCap,
        uint256 _hardCap
    ) Ownable(_multiSigAddress) {
        grxToken = IERC20(_grxToken);
        dailyWallet = _dailyWallet;
        treasuryWallet = _treasuryWallet;
        priceFeed = AggregatorV3Interface(_priceFeed);
        startTime = _startTime;
        endTime = _endTime;
        softCap = _softCap;
        hardCap = _hardCap;
        require(hardCap > softCap, "Hard cap must be greater than soft cap.");
    }
    
    //----------------------------------------------------------------------------------
    // YARDIMCI FONKSİYONLAR
    //----------------------------------------------------------------------------------

    // Chainlink Oracle kullanarak güncel BNB/USD fiyatını çeker
    function getBNBPriceUSD() public view returns (uint256) {
        (, int256 price, , , ) = priceFeed.latestRoundData();
        require(price > 0, "Price feed unavailable or stale.");
        // Fiyatı 18 ondalık sayıya dönüştürerek döndür (Chainlink genellikle 8 ondalık kullanır)
        return uint256(price) * 10**10; 
    }

    //----------------------------------------------------------------------------------
    // SATIN ALMA İŞLEMİ (BUY)
    //----------------------------------------------------------------------------------
    
    // Yatırımcının BNB göndererek GRX satın alma fonksiyonu
    receive() external payable {
        buyTokens(msg.sender);
    }

    function buyTokens(address _investor) public payable {
        require(block.timestamp >= startTime && block.timestamp <= endTime, "Presale is not active.");
        require(msg.value > 0, "Send BNB to buy tokens.");
        require(totalRaised < hardCap, "Hard cap reached.");

        // 1. BNB'nin USD Değeri Hesaplaması
        uint256 bnbPrice = getBNBPriceUSD(); 
        uint256 bnbAmount = msg.value;      
        // Toplam BNB'nin USD cinsinden değeri (18 ondalık)
        uint256 totalUSDValue = (bnbAmount * bnbPrice) / 10**18; 

        // 2. Komisyon ve Net Yatırım Hesaplaması
        // BNB Komisyon Miktarı (Daily Wallet'a gidecek)
        uint256 commissionBNB = (bnbAmount * COMMISSION_RATE) / 100;
        // USD Komisyon Miktarı
        uint256 commissionUSD = (totalUSDValue * COMMISSION_RATE) / 100;
        // Yatırımcının NET USD yatırım miktarı
        uint256 netInvestmentUSD = totalUSDValue - commissionUSD;

        // 3. Alınacak GRX Miktarı
        uint256 grxAmount = (netInvestmentUSD * (10**18 / GRX_PRICE_USD)); 
        
        // Hard Cap Kontrolü
        require(totalRaised + totalUSDValue <= hardCap, "Exceeds hard cap.");

        // 4. İşlemleri Gerçekleştirme
        
        // a) Komisyonu Daily Wallet'a Gönder (BNB olarak)
        (bool success, ) = payable(dailyWallet).call{value: commissionBNB}("");
        require(success, "BNB commission transfer failed.");

        // b) Toplanan fonu Kaydet
        totalRaised += totalUSDValue;
        investments[_investor] += netInvestmentUSD; // Sadece net yatırım kaydedilir

        // c) GRX Tokenlerini Vesting Kontratına Gönder (Bu kısım entegrasyon için sonra tamamlanacak)
        // grxToken.transfer(VESTING_CONTRACT_ADDRESS, grxAmount); 
        
        // Kalan BNB fonu (bnbAmount - commissionBNB) bu kontratta kalır (Likidite/Refund için).
    }
    
    //----------------------------------------------------------------------------------
    // REFUND (GERİ İADE) MANTIĞI
    //----------------------------------------------------------------------------------

    // Presale Soft Cap'e ulaşamazsa (Başarısızlık) herkes fonunu geri alır.
    function emergencyRefund() public {
        require(block.timestamp > endTime, "Presale is still active.");
        require(totalRaised < softCap, "Soft cap reached. Cannot use emergency refund.");
        require(!presaleCanceled, "Refund already processed or canceled.");
        
        presaleCanceled = true;
        // Burada her yatırımcının yatırdığı BNB miktarı iade edilmelidir. 
        // (Bu taslakta BNB miktarları değil, USD değeri tutulmaktadır. Tam entegrasyon için BNB miktarı tutulmalıdır.)
    }

    // Presale başarılı olduğunda (Soft Cap'e ulaşılsa bile) 30 gün sonra %5 ceza ile iade
    function claimRefundWithPenalty() public {
        // Kontrol 1: 30 günlük kilit süresi bitmiş olmalı
        require(block.timestamp >= endTime + REFUND_LOCK_PERIOD, "Refund is not available yet.");
        // Kontrol 2: Soft Cap'e ulaşılmış olmalı
        require(totalRaised >= softCap, "Presale failed. Use emergencyRefund.");
        
        uint256 investmentUSD = investments[msg.sender];
        require(investmentUSD > 0, "No investment found.");

        // %5 Ceza Hesaplaması (USD Cinsinden)
        uint256 penaltyUSD = (investmentUSD * REFUND_PENALTY_RATE) / 100;
        uint256 netRefundUSD = investmentUSD - penaltyUSD;
        
        // İade (Refund) işlemi BNB olarak yapılmalıdır (o anki BNB/USD fiyatını çekerek).
        // Ceza BNB'si Hazinede kalmalı, kalan iade BNB'si yatırımcıya gönderilmelidir.
        // Bu, hassas BNB hesaplamaları gerektirir ve burada sadeleştirilmiştir.
        
        investments[msg.sender] = 0; // İade edildi olarak işaretle
    }

    // Sahibin (Multi-Sig) kontratta kalan fonları (Likidite için) çekmesi
    function withdrawRemainingFunds() public onlyOwner {
        require(block.timestamp > endTime, "Presale must be finished.");
        require(totalRaised >= softCap, "Cannot withdraw, presale failed.");
        
        // Multi-Sig cüzdanına (Owner) kontratta kalan tüm BNB'yi gönder.
        (bool success, ) = payable(owner()).call{value: address(this).balance}("");
        require(success, "Withdrawal failed.");
    }
}