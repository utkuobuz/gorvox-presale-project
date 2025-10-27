// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

// Hardhat/NPM'e uygun OpenZeppelin ve Chainlink import'ları
import "@openzeppelin/contracts/token/ERC20/IERC20.sol"; // <--- IERC20 hatası çözüldü
import "@openzeppelin/contracts/access/Ownable.sol";
// Chainlink import'u (Kontratınızda kullanılıyorsa doğru yolda olmalı)
// Eğer Chainlink kullanmıyorsanız bu satırı silebilirsiniz, ancak Presale kontratınızda var.
//import "@chainlink/contracts/v0.8/interfaces/AggregatorV3Interface.sol"; 


contract GRXStaking is Ownable {
    
    IERC20 public immutable grxToken;
    
    // Staking Havuzu: Bu kontratın elinde tuttuğu toplam ödül tokeni
    uint256 public totalRewardPool; 
    
    // Staking Limitleri ve Ödül Oranları (10000 = 100%)
    uint256 public constant FLEXIBLE_APR = 500; // %5 APR
    uint256 public constant LOCKED_180D_APR = 1000; // %10 APR

    // Kilit Süreleri (Saniye cinsinden)
    uint256 public constant LOCK_180_DAYS = 180 days; 

    // Yatırımcı Bilgileri
    struct Stake {
        uint256 amount;
        uint256 stakeTime;
        uint256 lockDuration; // 0 ise esnek (flexible), > 0 ise kilitli
        uint256 rewardRate; // Staking yapıldığı andaki APR
    }
    
    mapping(address => Stake) public stakes;
    
    // Ödül Takibi
    mapping(address => uint256) public claimedRewards;

    event Staked(address indexed user, uint256 amount, uint256 lockDuration);
    event RewardsClaimed(address indexed user, uint256 amount);
    event Unstaked(address indexed user, uint256 amount);

    // Constructor
    constructor(address _grxToken, address _multiSigAddress) Ownable(_multiSigAddress) {
        grxToken = IERC20(_grxToken);
    }
    
    //----------------------------------------------------------------------------------
    // YÖNETİM FONKSİYONLARI
    //----------------------------------------------------------------------------------

    function fundRewardPool(uint256 _amount) public onlyOwner {
        totalRewardPool += _amount;
    }

    //----------------------------------------------------------------------------------
    // STAKE İŞLEMLERİ
    //----------------------------------------------------------------------------------

    // Staking yapma fonksiyonu
    function stake(uint256 _amount, uint256 _lockDuration) public {
        require(_amount > 0, "Amount must be greater than zero.");
        
        uint256 rate;
        if (_lockDuration == 0) {
            rate = FLEXIBLE_APR;
        } else if (_lockDuration == LOCK_180_DAYS) {
            rate = LOCKED_180D_APR;
        } else {
            revert("Invalid lock duration.");
        }
        
        // Kullanıcıdan tokenleri çek
        require(grxToken.transferFrom(msg.sender, address(this), _amount), "Token transfer failed.");
        
        // Mevcut staking varsa güncelle, yoksa yeni oluştur
        stakes[msg.sender] = Stake({
            amount: stakes[msg.sender].amount + _amount, // Mevcut miktar üzerine ekle
            stakeTime: block.timestamp,
            lockDuration: _lockDuration,
            rewardRate: rate
        });

        emit Staked(msg.sender, _amount, _lockDuration);
    }

    //----------------------------------------------------------------------------------
    // ÖDÜL VE UNSTAKE HESAPLAMASI
    //----------------------------------------------------------------------------------

    // Hak Edilen Ödülü Hesaplama
    function calculateRewards(address _user) public view returns (uint256) {
        // Shadowing'den kurtulmak için yeni ad (_currentStake) kullanıldı
        Stake memory _currentStake = stakes[_user]; 
        
        // HATA ÇÖZÜMÜ: _currentStake kullanıldı
        if (_currentStake.amount == 0) return 0;
        
        // Geçen süre (saniye)
        uint256 timeStaked = block.timestamp - _currentStake.stakeTime;
        
        // Basitleştirilmiş Ödül Hesaplaması: (Miktar * APR * Geçen Süre) / (Yılın Saniyesi * 10000)
        uint256 rewards = (_currentStake.amount * _currentStake.rewardRate * timeStaked) / (31557600 * 10000); 
        
        return rewards;
    }
    
    // Ödülleri çekme (Claim)
    function claimRewards() public {
        uint256 rewards = calculateRewards(msg.sender);
        require(rewards > 0, "No rewards available.");
        
        require(rewards <= totalRewardPool, "Insufficient rewards in pool.");
        
        totalRewardPool -= rewards;
        claimedRewards[msg.sender] += rewards;

        require(grxToken.transfer(msg.sender, rewards), "Reward transfer failed.");
        emit RewardsClaimed(msg.sender, rewards);
    }

    // Unstake (Çekme)
    function unstake() public {
        // Shadowing'den kurtulmak için yeni ad (_senderStake) kullanıldı
        Stake storage _senderStake = stakes[msg.sender]; 
        
        // HATA ÇÖZÜMÜ: _senderStake kullanıldı
        uint256 amount = _senderStake.amount; 
        require(amount > 0, "No active stake.");

        // Kilitli Staking Kontrolü
        // HATA ÇÖZÜMÜ: _senderStake kullanıldı
        if (_senderStake.lockDuration > 0) {
            require(block.timestamp >= _senderStake.stakeTime + _senderStake.lockDuration, "Stake is still locked.");
        }
        
        claimRewards(); 

        // Staking kaydını temizle ve tokenleri iade et
        // HATA ÇÖZÜMÜ: _senderStake kullanıldı
        _senderStake.amount = 0;
        
        require(grxToken.transfer(msg.sender, amount), "Unstake transfer failed.");
        emit Unstaked(msg.sender, amount);
    }
}