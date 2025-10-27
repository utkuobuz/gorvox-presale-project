// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

// OpenZeppelin kütüphaneleri: ERC20 token standardı ve Yetkilendirme (Ownable)
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

// GRXToken kontratı
contract GRXToken is ERC20, Ownable {
    // 1. TOPLAM ARZ: 21 Milyar (18 ondalık sayısı ile çarpılır)
    uint256 private constant TOTAL_SUPPLY = 21000000000 * 10**18;
    
    // 2. İŞLEM KİLİDİ BAYRAĞI: Başlangıçta transfer kapalı (Presale devam ediyor)
    bool public tradingEnabled = false; 

    // 3. WHITELIST: Kilit aktifken transfer yapmasına izin verilen (Staking, Refund, Treasury vb.) kontratlar
    mapping(address => bool) public isWhitelisted;

    // 4. KURUCU CÜZDANI: Kontrat konuşlandığında tüm tokenlerin basılacağı adres.
    address public initialRecipientAddress; 

    // Kontratın Yapıcısı (Constructor)
    constructor(address _multiSigAddress) 
        ERC20("Gorvox Finance", "GRX") 
        Ownable(_multiSigAddress) // Multi-Sig, kontratın sahibi ve kilidi açma yetkisine sahip olur
    {
        initialRecipientAddress = _multiSigAddress;
        
        // Tüm tokenlerin %100'ü Multi-Sig adresine basılır (Mint işlemi sadece burada yapılır)
        _mint(_multiSigAddress, TOTAL_SUPPLY);
    }
    
    // Sadece Multi-Sig (Owner) tarafından çağrılabilir. TGE gerçekleştiğinde kullanılır.
    function enableTrading() public onlyOwner {
        require(!tradingEnabled, "Trading is already enabled.");
        tradingEnabled = true;
    }

    // Whitelist'e kontrat ekleme/çıkarma yetkisi (Sadece Multi-Sig)
    function setWhitelist(address _contract, bool _status) public onlyOwner {
        isWhitelisted[_contract] = _status;
    }

    // _update: OpenZeppelin v5.0'da transfer işlemlerinden önce çalışan ana hook'tur.
    function _update(address from, address to, uint256 value) internal override {
        super._update(from, to, value); // Önce üst sınıfın (ERC20) update'ini çağır

        // Kontrol: Eğer ticaret (trading) aktif değilse (Presale devam ediyorsa)
        if (!tradingEnabled) {
            // İSTİSNA 1: Whitelist'teki adresler arası transferlere izin ver
            if (isWhitelisted[from] || isWhitelisted[to]) {
                return;
            }

            // İSTİSNA 2: Multi-Sig cüzdanından yapılan ilk dağıtımlara izin ver
            if (from == initialRecipientAddress) {
                return;
            }
            
            // Kalan tüm adresler için transferi engelle (Hisse alım satımı kilitlidir)
            require(tradingEnabled, "Transfer is locked until Token Generation Event (TGE)."); 
        }
    }
}