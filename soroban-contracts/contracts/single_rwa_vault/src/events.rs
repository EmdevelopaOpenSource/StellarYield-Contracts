//! Soroban events for SingleRWA_Vault.
//!
//! Each function mirrors an EVM event from ISingleRWA_Vault.sol.

use soroban_sdk::{symbol_short, Address, Env, String};

use crate::types::VaultState;

pub fn emit_zkme_verifier_updated(e: &Env, old: Address, new: Address) {
    e.events().publish(
        (symbol_short!("zkme_upd"),),
        (old, new),
    );
}

pub fn emit_cooperator_updated(e: &Env, old: Address, new: Address) {
    e.events().publish(
        (symbol_short!("coop_upd"),),
        (old, new),
    );
}

pub fn emit_yield_distributed(e: &Env, epoch: u32, amount: i128, timestamp: u64) {
    e.events().publish(
        (symbol_short!("yield_dis"), epoch),
        (amount, timestamp),
    );
}

pub fn emit_yield_claimed(e: &Env, user: Address, amount: i128, epoch: u32) {
    e.events().publish(
        (symbol_short!("yield_clm"), user),
        (amount, epoch),
    );
}

pub fn emit_vault_state_changed(e: &Env, old: VaultState, new: VaultState) {
    e.events().publish(
        (symbol_short!("st_chg"),),
        (old, new),
    );
}

pub fn emit_maturity_date_set(e: &Env, timestamp: u64) {
    e.events().publish(
        (symbol_short!("mat_set"),),
        timestamp,
    );
}

pub fn emit_deposit_limits_updated(e: &Env, min: i128, max: i128) {
    e.events().publish(
        (symbol_short!("dep_lim"),),
        (min, max),
    );
}

pub fn emit_operator_updated(e: &Env, operator: Address, status: bool) {
    e.events().publish(
        (symbol_short!("op_upd"), operator),
        status,
    );
}

pub fn emit_emergency_action(e: &Env, paused: bool, reason: String) {
    e.events().publish(
        (symbol_short!("emergency"),),
        (paused, reason),
    );
}

// SEP-41 events
pub fn emit_approval(
    e: &Env,
    from: Address,
    spender: Address,
    amount: i128,
    expiration_ledger: u32,
) {
    e.events().publish(
        (symbol_short!("approve"), from, spender),
        (amount, expiration_ledger),
    );
}

pub fn emit_transfer(e: &Env, from: Address, to: Address, amount: i128) {
    e.events().publish(
        (symbol_short!("transfer"), from, to),
        amount,
    );
}

pub fn emit_burn(e: &Env, from: Address, amount: i128) {
    e.events().publish(
        (symbol_short!("burn"), from),
        amount,
    );
}

pub fn emit_address_blacklisted(e: &Env, address: Address, status: bool) {
    e.events().publish(
        (symbol_short!("blklist"), address),
        status,
    );
}
