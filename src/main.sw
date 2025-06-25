contract;
use std::hash::{Hash, keccak256, sha256};
use std::bytes::Bytes;
use std::ecr::{ec_recover, ec_recover_address, EcRecoverError};
use std::b512::B512;
use std::array_conversions::{b256::*, u16::*, u256::*, u32::*, u64::*};
use std::logging::log;
use std::asset::transfer;
use std::block::height;
use std::call_frames::msg_asset_id;
use std::context::msg_amount;
use std::constants::ZERO_B256;

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
    payments: StorageMap<Address, u256> = StorageMap {},
    // _INITIATE_TYPEHASH: b256 = keccak256("Initiate(address redeemer,uint256 timelock,uint256 amount,bytes32 secretHash)"),
    // _REFUND_TYPEHASH: b256 = keccak256("Refund(bytes32 orderId)"),
    _INITIATE_TYPEHASH: b256 = ZERO_B256,
    _REFUND_TYPEHASH: b256 = ZERO_B256,
}

configurable {
    token: AssetId = AssetId::from(ZERO_B256),
}

enum UnsafeParams {
    ZeroAddressRedeemer: (),
    ZeroTimelock: (),
    ZeroAmount: (),
}

enum UnsafeTransfer {
    InvalidAsset: (),
    InvalidAmount: (),
}

fn safe_params(redeemer: Address, timelock: u256, amount: u256) -> Result<(), UnsafeParams> {
    log("Checking params: ");
    require(
        redeemer != Address::zero(),
        UnsafeParams::ZeroAddressRedeemer,
    );
    require(timelock > 0, UnsafeParams::ZeroTimelock);
    require(amount > 0, UnsafeParams::ZeroAmount);
    log("Params are safe");
    Ok(())
}
#[storage(read, write)]
fn safe_transfer_from(
    sender: Address,
    asset_id: AssetId,
    amount: u256,
    msg_amount: u256,
) -> Result<(), UnsafeTransfer> {
    require(asset_id == token, UnsafeTransfer::InvalidAsset);
    require(amount == msg_amount, UnsafeTransfer::InvalidAmount);
    storage.payments.insert(sender, msg_amount);
    Ok(())
}

abi HTLC {
    #[payable, storage(read, write)]
    fn initiate(
        redeemer: Address,
        timelock: u256,
        amount: u256,
        secret_hash: b256,
    ) -> bool;
    #[payable, storage(read, write)]
    fn initiate_on_behalf(
        initiator: Address,
        redeemer: Address,
        timelock: u256,
        amount: u256,
        secret_hash: b256,
    );
    #[payable, storage(read, write)]
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
    #[storage(read, write)]
    fn instant_refund_digest(order_id: b256) -> b256;
}

impl HTLC for Contract {
    #[payable, storage(read, write)]
    fn initiate(
        redeemer: Address,
        timelock: u256,
        amount: u256,
        secret_hash: b256,
    ) -> bool {
        require(safe_params(redeemer, timelock, amount).is_ok(), true);
        log("Initiated with params: ");
        log(redeemer);
        log(timelock);
        log(amount);
        let asset_id = msg_asset_id();
        let msg_amount = u256::from(msg_amount());
        let msg_sender = match msg_sender() {
            Ok(Identity::Address(addr)) => addr,
            _ => revert(0),
        };
        match safe_transfer_from(msg_sender, asset_id, msg_amount, amount) {
            Ok(_) => (),
            Err(_) => revert(0),
        };
        _initiate(
            msg_sender,
            msg_sender,
            redeemer,
            timelock,
            amount,
            secret_hash,
        );
        true
    }

