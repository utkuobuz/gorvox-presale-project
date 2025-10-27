// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

// Chainlink arayüzünü taklit eder.
contract MockAggregatorV3 {
    int256 private s_answer;
    uint8 private s_decimals;

    constructor(uint8 decimals_, int256 initialAnswer_) {
        s_decimals = decimals_;
        s_answer = initialAnswer_;
    }

    // Fiyatı test sırasında istediğimiz zaman değiştirebilmek için.
    function setLatestAnswer(int256 newAnswer) public {
        s_answer = newAnswer;
    }

    // AggregatorV3Interface'in beklediği fonksiyon
    function decimals() public view returns (uint8) {
        return s_decimals;
    }

    // AggregatorV3Interface'in beklediği fonksiyon
    function latestRoundData()
        public
        view
        returns (
            uint80 roundId,
            int256 answer,
            uint256 startedAt,
            uint256 updatedAt,
            uint80 answeredInRound
        )
    {
        // Basitçe: roundId = 1, answer = s_answer, startedAt/updatedAt = now()
        return (1, s_answer, block.timestamp, block.timestamp, 1);
    }
}