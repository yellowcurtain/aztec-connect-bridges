// SPDX-License-Identifier: GPL-2.0-only

pragma solidity >=0.6.10 <=0.8.10;
pragma experimental ABIEncoderV2;

import {SafeMath} from "@openzeppelin/contracts/utils/math/SafeMath.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {BridgeBase} from "../base/BridgeBase.sol";
import {ErrorLib} from "../base/ErrorLib.sol";
import {IRollupProcessor} from "../../aztec/interfaces/IRollupProcessor.sol";
import {AztecTypes} from "../../aztec/libraries/AztecTypes.sol";
import {IGPv2Settlement} from "./interfaces/IGPv2Settlement.sol";
import {CowswapTypes} from "./interfaces/CowswapTypes.sol";
// import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";

/// @title Bridge Contract between Aztec and Cowswap
/// @author yellowcurtain
contract CowswapBridge is BridgeBase {

    error InsufficientBalance(uint256 available, uint256 required);
    error NoMatchingPresignOrderFound();
    error PresignOrderExpired();

    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    /// @dev Smart contract responsible for processing Aztec zkRollups
    address public immutable rollupProcessor;

    /// @dev The settlement contract of cowswap
    /// Call setPreSignature function of GPv2Settlement to activate order
    IGPv2Settlement public immutable cowswapSettlement;

    /// @dev The vault relayer of cowswap
    /// Approve on vaultRelayer to be able to place order on cowswap
    /// More detail on vault relayer:
    /// https://docs.cow.fi/smart-contracts/vault-relayer
    address public immutable vaultRelayer;

    /// @dev Array of orderUid
    /// Unique order id of cowswap
    /// More detail on orderUid:
    /// https://docs.cow.fi/front-end/gp-explorer
    bytes[] public orderUids;

    /// @dev Presigned orders
    /// Presigned orders are none active orders, key is orderUid
    /// Call setPreSignature will sign and activate order
    /// More detail on presigned order:
    /// https://docs.cow.fi/tutorials/cowswap-trades-with-a-gnosis-safe-wallet
    mapping(bytes => CowswapTypes.CowswapOrder) public presignedOrders;

    /// @dev Array of interaction nonce 
    /// Interaction nonce is a globally unique identifier for DeFi interaction
    uint256[] public pendingInteractionNonces;

    /// @dev Interactions
    /// Key is interactionNonce
    mapping(uint256 => CowswapTypes.Interaction) public interactions;

    // /// @dev Chainlink price feed 
    // /// More detail on chainlink price feed:
    // /// https://docs.chain.link/docs/ethereum-addresses/
    // AggregatorV3Interface internal priceFeed;

    /// @dev Empty receive function
    /// Allow bridge contract to receive Ether
    receive() external payable {}

    constructor(address _cowswapSettlement, address _rollupProcessor, address _vaultRelayer) BridgeBase(_rollupProcessor) {
        cowswapSettlement = IGPv2Settlement(_cowswapSettlement);
        rollupProcessor = _rollupProcessor;
        vaultRelayer = _vaultRelayer;
        // // Aggregator: ETH/USD
        // priceFeed = AggregatorV3Interface(0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419);
    }

    /// @dev Keeper should prepare presigned order before call convert
    /// @param _order Cowswap Order
    /// @param _orderUid Unique order id
    function addPresignOrder(CowswapTypes.CowswapOrder calldata _order, bytes calldata _orderUid) external {
        orderUids.push(_orderUid);
        presignedOrders[_orderUid] = _order;
    }

    /// @dev free storage
    /// 1， Delete pending interactions that has expired or succeded
    /// 2， Delete presigned order that has expired
    function freeStorage() public {
        for (uint256 i = 0; i < pendingInteractionNonces.length; i++) {
            uint256 interactionNonce = pendingInteractionNonces[i];
            CowswapTypes.Interaction memory interaction = interactions[interactionNonce];
            if (interaction.status == CowswapTypes.InteractionStatus.EXPIRED ||
                interaction.status == CowswapTypes.InteractionStatus.SUCCEEDED) {
                    delete interactions[interactionNonce];
                    pendingInteractionNonces[i] = pendingInteractionNonces[pendingInteractionNonces.length - 1];
                    pendingInteractionNonces.pop();
                }
        }

        for (uint256 i = 0; i < orderUids.length; i++) {
            bytes memory currentOrderUid = orderUids[i];
            CowswapTypes.CowswapOrder memory order = presignedOrders[currentOrderUid];
            if (order.validTo < block.timestamp) {
                delete presignedOrders[currentOrderUid];
                orderUids[i] = orderUids[orderUids.length - 1];
                orderUids.pop();
            }
        }
    }

    function convert(
        AztecTypes.AztecAsset calldata _inputAssetA,
        AztecTypes.AztecAsset calldata,
        AztecTypes.AztecAsset calldata _outputAssetA,
        AztecTypes.AztecAsset calldata,
        uint256 _inputValue,
        uint256 _interactionNonce,
        uint64,
        address
    )
    external
    payable
    override(BridgeBase)
    onlyRollup
    returns (
        uint256 _outputValueA,
        uint256 _outputValueB,
        bool _isAsync
    ) {
        _balanceCheck(_inputAssetA.erc20Address, _inputValue);

        _allowanceSet(_inputAssetA.erc20Address, _inputValue);

        bytes memory orderUid = _findPresignOrder(_inputAssetA.erc20Address, _outputAssetA.erc20Address, _inputValue);
        _placeOrder(orderUid);

        interactions[_interactionNonce] = CowswapTypes.Interaction(orderUid, CowswapTypes.InteractionStatus.PENDING);
        pendingInteractionNonces.push(_interactionNonce);
        
        // try to finalise all pending interactions
        for (uint256 i = 0; i < pendingInteractionNonces.length; i++) {
            _finaliseInteraction(pendingInteractionNonces[i]);
        }

        return (0,0,true);
    }

    function finalise(
        AztecTypes.AztecAsset calldata,
        AztecTypes.AztecAsset calldata,
        AztecTypes.AztecAsset calldata,
        AztecTypes.AztecAsset calldata,
        uint256 _interactionNonce,
        uint64
    )
    external
    payable
    override(BridgeBase)
    onlyRollup
    returns (
        uint256 _outputValueA,
        uint256,
        bool _interactionComplete
    ) {
        _nounceCheck(_interactionNonce);
       
        _finaliseInteraction(_interactionNonce);

        bytes memory orderUid = interactions[_interactionNonce].orderUid;
        CowswapTypes.CowswapOrder memory order = presignedOrders[orderUid];

        return (order.buyAmount, 0, true);
    }

    /// @dev Check balance of input asset is enough for swapping
    /// DefiBridgeProxy should transfer input asset to cowswap bridge
    /// @param _inputAsset address of input asset
    /// @param _inputValue value of input asset
    function _balanceCheck(address _inputAsset, uint256 _inputValue) private view {
        uint256 balance = IERC20(_inputAsset).balanceOf(address(this));
        if (balance < _inputValue) {
            revert InsufficientBalance(balance, _inputValue);
        }
    }

    /// @dev Set allowance of input asset on vault relayer of cowswap
    /// GPv2VaultRelayer address on Mainnet:0xc92e8bdf79f0507f65a392b0ab4667716bfe0110
    /// @param _inputAsset address of input asset
    /// @param _inputValue value of input asset
    function _allowanceSet(address _inputAsset, uint256 _inputValue) private {  
        uint256 amount = IERC20(_inputAsset).allowance(address(this), vaultRelayer);
        if (amount <  _inputValue) {
            IERC20(_inputAsset).safeIncreaseAllowance(vaultRelayer, _inputValue);
        }
    }

    /// @dev Check existance of interactionNonce
    /// @param _interactionNonce interactionNonce
    function _nounceCheck(uint256 _interactionNonce) private view {
        CowswapTypes.Interaction memory interaction = interactions[_interactionNonce];
        if (interaction.orderUid.length == 0) {
            revert ErrorLib.InvalidNonce();
        }
    }

    /// @dev Find a matching presign order from presigned orders 
    /// @param _sellToken address of sell token
    /// @param _buyToken address of buy token
    /// @param _sellAmount value of sell token
    function _findPresignOrder(address _sellToken, address _buyToken, uint256 _sellAmount) 
    private view returns (bytes memory) {
        for (uint256 i = 0; i < orderUids.length; i++) {
            bytes memory orderUid = orderUids[i];
            CowswapTypes.CowswapOrder memory order = presignedOrders[orderUid];
            if (_sellToken == order.sellToken && _buyToken == order.buyToken 
                && _sellAmount == order.sellAmount && order.validTo >= block.timestamp) {
                    return orderUid;
            } 
        }
        revert NoMatchingPresignOrderFound();
    }

    /// @dev Place order on cowswap
    /// Call setPreSignature to activate presigned order. 
    /// @param _orderUid presigned CowswapOrder
    function _placeOrder(bytes memory _orderUid) private  {
        cowswapSettlement.setPreSignature(_orderUid, true);
    }

    /// @dev Check if sellAmount of order filled
    /// If order is completely filled, filledAmount[orderUid] will be same as total sell amount
    /// Refer to: https://github.com/gnosis/gp-v2-contracts/blob/main/src/contracts/GPv2Settlement.sol#L217
    /// @param _orderUid The unique identifiers of the order
    /// @param _amount The unique identifiers of the order
    function _isOrderFilled(bytes memory _orderUid, uint256 _amount) private view returns (bool _isFilled) {
        uint256 filledAmount = cowswapSettlement.filledAmount(_orderUid);
        if(_amount == filledAmount) {
            _isFilled = true;
        } else {
            _isFilled = false;
        }
        return _isFilled;
    }

    /// @dev Finalise specific interaction
    /// @param _interactionNonce InteractionNonce
    function _finaliseInteraction(uint256 _interactionNonce) private {
        CowswapTypes.Interaction storage interaction = interactions[pendingInteractionNonces[_interactionNonce]];
        if (interaction.status == CowswapTypes.InteractionStatus.PENDING) {
            bytes memory orderUid = interaction.orderUid;
            CowswapTypes.CowswapOrder memory order = presignedOrders[orderUid];
            if (order.validTo < block.timestamp) {
                // MARK as expired
                interaction.status = CowswapTypes.InteractionStatus.EXPIRED;
                revert PresignOrderExpired();
            } else {
                bool isFilled = _isOrderFilled(interaction.orderUid, order.sellAmount);
                if (isFilled == true) {
                    // Approve the transfer of funds back to the rollup contract            
                    uint256 amount = IERC20(order.buyToken).allowance(address(this), ROLLUP_PROCESSOR);
                    if (amount < order.buyAmount) {
                        IERC20(order.buyToken).safeIncreaseAllowance(ROLLUP_PROCESSOR, order.buyAmount);
                    }
                    // Transfer funds back to rollup contract
                    IERC20(order.buyToken).transfer(ROLLUP_PROCESSOR, order.buyAmount);
                    // MARK as succeded
                    interaction.status = CowswapTypes.InteractionStatus.SUCCEEDED;
                }
            }
        }
    }
}

