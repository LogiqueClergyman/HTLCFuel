contract;
use std::hash::{Hash, keccak256, sha256};
use std::bytes::Bytes;
use std::ecr::{ec_recover, ec_recover_address, EcRecoverError};
use std::b512::B512;
use std::array_conversions::{b256::*, u16::*, u256::*, u32::*, u64::*};
use std::logging::log;
use std::asset::transfer;
use std::block::height;
struct Order {
    is_fulfilled: bool,
    initiator: Address,
    redeemer: Address,
    initiated_at: u256,
    timelock: u256,
    amount: u256,
}

struct InitiatedEvent {
    order_ID: b256,
    secret_hash: b256,
    amount: u256,
}

struct RedeemedEvent {
    order_ID: b256,
    secret_hash: b256,
    secret: Bytes,
}

struct RefundedEvent {
    order_ID: b256,
}

storage {
    orders: StorageMap<b256, Order> = StorageMap {},
    // _INITIATE_TYPEHASH: b256 = keccak256("Initiate(address redeemer,uint256 timelock,uint256 amount,bytes32 secretHash)"),
    // _REFUND_TYPEHASH: b256 = keccak256("Refund(bytes32 orderId)"),
}

configurable {}

enum UnsafeParams {
    ZeroAddressRedeemer: (),
    ZeroTimelock: (),
    ZeroAmount: (),
}

enum UnsafeTransfer {}

fn safe_params(redeemer: Address, timelock: u256, amount: u256) -> Result<(), UnsafeParams> {
    require(
        redeemer != Address::zero(),
        UnsafeParams::ZeroAddressRedeemer,
    );
    require(timelock > 0, UnsafeParams::ZeroTimelock);
    require(amount > 0, UnsafeParams::ZeroAmount);
    Ok(())
}

fn safe_transfer() -> Result<(), ()> {
    Ok(())
}

abi HTLC {
    fn initiate(
        redeemer: Address,
        timelock: u256,
        amount: u256,
        secret_hash: b256,
    );

    fn initiate_on_behalf(
        initiator: Address,
        redeemer: Address,
        timelock: u256,
        amount: u256,
        secret_hash: b256,
    );

    fn initiate_with_signature(
        redeemer: Address,
        timelock: u256,
        amount: u256,
        secret_hash: b256,
        signature: Bytes,
    );

    #[storage(read, write)]
    fn redeem(order_id: b256, secret: Bytes);

    #[storage(read, write)]
    fn refund(order_id: b256);

    #[storage(read, write)]
    fn instant_refund(order_id: b256, signature: Bytes);
    // fn instant_refund_digest(order_id: b256) -> b256;
}

impl HTLC for Contract {
    fn initiate(
        redeemer: Address,
        timelock: u256,
        amount: u256,
        secret_hash: b256,
    ) {
        require(safe_params(redeemer, timelock, 0).is_ok(), true);
        let msg_sender = match msg_sender() {
            Ok(Identity::Address(addr)) => addr,
            _ => revert(0),
        };
        _initiate(
            msg_sender,
            msg_sender,
            redeemer,
            timelock,
            amount,
            secret_hash,
        );
    }

