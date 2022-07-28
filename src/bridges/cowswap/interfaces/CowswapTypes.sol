// SPDX-License-Identifier: GPL-2.0-only

pragma solidity >=0.6.10 <=0.8.10;
pragma experimental ABIEncoderV2;

library CowswapTypes {

    struct CowswapOrder {
        uint256 sellAmount; //pack variables
        uint256 buyAmount;
        uint256 feeAmount;
        address sellToken;
        address buyToken;
        uint256 validTo;
    }

    enum InteractionStatus {
        PENDING,
        EXPIRED,
        SUCCEEDED
    }

    struct Interaction {
        bytes orderUid; //bytes is used in GPv2Settlement
        InteractionStatus status;
    }

}

