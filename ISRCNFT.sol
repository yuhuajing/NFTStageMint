//SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

interface ISRCNFT {
    error CosignerNotSet();
    error InvalidCosignSignature();
    error InvalidStage();
    error InvalidStartAndEndTimestamp();
    error NoStageSupplyLeft();
    error HasStopped();
    error WMStopped();
    error NotEnoughValue();
    error NotMintable();
    error Mintable();
    error TimestampExpired();
    error WithdrawFailed();
    struct MintStageInfo {
        uint80 whiteSalePrice;
        uint80 publicSalePrice;
        uint24 whiteSaleHour;
        uint24 publicSaleHour;
        uint24 maxStageSupply;
        uint64 startTimeUnixSeconds;
        uint256 endWhiteTimeUnixSeconds;
        uint256 endTimeUnixSeconds;
    }

    struct InputMintStageInfo {
        uint80 whiteSalePrice;
        uint80 publicSalePrice;
        uint24 whiteSaleHour;
        uint24 publicSaleHour;
        uint24 maxStageSupply;
        uint64 startTimeUnixSeconds;
    }
    event Withdraw(uint256 value);
}