    fn initiate_on_behalf(
        initiator: Address,
        redeemer: Address,
        timelock: u256,
        amount: u256,
        secret_hash: b256,
    ) {
        require(safe_params(redeemer, timelock, 0).is_ok(), true);
        let msg_sender = match msg_sender() {
            Ok(Identity::Address(addr)) => addr,
            _ => revert(0),
        };
        _initiate(
            msg_sender,
            initiator,
            redeemer,
            timelock,
            amount,
            secret_hash,
        );
    }
    fn initiate_with_signature(
        redeemer: Address,
        timelock: u256,
        amount: u256,
        secret_hash: b256,
        signature: Bytes,
    ) {
        require(safe_params(redeemer, timelock, 0).is_ok(), true);

        let _INITIATE_TYPEHASH: b256 = keccak256("Initiate(address redeemer,uint256 timelock,uint256 amount,bytes32 secretHash)");

        let encoded = core::codec::encode((_INITIATE_TYPEHASH, redeemer, timelock, amount, secret_hash));
        let hashed = keccak256(Bytes::from(encoded));
        let MSG_HASH = <b256 as From<Bytes>>::from(Bytes::from(hashed));

        let mut r_array = [0u8; 32];
        let mut s_array = [0u8; 32];
        let mut i = 0;
        while i < 32 {
            r_array[i] = signature.get(i).unwrap();
            s_array[i] = signature.get(i + 32).unwrap();
            i += 1;
        }

        let r = b256::from_be_bytes(r_array);
        let s = b256::from_be_bytes(s_array);
        let sig_B512 = B512::from((r, s));
        let initiator = match ec_recover_address(sig_B512, MSG_HASH) {
            Ok(addr) => addr,
            Err(EcRecoverError) => revert(0),
        };
        _initiate(
            initiator,
            initiator,
            redeemer,
            timelock,
            amount,
            secret_hash,
        );
    }

    #[storage(read, write)]
    fn redeem(order_ID: b256, secret: Bytes) {
        let mut order = storage.orders.get(order_ID).try_read().unwrap();

        require(
            order.redeemer != Address::zero(),
            "HTLC: order not initiated",
        );
        require(!order.is_fulfilled, "HTLC: order fulfilled");

        let secret_hash = sha256(secret);
        let encoded = core::codec::encode(("chainId", secret_hash, order.initiator));
        require(
            sha256(Bytes::from(encoded)) == order_ID,
            "HTLC: incorrect secret",
        );
        order.is_fulfilled = true;
        storage.orders.insert(order_ID, order);

        log(RedeemedEvent {
            order_ID,
            secret_hash,
            secret,
        });
        let token: AssetId = AssetId::from(b256::from(0));
        transfer(
            Identity::Address(order.redeemer),
            token,
            <u64 as TryFrom<u256>>::try_from(order.amount)
                .unwrap(),
        );
    }

    #[storage(read, write)]
    fn refund(order_ID: b256) {
        let mut order = storage.orders.get(order_ID).try_read().unwrap();

        require(
            order.redeemer != Address::zero(),
            "HTLC: order not initiated",
        );

        require(!order.is_fulfilled, "HTLC: order fulfilled");
        require(
            order.initiated_at + order.timelock < u256::from(height()),
            "HTLC: order not expired",
        );

        order.is_fulfilled = true;
        storage.orders.insert(order_ID, order);

        log(RefundedEvent { order_ID });
        let token: AssetId = AssetId::from(b256::from(0));
        transfer(
            Identity::Address(order.initiator),
            token,
            <u64 as TryFrom<u256>>::try_from(order.amount)
                .unwrap(),
        );
    }

    #[storage(read, write)]
    fn instant_refund(order_ID: b256, signature: Bytes) {
        let mut order = storage.orders.get(order_ID).try_read().unwrap();
        let redeemer = instant_refund_digest(order_ID);
        require(
            order.redeemer == redeemer,
            "HTLC: invalid redeemer signature",
        );
        require(!order.is_fulfilled, "HTLC: order fulfilled");

        order.is_fulfilled = true;
        storage.orders.insert(order_ID, order);

        log(RefundedEvent { order_ID });
        let token: AssetId = AssetId::from(b256::from(0));
        transfer(
            Identity::Address(order.initiator),
            token,
            <u64 as TryFrom<u256>>::try_from(order.amount)
                .unwrap(),
        )
    }
}

fn _initiate(
    funder: Address,
    initiator: Address,
    redeemer: Address,
    timelock: u256,
    amount: u256,
    secret_hash: b256,
) {}

fn instant_refund_digest(order_ID: b256) -> Address {
    let _REFUND_TYPEHASH: b256 = keccak256("Refund(bytes32 orderId)");
    let encoded = core::codec::encode((_REFUND_TYPEHASH, order_ID));
    let hashed = keccak256(Bytes::from(encoded));
    Address::from(<b256 as From<Bytes>>::from(Bytes::from(hashed)))
}
