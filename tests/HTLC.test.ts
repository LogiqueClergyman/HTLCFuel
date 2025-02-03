import { test, describe, beforeAll, afterAll } from 'bun:test';
import { expect } from 'chai';
import { launchTestNode, TestAssetId } from 'fuels/test-utils';
import { HTLCFuel, HTLCFuelFactory } from '../contracts';
import { BitcoinNetwork, BitcoinProvider, BitcoinWallet } from "@catalogfi/wallets";
import { HTLC as BitcoinHTLC } from "../bitcoin/htlc";
import { regTestUtils } from '../bitcoin/regtest';
import { bn, type WalletUnlocked } from 'fuels';
import { randomBytes, createHash } from 'crypto';
import { sha256 } from 'fuels';

describe('HTLC Tests', () => {

    let customAssetId: TestAssetId;
    let BTCprovider = new BitcoinProvider(BitcoinNetwork.Regtest, "http://localhost:30000");
    console.log("BTC Node connected");
    let owner: WalletUnlocked;
    let alice: WalletUnlocked;
    let bob: WalletUnlocked;
    let charlie: WalletUnlocked;

    let htlcFUEL: HTLCFuel;
    let FUELprovider: any;
    let cleanup: () => void;

    beforeAll(async () => {

        customAssetId = TestAssetId.random()[0];

        const launched = await launchTestNode({
            nodeOptions:{
                loggingEnabled: true,
            },
            walletsConfig: {
                count: 4,
                assets: [customAssetId],
                coinsPerAsset: 1,
                amountPerCoin: 1000000,
            },
            contractsConfigs: [
                {
                    factory: HTLCFuelFactory,
                    walletIndex: 0,
                    options: {
                        configurableConstants: {
                            token: { bits: customAssetId.value },
                        }
                    }
                }
            ]
        });

        const {
            wallets: [wallet1, wallet2, wallet3, wallet4],
            contracts: [contract],
            provider,
        } = launched;
        cleanup = launched.cleanup;
        owner = wallet1;
        alice = wallet2;
        bob = wallet3;
        charlie = wallet4;
        htlcFUEL = contract;
        FUELprovider = provider;

        console.log("owner: ", owner.address.toString());
        console.log("alice: ", alice.address.toString());
        console.log("bob: ", bob.address.toString());
        console.log("charlie: ", charlie.address.toString());
        console.log("contract: ", htlcFUEL.id.toString());
        console.log("Contract deployed, wallets created");
        // console.log((await wallet2.getBalances()).balances[0].amount.toString());



        // Add your test assertions here
    });

    afterAll(async () => {
        cleanup();
    });

    describe('BTC <-> FUEL', () => {
        const aliceBitcoinWallet = BitcoinWallet.createRandom(BTCprovider);
        const bobBitcoinWallet = BitcoinWallet.createRandom(BTCprovider);
        const secret = randomBytes(32);
        const secretHash = '0x' + createHash('sha256').update(secret).digest('hex');
        const fromAmount = 10000;
        const toAmount = bn(90000);
        const expiry = 7200;

        test("Should be able to swap BTC for FUEL", async () => {
            const bobPubkey = await bobBitcoinWallet.getPublicKey();
            const alicePubkey = await aliceBitcoinWallet.getPublicKey();
            console.log("Bob's pubkey: ", bobPubkey);
            console.log("Alice's pubkey: ", alicePubkey);
            await regTestUtils.fund(await aliceBitcoinWallet.getAddress(), BTCprovider);
            console.log("Alice's wallet funded");
            const aliceBitcoinHTLC = await BitcoinHTLC.from(
                aliceBitcoinWallet,
                secretHash,
                alicePubkey,
                bobPubkey,
                expiry
            );

            // Alice initiates in Bitcoin
            await aliceBitcoinHTLC.initiate(fromAmount);
            console.log("Alice initiated in Bitcoin");

            // Bob initiates in Fuel
            console.log("params: ", { bits: alice.address.toB256() }, expiry, toAmount, secretHash);
            htlcFUEL.account = bob;

            const initiateResponse = await htlcFUEL.functions.initiate({ bits: alice.address.toB256() }, expiry, toAmount, secretHash.toString()).callParams(
                {
                    // destination: htlcFUEL.id,
                    // amount: toAmount,
                    // assetId: customAssetId.value
                    forward: [toAmount, customAssetId.value]
                }
            ).call();
            // console.log(initiateResponse);
            // const { logs: initiateLogs, value: initiateValue } = await initiateResponse.waitForResult();
            // console.log("Initiate Logs:", initiateLogs);
            // console.log("Initiate Return Value:", initiateValue);
            // console.log("Bob initiated in Fuel");

            // const secretHashBytes = Buffer.from(secretHash.slice(2), 'hex');
            // const bobAddressBytes = Buffer.from(bob.address.toB256().slice(2), 'hex');
            // const paddedBobAddress = Buffer.concat([Buffer.alloc(12), bobAddressBytes]);
            // const encodedData = Buffer.concat([secretHashBytes, paddedBobAddress]);
            // const orderId = sha256(encodedData);

            // const aliceFUELBalanceBefore = await alice.getBalance(customAssetId.value);

            // // Alice redeems in EVM by providing the secret
            // htlcFUEL.account = alice;
            // await htlcFUEL.functions.redeem(orderId, secret).call();
            // console.log("Alice redeemed in Fuel");

            // // make sure alice received the FUEL
            // expect(await alice.getBalance(customAssetId.value)).to.be.eq(aliceFUELBalanceBefore.add(toAmount));

            // const bobHTLC = await BitcoinHTLC.from(
            //     bobBitcoinWallet,
            //     secretHash,
            //     alicePubkey,
            //     bobPubkey,
            //     expiry
            // );
            // // Bob redeems in Bitcoin
            // const redeemId = await bobHTLC.redeem(secret.toString("hex"));
            // console.log("Bob redeemed in Bitcoin");

            // const tx = await BTCprovider.getTransaction(redeemId);

            // // make sure bob received the BTC
            // expect(tx).to.be.an('object');
            // expect(tx.txid).to.be.eq(redeemId);
            // expect(tx.vout[0].scriptpubkey_address).to.be.eq(await bobBitcoinWallet.getAddress());

        }, { timeout: 1000000 })

        // test("Should be able to swap FUEL for BTC", async () => {
        //     const alicePubkey = await aliceBitcoinWallet.getPublicKey();
        //     const bobPubkey = await bobBitcoinWallet.getPublicKey();
        //     console.log("Alice's pubkey: ", alicePubkey);
        //     console.log("Bob's pubkey: ", bobPubkey);

        //     await regTestUtils.fund(await bobBitcoinWallet.getAddress(), BTCprovider);
        //     console.log("Bob's wallet funded");

        //     // Alice initiates in Fuel
        //     htlcFUEL.account = alice;
        //     await htlcFUEL.functions.initiate({ bits: bob.address.toB256() }, expiry, fromAmount, secretHash).addTransfer({
        //         destination: htlcFUEL.id,
        //         amount: fromAmount,
        //         assetId: customAssetId.value,
        //     }).call();
        //     console.log("Alice initiated in Fuel");

        //     const bobHTLC = await BitcoinHTLC.from(
        //         bobBitcoinWallet,
        //         secretHash,
        //         alicePubkey,
        //         bobPubkey,
        //         expiry
        //     )

        //     // Bob initiates in Bitcoin
        //     await bobHTLC.initiate(Number(toAmount));
        //     console.log("Bob initiated in Bitcoin");

        //     const aliceHTLC = await BitcoinHTLC.from(
        //         aliceBitcoinWallet,
        //         secretHash,
        //         alicePubkey,
        //         bobPubkey,
        //         expiry
        //     );

        //     //Alice redeems in Bitcoin
        //     const txId = await aliceHTLC.redeem(secret.toString("hex"));
        //     console.log("Alice redeemed in Bitcoin");

        //     // make sure alice received the BTC
        //     const tx = await BTCprovider.getTransaction(txId);
        //     expect(tx).to.be.an('object');
        //     expect(tx.txid).to.be.eq(txId);
        //     expect(tx.vout[0].scriptpubkey_address).to.be.eq(await aliceBitcoinWallet.getAddress());

        //     const secretHashBytes = Buffer.from(secretHash.slice(2), 'hex');
        //     const aliceAddressBytes = Buffer.from(alice.address.toB256().slice(2), 'hex');
        //     const paddedAliceAddress = Buffer.concat([Buffer.alloc(12), aliceAddressBytes]);
        //     const encodedData = Buffer.concat([secretHashBytes, paddedAliceAddress]);
        //     const orderId = sha256(encodedData);

        //     const bobBalance = await bob.getBalance(customAssetId.value);

        //     // Bob redeems in Fuel
        //     htlcFUEL.account = bob;
        //     await htlcFUEL.functions.redeem(orderId, secret).call();
        //     console.log("Bob redeemed in Fuel");

        //     // make sure bob received the FUEL
        //     expect(await bob.getBalance(customAssetId.value)).to.be.eq(bobBalance.add(fromAmount));
        // })
    })
});

