// SPDX-License-Identifier: Apache-2.0
// Copyright 2022 Aztec.
pragma solidity >=0.8.4;

import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

import {BaseDeployment} from "./base/BaseDeployment.s.sol";
import {IRollupProcessor} from "rollup-encoder/interfaces/IRollupProcessor.sol";
import {DataProvider} from "../aztec/DataProvider.sol";

import {CurveDeployment} from "./curve/CurveDeployment.s.sol";
import {DonationDeployment} from "./donation/DonationDeployment.s.sol";
import {ERC4626Deployment} from "./erc4626/ERC4626Deployment.s.sol";
import {ERC4626Lister} from "./erc4626/ERC4626Lister.s.sol";
import {LiquityTroveDeployment} from "./liquity/LiquityTroveDeployment.s.sol";
import {UniswapDeployment} from "./uniswap/UniswapDeployment.s.sol";
import {YearnDeployment} from "./yearn/YearnDeployment.s.sol";
import {DCADeployment} from "./dca/DCADeployment.s.sol";
import {AngleSLPDeployment} from "./angle/AngleSLPDeployment.s.sol";
import {DataProviderDeployment} from "./dataprovider/DataProviderDeployment.s.sol";
import {CurveStethLpDeployment} from "./curve/CurveStethLpDeployment.s.sol";

/**
 * A helper script that allow easy deployment of multiple bridges
 */
