contract;

use std::hash::{Hash, keccak256};
use std::bytes::Bytes;
use std::ecr::{ec_recover, ec_recover_address, EcRecoverError};
use std::b512::B512;
use std::array_conversions::{b256::*, u16::*, u256::*, u32::*, u64::*,};
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

configurable {
    token: Address = Address::from(0x09c0b2d1a486c439a87bcba6b46a7a1a23f3897cc83a94521a96da5c23bc58db),
}

enum UnsafeParams {
    ZeroAddressRedeemer: (),
    ZeroTimelock: (),
    ZeroAmount: (),
}

fn safe_params(redeemer: Address, timelock: u256, amount: u256) -> Result<(), UnsafeParams> {
    require(
        redeemer != Address::zero(),
        UnsafeParams::ZeroAddressRedeemer,
    );
    require(timelock > 0, UnsafeParams::ZeroTimelock);
    require(amount > 0, UnsafeParams::ZeroAmount);
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
    fn instant_refund_digest(order_id: b256) -> b256;
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
        let _REFUND_TYPEHASH: b256 = keccak256("Refund(bytes32 orderId)");
        let encoded = core::codec::encode((
            _INITIATE_TYPEHASH,
            redeemer,
            timelock,
            amount,
            secret_hash,
        ));
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

        let b512 = B512::from((r, s));

        ///////////////////////////////////////
        ///////////////////////////////////////
        ///////////////////////////////////////
        ///////////////////////////////////////
        ///////////////////////////////////////
    }

    #[storage(read, write)]
    fn redeem(order_ID: b256, secret: Bytes) {}
    #[storage(read, write)]
    fn refund(order_ID: b256) {}

    #[storage(read, write)]
    fn instant_refund(order_ID: b256, signature: Bytes) {}
    fn instant_refund_digest(order_ID: b256) -> b256 {
        order_ID
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
