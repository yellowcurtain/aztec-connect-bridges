// SPDX-License-Identifier: GPL-2.0-only

pragma solidity >=0.8.4;

import {BridgeTestBase} from "./../../aztec/base/BridgeTestBase.sol";
import {AztecTypes} from "../../../aztec/libraries/AztecTypes.sol";
import {CowswapTypes} from "../../../bridges/cowswap/interfaces/CowswapTypes.sol";
import {IGPv2Settlement} from "../../../bridges/cowswap/interfaces/IGPv2Settlement.sol";
import {CowswapBridge} from "../../../bridges/cowswap/CowswapBridge.sol";
import {ErrorLib} from "../../../bridges/base/ErrorLib.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract CowswapTest is BridgeTestBase {

    CowswapBridge internal cowswapBridge;
    uint256 private bridgeId;
    AztecTypes.AztecAsset private empty;
    AztecTypes.AztecAsset private inputAssetA;
    AztecTypes.AztecAsset private outputAssetA;

    address private constant COWSWAPSETTLEMENT = 0x9008D19f58AAbD9eD0D60971565AA8510560ab41;
    address private constant VAULTRELAYER = 0xC92E8bdf79f0507f65a392b0ab4667716BFE0110;
    address private constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address private constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;

    function setUp() public {

        // Deploy a new cowswap bridge
        cowswapBridge = new CowswapBridge(COWSWAPSETTLEMENT, address(ROLLUP_PROCESSOR), VAULTRELAYER);

        // Bridge address is needed for keepers to place presigned order on cowswap.
        // console.log(address(cowswapBridge));

        // Impersonate the multi-sig to add a new bridge
        vm.prank(MULTI_SIG);

        // List the bridge with a gasLimit of 500000
        ROLLUP_PROCESSOR.setSupportedBridge(address(cowswapBridge), 500000); // To be decided

        // Fetch the id of the bridge
        bridgeId = ROLLUP_PROCESSOR.getSupportedBridgesLength();

        inputAssetA = AztecTypes.AztecAsset({
            id: 1,
            erc20Address: WETH,
            assetType: AztecTypes.AztecAssetType.ERC20
        });
        
        outputAssetA = AztecTypes.AztecAsset({
            id: 2,
            erc20Address: USDC,
            assetType: AztecTypes.AztecAssetType.ERC20
        });
    }

    function testInvalidCaller() public {
        uint256 balance = 1e18;
        deal(WETH, address(cowswapBridge), balance); 
        uint256 inputValueA = 2e18;
        vm.expectRevert(ErrorLib.InvalidCaller.selector);
        cowswapBridge.convert(inputAssetA, empty, outputAssetA, empty, inputValueA, 0, 0, address(0x0));
    }

    function testBalanceCheckFail() public {
        uint256 balance = 1e18;
        deal(WETH, address(cowswapBridge), balance); 
        uint256 inputValueA = 2e18;
        vm.expectRevert(abi.encodeWithSignature("InsufficientBalance(uint256,uint256)", balance, inputValueA));
        vm.prank(address(ROLLUP_PROCESSOR));
        cowswapBridge.convert(inputAssetA, empty, outputAssetA, empty, inputValueA, 0, 0, address(0x0));
    }

    function testAllowanceSet() public {
        _setupPresignOrder();
        uint256 balance = 2e18;
        deal(WETH, address(cowswapBridge), balance); 
        uint256 inputValueA = 1e18;
        vm.prank(address(ROLLUP_PROCESSOR));
        cowswapBridge.convert(inputAssetA, empty, outputAssetA, empty, inputValueA, 0, 0, address(0x0));
        uint256 amount = IERC20(inputAssetA.erc20Address).allowance(address(cowswapBridge), VAULTRELAYER);
        assertEq(amount, inputValueA);
    }
    
    function testFindPresignOrderFail() public {
        uint256 balance = 2e18;
        deal(WETH, address(cowswapBridge), balance); 
        uint256 inputValueA = 1e18;
        vm.expectRevert(CowswapBridge.NoMatchingPresignOrderFound.selector);
        vm.prank(address(ROLLUP_PROCESSOR));
        cowswapBridge.convert(inputAssetA, empty, outputAssetA, empty, inputValueA, 0, 0, address(0x0));
    }

    function testPresignOrderFail() public {
        _setupPresignOrderWithWrongBridgeAddress();
        uint256 balance = 2e18;
        deal(WETH, address(cowswapBridge), balance); 
        uint256 inputValueA = 1e18;
        vm.expectRevert(bytes("GPv2: cannot presign order"));
        vm.prank(address(ROLLUP_PROCESSOR));
        cowswapBridge.convert(inputAssetA, empty, outputAssetA, empty, inputValueA, 0, 0, address(0x0));
    }

    function testNounceCheck() public {
        uint256 balance = 2*10**18;
        deal(WETH, address(cowswapBridge), balance);
        _setupPresignOrder();
        uint256 interactionNonce = 0;
        uint256 inputValueA = 1*10**18;
        vm.prank(address(ROLLUP_PROCESSOR));
        cowswapBridge.convert(inputAssetA, empty, outputAssetA, empty, inputValueA, interactionNonce, 0, address(0x0));

        uint256 inputInteractionNonce = 1;
        vm.expectRevert(ErrorLib.InvalidNonce.selector);
        vm.prank(address(ROLLUP_PROCESSOR));
        cowswapBridge.finalise(empty, empty, empty, empty, inputInteractionNonce, 0);
    }

    function testPresignOrderExpired() public {
        uint256 balance = 2*10**18;
        deal(WETH, address(cowswapBridge), balance);
        _setupExpiredPresignOrder();
        uint256 interactionNonce = 0;
        uint256 inputValueA = 2*10**18;
        vm.warp(0);
        vm.prank(address(ROLLUP_PROCESSOR));
        cowswapBridge.convert(inputAssetA, empty, outputAssetA, empty, inputValueA, interactionNonce, 0, address(0x0));

        vm.warp(1973437051);
        vm.expectRevert(CowswapBridge.PresignOrderExpired.selector);
        vm.prank(address(ROLLUP_PROCESSOR));
        cowswapBridge.finalise(empty, empty, empty, empty, interactionNonce, 0);
    }

    /**
        Testing flow:
        1. Prepare first presigned order
        2. Call convert to place first order on cowswap
        3. Mock first order get executed 
        4. Prepare second presigned order
        5. Call convert to try to finalise first order
     */
    function testConvert() public {
        // 1, setup balance WETH: 5
        uint256 balance = 5*10**18;
        deal(WETH, address(cowswapBridge), balance);

        // 2, setup first order: sell 1 WETH for USDC
        _setupPresignOrder();
        uint256 interactionNonce = 0;
        uint256 inputValueA = 1*10**18;
        vm.prank(address(ROLLUP_PROCESSOR));
        cowswapBridge.convert(inputAssetA, empty, outputAssetA, empty, inputValueA, interactionNonce, 0, address(0x0));

        // 3, setup first order success swap situation
        (bytes memory orderUid, ) = cowswapBridge.interactions(interactionNonce);        
        (uint256 sellAmount, uint256 buyAmount, uint256 feeAmount, , ,) = cowswapBridge.presignedOrders(orderUid);
        deal(WETH, address(cowswapBridge), balance - sellAmount - feeAmount);
        deal(USDC, address(cowswapBridge), buyAmount);
        vm.mockCall(
            COWSWAPSETTLEMENT,
            abi.encodeWithSelector(IGPv2Settlement.filledAmount.selector, orderUid),
            abi.encode(sellAmount)
        );

        // 4, setup second order: sell 2WETH for USDC
        _setupPresignOrder1();
        uint256 interactionNonce1 = 1;
        uint256 inputValueA1 = 2*10**18;
        vm.prank(address(ROLLUP_PROCESSOR));
        cowswapBridge.convert(inputAssetA, empty, outputAssetA, empty, inputValueA1, interactionNonce1, 0, address(0x0));

        // 5, rollup contract should receive correct output asset
        (, CowswapTypes.InteractionStatus status) = cowswapBridge.interactions(interactionNonce);  
        assertEq(uint(status), 2);
        uint256 amount = IERC20(outputAssetA.erc20Address).balanceOf(address(ROLLUP_PROCESSOR));
        assertEq(amount, buyAmount);
    }

    /**
        Testing flow:
        1. Prepare presigned order
        2. Call convert to place order on cowswap
        3. Mock order get executed 
        4. Call finalise to finalise order
     */
    function testFinalise() public {
        uint256 balance = 2*10**18;
        deal(WETH, address(cowswapBridge), balance);
        _setupPresignOrder();
        uint256 interactionNonce = 0;
        uint256 inputValueA = 1*10**18;
        vm.prank(address(ROLLUP_PROCESSOR));
        cowswapBridge.convert(inputAssetA, empty, outputAssetA, empty, inputValueA, interactionNonce, 0, address(0x0));

        // mock first order success swap situation
        (bytes memory orderUid, ) = cowswapBridge.interactions(interactionNonce);        
        (uint256 sellAmount, uint256 buyAmount, uint256 feeAmount, , ,) = cowswapBridge.presignedOrders(orderUid);
        deal(WETH, address(cowswapBridge), balance - sellAmount - feeAmount);
        deal(USDC, address(cowswapBridge), buyAmount);
        vm.mockCall(
            COWSWAPSETTLEMENT,
            abi.encodeWithSelector(IGPv2Settlement.filledAmount.selector, orderUid),
            abi.encode(sellAmount)
        );

        vm.prank(address(ROLLUP_PROCESSOR));
        cowswapBridge.finalise(empty, empty, empty, empty, interactionNonce, 0);

        uint256 amount = IERC20(outputAssetA.erc20Address).balanceOf(address(ROLLUP_PROCESSOR));
        assertEq(amount, buyAmount);
        (, CowswapTypes.InteractionStatus status) = cowswapBridge.interactions(interactionNonce);  
        assertEq(uint(status), 2);
    }

    function _setupPresignOrder() public {
        // 0x367e6e644cbecb6f3fd82a4b92ae11f9370d3582b5a41c8ab131796a2f028f99ce71065d4017f316ec606fe4422e11eb2c47c24675a53939
        bytes memory orderUid = "6~ndL\xbe\xcbo?\xd8*K\x92\xae\x11\xf97\r5\x82\xb5\xa4\x1c\x8a\xb11yj/\x02\x8f\x99\xceq\x06]@\x17\xf3\x16\xec`o\xe4B.\x11\xeb,G\xc2Fu\xa599";
        CowswapTypes.CowswapOrder memory order = CowswapTypes.CowswapOrder({
            sellAmount: 1*10**18,
            buyAmount: 1377*10**6,
            feeAmount: 1*10**15,
            sellToken: WETH,
            buyToken: USDC,
            validTo: 1973762361 //10 years from now
        });
        cowswapBridge.addPresignOrder(order, orderUid);
    }

    function _setupPresignOrder1() public {
        // 05fd87bcc9d395effbecd9a2e669e274e40a1e81056fecfe3a13acd134618211ce71065d4017f316ec606fe4422e11eb2c47c24675a9a089
        bytes memory orderUid = "\x05\xfd\x87\xbc\xc9\xd3\x95\xef\xfb\xec\xd9\xa2\xe6i\xe2t\xe4\n\x1e\x81\x05o\xec\xfe:\x13\xac\xd14a\x82\x11\xceq\x06]@\x17\xf3\x16\xec`o\xe4B.\x11\xeb,G\xc2Fu\xa9\xa0\x89";
        CowswapTypes.CowswapOrder memory order = CowswapTypes.CowswapOrder({
            sellAmount: 2*10**18,
            buyAmount: 170035160559196,
            feeAmount: 263470681207355,
            sellToken: WETH,
            buyToken: USDC,
            validTo: 1973762361 //10 years from now
        });
        cowswapBridge.addPresignOrder(order, orderUid);
    }

    function _setupPresignOrderWithWrongBridgeAddress() public {
        // 0xf98dfeb6a80f2667008c80cad42fba6ef353b66dd8777e935939f3d196e1bf1defc56627233b02ea95bae7e19f648d7dcd5bb1327593faed
        bytes memory orderUid = "\xf9\x8d\xfe\xb6\xa8\x0f&g\x00\x8c\x80\xca\xd4/\xban\xf3S\xb6m\xd8w~\x93Y9\xf3\xd1\x96\xe1\xbf\x1d\xef\xc5f'#;\x02\xea\x95\xba\xe7\xe1\x9fd\x8d}\xcd[\xb12u\x93\xfa\xed";
        CowswapTypes.CowswapOrder memory order = CowswapTypes.CowswapOrder({
            sellAmount: 1*10**18,
            buyAmount: 1377*10**6,
            feeAmount: 1*10**15,
            sellToken: WETH,
            buyToken: USDC,
            validTo: 1973437051 //10 years from now
        });
        cowswapBridge.addPresignOrder(order, orderUid);
    }

    function _setupExpiredPresignOrder() public {
        // 05fd87bcc9d395effbecd9a2e669e274e40a1e81056fecfe3a13acd134618211ce71065d4017f316ec606fe4422e11eb2c47c24675a9a089
        bytes memory orderUid = "\x05\xfd\x87\xbc\xc9\xd3\x95\xef\xfb\xec\xd9\xa2\xe6i\xe2t\xe4\n\x1e\x81\x05o\xec\xfe:\x13\xac\xd14a\x82\x11\xceq\x06]@\x17\xf3\x16\xec`o\xe4B.\x11\xeb,G\xc2Fu\xa9\xa0\x89";
        CowswapTypes.CowswapOrder memory order = CowswapTypes.CowswapOrder({
            sellAmount: 2*10**18,
            buyAmount: 170035160559196,
            feeAmount: 263470681207355,
            sellToken: WETH,
            buyToken: USDC,
            validTo: 1073762361
        });
        cowswapBridge.addPresignOrder(order, orderUid);
    }
}