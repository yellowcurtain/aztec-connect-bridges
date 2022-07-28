// SPDX-License-Identifier: GPL-2.0-only

pragma solidity >=0.6.10 <=0.8.10;
pragma experimental ABIEncoderV2;
interface IGPv2Settlement {

    function setPreSignature(bytes calldata orderUid, bool signed) external;

    function filledAmount(bytes calldata orderUid) external view returns (uint256);
    
}

