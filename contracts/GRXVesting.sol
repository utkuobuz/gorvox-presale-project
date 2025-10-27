// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract GRXVesting is Ownable {
    // 1. TOKEN ADRESİ: Vesting yapılacak GRX Token kontrat adresi
    IERC20 public immutable grxToken;

    // 2. VESTING PERİYODU: 6 Ay (yaklaşık 180 gün) saniye cinsinden
    uint256 private constant VESTING_PERIOD = 180 days; 
    
    // 3. YATIRIMCI BİLGİLERİ
    struct Investor {
        uint256 totalAmount;          // Presale'de satın alınan toplam token miktarı
        uint256 tgeTime;              // TGE (Vesting Başlangıç) zaman damgası
        uint256 claimedAmount;        // Daha önce çekilen (claim edilen) miktar
    }

    mapping(address => Investor) public investors;

    event TokensVested(address indexed investor, uint256 amount, uint256 tgeTime);
    event TokensClaimed(address indexed investor, uint256 amount);

    // Constructor: GRX Token adresini alır ve Multi-Sig cüzdanı Owner olarak ayarlar
    constructor(address _grxTokenAddress, address _multiSigAddress) Ownable(_multiSigAddress) {
        grxToken = IERC20(_grxTokenAddress);
    }

    // Sadece Owner (Multi-Sig veya Presale Kontratı) tarafından çağrılabilir.
    // Bu fonksiyon, Presale bittiğinde her yatırımcı için cüzdanına tahsis edilen token miktarını ve TGE başlangıcını tanımlar.
    function vestTokens(address _investor, uint256 _amount, uint256 _tgeTime) public onlyOwner {
        require(investors[_investor].totalAmount == 0, "Investor already vested.");
        require(_amount > 0, "Amount must be greater than zero.");
        require(_tgeTime > 0, "TGE time must be set.");

        // Bilgileri kaydet
        investors[_investor] = Investor({
            totalAmount: _amount,
            tgeTime: _tgeTime,
            claimedAmount: 0
        });

        emit TokensVested(_investor, _amount, _tgeTime);
    }
    
    //----------------------------------------------------------------------------------
    // HESAPLAMA MANTIĞI: Toplam hak edilen token miktarını hesaplar
    //----------------------------------------------------------------------------------

    function getVestedAmount(address _investor) public view returns (uint256) {
        Investor memory investor = investors[_investor];
        
        // Eğer yatırımcıya tahsisat yapılmamışsa 0 dön
        if (investor.totalAmount == 0) {
            return 0;
        }

        uint256 totalAmount = investor.totalAmount;
        uint256 tgeTime = investor.tgeTime;
        
        // TGE anında serbest kalan kısım (%20)
        uint256 immediateRelease = (totalAmount * 20) / 100;
        
        // Lineer vesting'e tabi tutulan kısım (%80)
        uint256 linearVestingAmount = totalAmount - immediateRelease;

        // TGE henüz gerçekleşmediyse, sadece anında serbest kalan miktar hak edilmiştir
        if (block.timestamp < tgeTime) {
            return immediateRelease;
        }

        // TGE'den bu yana geçen süre
        uint256 timeElapsed = block.timestamp - tgeTime;
        
        // Lineer vesting periyodu tamamlandıysa (6 aydan fazla geçtiyse)
        if (timeElapsed >= VESTING_PERIOD) {
            return totalAmount; // %100'ü hak edilmiştir
        }

        // Lineer hak ediş hesaplaması: (Geçen Zaman / Toplam Vesting Süresi) * Lineer Miktar
        uint256 vestedLinear = (linearVestingAmount * timeElapsed) / VESTING_PERIOD;

        return immediateRelease + vestedLinear;
    }

    //----------------------------------------------------------------------------------
    // CLAIM MANTIĞI: Yatırımcının hak ettiği tokenleri çekmesi
    //----------------------------------------------------------------------------------

    function claim() public {
        Investor storage investor = investors[msg.sender];
        require(investor.totalAmount > 0, "No tokens allocated to this address.");

        // Şu ana kadar hak edilen toplam miktar
        uint256 vested = getVestedAmount(msg.sender);
        
        // Çekilebilir miktar = Hak edilen - Zaten çekilmiş olan
        uint256 claimable = vested - investor.claimedAmount;

        require(claimable > 0, "No claimable tokens available yet.");

        // Token transferini gerçekleştir
        investor.claimedAmount += claimable;
        grxToken.transfer(msg.sender, claimable);

        emit TokensClaimed(msg.sender, claimable);
    }
}