    #[payable, storage(read, write)]
    fn initiate_on_behalf(
        initiator: Address,
        redeemer: Address,
        timelock: u256,
        amount: u256,
        secret_hash: b256,
    ) {
        require(safe_params(redeemer, timelock, amount).is_ok(), true);
        let asset_id = msg_asset_id();
        let msg_amount = u256::from(msg_amount());
        let msg_sender = match msg_sender() {
            Ok(Identity::Address(addr)) => addr,
            _ => revert(0),
        };
        match safe_transfer_from(msg_sender, asset_id, msg_amount, amount) {
            Ok(_) => (),
            Err(_) => revert(0),
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

    #[payable, storage(read, write)]
    fn initiate_with_signature(
        redeemer: Address,
        timelock: u256,
        amount: u256,
        secret_hash: b256,
        signature: Bytes,
    ) {
        require(safe_params(redeemer, timelock, amount).is_ok(), true);
        let hash = storage._INITIATE_TYPEHASH.try_read().unwrap();
        let encoded = core::codec::encode((hash, redeemer, timelock, amount, secret_hash));
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
        let asset_id = msg_asset_id();
        let msg_amount = u256::from(msg_amount());
        let msg_sender = match msg_sender() {
            Ok(Identity::Address(addr)) => addr,
            _ => revert(0),
        };
        match safe_transfer_from(msg_sender, asset_id, msg_amount, amount) {
            Ok(_) => (),
            Err(_) => revert(0),
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
        let mut payment = storage.payments.get(order.initiator).try_read().unwrap();
        payment -= order.amount;
        storage.payments.insert(order.initiator, payment);
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
        let mut payment = storage.payments.get(order.initiator).try_read().unwrap();
        payment -= order.amount;
        storage.payments.insert(order.initiator, payment);
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
        let MSG_HASH = _instant_refund_digest(order_ID);
        let redeemer = match ec_recover_address(sig_B512, MSG_HASH) {
            Ok(addr) => addr,
            Err(EcRecoverError) => revert(0),
        };
        require(
            order.redeemer == redeemer,
            "HTLC: invalid redeemer signature",
        );
        require(!order.is_fulfilled, "HTLC: order fulfilled");

        order.is_fulfilled = true;
        storage.orders.insert(order_ID, order);

        log(RefundedEvent { order_ID });
        let mut payment = storage.payments.get(order.initiator).try_read().unwrap();
        payment -= order.amount;
        storage.payments.insert(order.initiator, payment);
        transfer(
            Identity::Address(order.initiator),
            token,
            <u64 as TryFrom<u256>>::try_from(order.amount)
                .unwrap(),
        )
    }
    #[storage(read, write)]
    fn instant_refund_digest(order_ID: b256) -> b256 {
        _instant_refund_digest(order_ID)
    }
}
#[storage(read, write)]
fn _initiate(
    funder_: Address,
    initiator_: Address,
    redeemer_: Address,
    timelock_: u256,
    amount_: u256,
    secret_hash_: b256,
) {
    require(initiator_ != redeemer_, "HTLC: same initiator and redeemer");
    let deposited = storage.payments.get(funder_).try_read().unwrap();
    require(deposited == amount_, "HTLC: invalid amount paid");
    let encoded = core::codec::encode(("chainId", secret_hash_, initiator_));
    let order_ID = sha256(Bytes::from(encoded));
    let order = storage.orders.get(order_ID).try_read().unwrap();
    require(order.redeemer == Address::zero(), "HTLC: duplicate order");
    let new_order = Order {
        is_fulfilled: false,
        initiator: initiator_,
        redeemer: redeemer_,
        initiated_at: u256::from(height()),
        timelock: timelock_,
        amount: amount_,
    };
    storage.orders.insert(order_ID, new_order);
    log(InitiatedEvent {
        order_ID,
        secret_hash: secret_hash_,
        amount: amount_,
    });
}
#[storage(read, write)]
fn _instant_refund_digest(order_ID: b256) -> b256 {
    let hash = storage._REFUND_TYPEHASH.try_read().unwrap();
    let encoded = core::codec::encode((hash, order_ID));
    let hashed = keccak256(Bytes::from(encoded));
    let MSG_HASH = <b256 as From<Bytes>>::from(Bytes::from(hashed));
    MSG_HASH
}