contract AggregateDeployment is BaseDeployment {
    address internal erc4626Bridge;

    function deployAndListAll() public {
        DataProviderDeployment dataProviderDeploy = new DataProviderDeployment();
        dataProviderDeploy.setUp();
        address dataProvider = dataProviderDeploy.deploy();

        emit log("--- Curve ---");
        {
            CurveDeployment curveDeployment = new CurveDeployment();
            curveDeployment.setUp();
            curveDeployment.deployAndList();
        }

        emit log("--- Yearn ---");
        {
            YearnDeployment yearnDeployment = new YearnDeployment();
            yearnDeployment.setUp();
            yearnDeployment.deployAndList();
        }

        emit log("--- Element 2M ---");
        {
            uint256 element2Id = listBridge(IRollupProcessor(ROLLUP_PROCESSOR).getSupportedBridge(1), 2000000);
            emit log_named_uint("Element 2M bridge address id", element2Id);
        }

        emit log("--- ERC4626 ---");
        {
            ERC4626Deployment erc4626Deployment = new ERC4626Deployment();
            erc4626Deployment.setUp();
            erc4626Bridge = erc4626Deployment.deploy();

            uint256 depositAddressId = listBridge(erc4626Bridge, 300000);
            emit log_named_uint("ERC4626 bridge address id (300k gas)", depositAddressId);
        }

        emit log("--- Euler ---");
        {
            ERC4626Lister lister = new ERC4626Lister();
            lister.setUp();

            address erc4626EulerWETH = 0x3c66B18F67CA6C1A71F829E2F6a0c987f97462d0;
            lister.listVault(erc4626Bridge, erc4626EulerWETH);
            uint256 weWethAssetId = listAsset(erc4626EulerWETH, 55000);
            emit log_named_uint("ERC4626 euler weth id", weWethAssetId);

            address erc4626EulerWSTETH = 0x60897720AA966452e8706e74296B018990aEc527;
            lister.listVault(erc4626Bridge, erc4626EulerWSTETH);
            uint256 wewstEthAssetId = listAsset(erc4626EulerWSTETH, 55000);
            emit log_named_uint("ERC4626 euler wstEth id", wewstEthAssetId);

            address erc4626EulerDai = 0x4169Df1B7820702f566cc10938DA51F6F597d264;
            lister.listVault(erc4626Bridge, erc4626EulerDai);
            uint256 wedaiAssetId = listAsset(erc4626EulerDai, 55000);
            emit log_named_uint("ERC4626 euler dai id", wedaiAssetId);
        }

        emit log("--- DCA ---");
        {
            DCADeployment dcaDeployment = new DCADeployment();
            dcaDeployment.setUp();
            dcaDeployment.deployAndList();
        }

        emit log("--- ERC4626 400k and 500k gas configurations ---");
        {
            uint256 depositAddressId = listBridge(erc4626Bridge, 500000);
            emit log_named_uint("ERC4626 bridge address id (500k gas)", depositAddressId);

            depositAddressId = listBridge(erc4626Bridge, 400000);
            emit log_named_uint("ERC4626 bridge address id (400k gas)", depositAddressId);
        }

        emit log("--- AAVE v2 ---");
        {
            ERC4626Lister lister = new ERC4626Lister();
            lister.setUp();

            address erc4626AaveV2Dai = 0xbcb91e0B4Ad56b0d41e0C168E3090361c0039abC;
            lister.listVault(erc4626Bridge, erc4626AaveV2Dai);
            uint256 erc4626AaveV2DaiId = listAsset(erc4626AaveV2Dai, 55000);
            emit log_named_uint("ERC4626 aave v2 dai id", erc4626AaveV2DaiId);

            address erc4626AaveV2WETH = 0xc21F107933612eCF5677894d45fc060767479A9b;
            lister.listVault(erc4626Bridge, erc4626AaveV2WETH);
            uint256 erc4626AaveV2WETHId = listAsset(erc4626AaveV2WETH, 55000);
            emit log_named_uint("ERC4626 aave v2 weth id", erc4626AaveV2WETHId);
        }

        emit log("--- Liquity 275% CR and 400% CR deployments ---");
        {
            LiquityTroveDeployment liquityTroveDeployment = new LiquityTroveDeployment();
            liquityTroveDeployment.setUp();

            liquityTroveDeployment.deployAndList(275);
            liquityTroveDeployment.deployAndList(400);
        }

        emit log("--- Compound ---");
        {
            ERC4626Lister lister = new ERC4626Lister();
            lister.setUp();

            address erc4626CompoundDai = 0x6D088fe2500Da41D7fA7ab39c76a506D7c91f53b;
            lister.listVault(erc4626Bridge, erc4626CompoundDai);
            uint256 erc4626CDaiId = listAsset(erc4626CompoundDai, 55000);
            emit log_named_uint("ERC4626 compound dai id", erc4626CDaiId);
        }

        emit log("--- Uniswap ---");
        {
            UniswapDeployment uniswapDeployment = new UniswapDeployment();
            uniswapDeployment.setUp();
            uniswapDeployment.deployAndList();
        }

        emit log("--- Set ---");
        {
            address iceth = 0x7C07F7aBe10CE8e33DC6C5aD68FE033085256A84;
            uint256 icethId = listAsset(iceth, 55000);
            emit log_named_uint("Set protocol icEth id", icethId);
        }

        emit log("--- Let anyone deploy ---");
        {
            IRollupProcessor rp = IRollupProcessor(ROLLUP_PROCESSOR);
            if (!rp.allowThirdPartyContracts()) {
                vm.broadcast();
                rp.setAllowThirdPartyContracts(true);
            }
        }

        emit log("--- Data Provider ---");
        {
            dataProviderDeploy.updateNames(dataProvider);
        }
    }

    function readStats() public {
        emit log("--- Stats for the Rollup ---");
        IRollupProcessor rp = IRollupProcessor(ROLLUP_PROCESSOR);

        if (rp.allowThirdPartyContracts()) {
            emit log("Third parties can deploy bridges");
        } else {
            emit log("Third parties cannot deploy bridges");
        }

        uint256 assetCount = assetLength();
        emit log_named_uint("Assets", assetCount + 1);
        for (uint256 i = 0; i <= assetCount; i++) {
            string memory symbol = i > 0 ? IERC20Metadata(rp.getSupportedAsset(i)).symbol() : "Eth";
            uint256 gas = i > 0 ? rp.assetGasLimits(i) : 30000;
            emit log_named_string(
                string(abi.encodePacked("  Asset ", Strings.toString(i))),
                string(abi.encodePacked(symbol, ", ", Strings.toString(gas)))
                );
        }

        uint256 bridgeCount = bridgesLength();
        emit log_named_uint("Bridges", bridgeCount);
        for (uint256 i = 1; i <= bridgeCount; i++) {
            address bridge = rp.getSupportedBridge(i);
            uint256 gas = rp.bridgeGasLimits(i);
            emit log_named_string(
                string(abi.encodePacked("  Bridge ", Strings.toString(i))),
                string(abi.encodePacked(Strings.toHexString(bridge), ", ", Strings.toString(gas)))
                );
        }
    }
}
