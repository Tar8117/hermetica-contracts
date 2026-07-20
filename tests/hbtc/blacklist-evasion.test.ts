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
  mineBlocks(500); // enough blocks to clear the redeem cooldown
}

describe('Blacklist Evasion (soft-blacklist bypass via token transfer)', () => {
  it('SCENARIO 1: soft-blacklisted user exits via a clean address, default config', () => {
    const depositAmount = ONE_BTC;

    // make deployer a blacklister so it can add/remove entries
    txOk(blacklist.setBlacklister(deployer, true), deployer);

    // full blacklist is off by default
    expect(rov(blacklist.getFullBlacklistEnabled())).toBe(false);

    // user1 deposits, gets hBTC shares
    const depositResult = txOk(vault.deposit(depositAmount, null), user1);
    const shares = depositResult.value as bigint;
    expect(rov(hbtcToken.getBalance(user1)).value).toBe(shares);

    // soft-blacklist user1
    txOk(
      blacklist.addBlacklist([{ address: user1, full: false }]),
      deployer,
    );
    expect(rov(blacklist.getSoftBlacklist(user1))).toBe(true);
    expect(rov(blacklist.getFullBlacklist(user1))).toBe(false);

    // direct redeem should fail, this part works fine
    const directAttempt = txErr(vault.requestRedeem(shares, false), user1);
    expect(directAttempt.value).toBe(ERR.SOFT_BLACKLISTED);

    // now transfer to a clean address instead - nothing blocks this
    const transferResult = txOk(
      hbtcToken.transfer(shares, user1, user2, null),
      user1,
    );
    expect(transferResult.value).toBe(true);
    expect(rov(hbtcToken.getBalance(user1)).value).toBe(0n);
    expect(rov(hbtcToken.getBalance(user2)).value).toBe(shares);

    // user2 redeems normally and gets the sBTC
    const redeemRequest = txOk(vault.requestRedeem(shares, false), user2);
    const claimId = redeemRequest.value as bigint;

    advancePastCooldown();

    txOk(vault.fundClaim(claimId), manager);
    const finalRedeem = txOk(vault.redeem(claimId), user2);

    // user1 is still soft-blacklisted, but the funds are already out
    expect(finalRedeem.value as bigint).toBeGreaterThan(0n);
    expect(rov(blacklist.getSoftBlacklist(user1))).toBe(true);
  });

  it('SCENARIO 2: bypass persists even with full-blacklist-enabled = true, for a soft-only address', () => {
    const depositAmount = ONE_BTC;

    txOk(blacklist.setBlacklister(deployer, true), deployer);

    // turn on full-blacklist enforcement to see if that fixes it
    txOk(blacklist.setFullBlacklistEnabled(true), deployer);
    expect(rov(blacklist.getFullBlacklistEnabled())).toBe(true);

    const depositResult = txOk(vault.deposit(depositAmount, null), user1);
    const shares = depositResult.value as bigint;

    // user1 is only soft-blacklisted, not full
    txOk(
      blacklist.addBlacklist([{ address: user1, full: false }]),
      deployer,
    );
    expect(rov(blacklist.getSoftBlacklist(user1))).toBe(true);
    expect(rov(blacklist.getFullBlacklist(user1))).toBe(false);

    txErr(vault.requestRedeem(shares, false), user1);

    // still works - transfer only checks the full flag, not soft,
    // so turning on full-blacklist-enabled doesn't change anything here
    const transferResult = txOk(
      hbtcToken.transfer(shares, user1, user2, null),
      user1,
    );
    expect(transferResult.value).toBe(true);
    expect(rov(hbtcToken.getBalance(user2)).value).toBe(shares);
  });
});
