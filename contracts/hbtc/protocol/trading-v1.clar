;; @contract Trading 
;; @version 1
;; @desc Batched and atomic position management across DeFi protocols

(use-trait ft 'SP2VCQJGH7PHP2DJK7Z0V48AGBHQAW3R3ZW1QF4N.ft-trait.ft-trait)
(use-trait zest-market .zest-market-trait-v1.zest-market-trait)
(use-trait zest-vault .zest-vault-trait-v1.zest-vault-trait)
(use-trait hbtc-vault .vault-trait-v1.vault-trait)
(use-trait staking .staking-trait-v1.staking-trait)
(use-trait staking-silo .staking-silo-trait-v1.staking-silo-trait)

;;-------------------------------------
;; Constants
;;-------------------------------------

(define-constant ERR_INVALID_AMOUNT (err u120001))

;;-------------------------------------
;; Helper Functions (Common to Both Paths)
;;-------------------------------------

;; @desc - Borrows USDh from Zest v2 market and stakes it in Hermetica
;; @param - market-trait: Zest v2 market contract
;; @param - staking-trait: Hermetica staking contract
;; @param - usdh-token-trait: USDh token contract
;; @param - usdh-amount: Amount of USDh to borrow and stake
;; @param - price-feed-1: Pyth price feed data
;; @param - price-feed-2: Secondary price feed data
(define-public (zest-open
  (market-trait <zest-market>) (staking-trait <staking>) 
  (usdh-token-trait <ft>)
  (usdh-amount uint)
  (price-feed-1 (optional (buff 8192))) (price-feed-2 (optional (buff 8192))))
  (begin
    (try! (contract-call? .hq-hbtc-v1 check-is-trader contract-caller))
    (asserts! (> usdh-amount u0) ERR_INVALID_AMOUNT)
    ;; Borrow USDh from Zest v2 market
    (try! (contract-call? .zest-interface-v0-2 zest-borrow market-trait usdh-token-trait usdh-amount price-feed-1 price-feed-2))
    ;; Stake the borrowed USDh into Hermetica
    (try! (contract-call? .hermetica-interface-v1 hermetica-stake usdh-amount staking-trait))
    (ok true)
  )
)

;; @desc - Unstakes sUSDh from Hermetica and repays USDh to Zest v2 market
;; @param - market-trait: Zest v2 market contract
;; @param - staking-trait: Hermetica staking contract
;; @param - staking-silo-trait: Hermetica silo for withdrawal claims
;; @param - usdh-token-trait: USDh token contract
;; @param - susdh-amount: Amount of sUSDh to unstake
;; @param - price-feed-1: Pyth price feed data
;; @param - price-feed-2: Secondary price feed data
(define-public (zest-close
  (market-trait <zest-market>) (staking-trait <staking>) (staking-silo-trait <staking-silo>) 
  (usdh-token-trait <ft>)
  (susdh-amount uint)
  (price-feed-1 (optional (buff 8192))) (price-feed-2 (optional (buff 8192))))
  (begin
    (try! (contract-call? .hq-hbtc-v1 check-is-trader contract-caller))
    (asserts! (> susdh-amount u0) ERR_INVALID_AMOUNT)
    (let (
      ;; Unstake sUSDh from Hermetica (instant withdrawal)
      (usdh-amount (try! (contract-call? .hermetica-interface-v1 hermetica-unstake-and-withdraw susdh-amount staking-trait staking-silo-trait))))
      ;; Repay USDh loan to Zest v2 market
      (try! (contract-call? .zest-interface-v0-2 zest-repay market-trait usdh-token-trait usdh-amount price-feed-1 price-feed-2))
      (ok true)
    )
  )
)

;;=====================================
;; DIRECT PATH (sBTC as Collateral)
;;=====================================

;;-------------------------------------
;; Open Position - Direct Path
;;-------------------------------------

;; @desc - Opens a leveraged position using direct sBTC collateral
;; @note - Uses sBTC directly as collateral in Zest market (no vault intermediary)
;; @param - market-trait: Zest v2 market contract
;; @param - staking-trait: Hermetica staking contract
;; @param - sbtc-token-trait: sBTC token contract
;; @param - usdh-token-trait: USDh token contract
;; @param - sbtc-amount: Amount of sBTC to add as collateral
;; @param - usdh-amount: Amount of USDh to borrow
;; @param - price-feed-1: Pyth price feed data for sBTC
;; @param - price-feed-2: Secondary price feed data
(define-public (zest-open-add
  (market-trait <zest-market>) (staking-trait <staking>) (sbtc-token-trait <ft>) (usdh-token-trait <ft>)
  (sbtc-amount uint) (usdh-amount uint)
  (price-feed-1 (optional (buff 8192))) (price-feed-2 (optional (buff 8192))))
  (begin
    (try! (contract-call? .hq-hbtc-v1 check-is-trader contract-caller))
    (asserts! (> sbtc-amount u0) ERR_INVALID_AMOUNT)
    (asserts! (> usdh-amount u0) ERR_INVALID_AMOUNT)

    ;; Step 1: Add sBTC directly as collateral
    (try! (contract-call? .zest-interface-v0-2 zest-collateral-add market-trait sbtc-token-trait sbtc-amount price-feed-1 price-feed-2))

    ;; Step 2: Borrow USDh and stake it in Hermetica
    (try! (zest-open market-trait staking-trait usdh-token-trait usdh-amount price-feed-1 price-feed-2))

    (print { action: "zest-open-add", user: contract-caller, data: { sbtc-amount: sbtc-amount, usdh-amount: usdh-amount } })
    (ok true)
  )
)

;;-------------------------------------
;; Close Position - Direct Path
;;-------------------------------------

;; @desc - Closes a leveraged position using direct sBTC collateral
;; @note - Removes sBTC directly from Zest market (no vault intermediary)
;; @param - market-trait: Zest v2 market contract
;; @param - staking-trait: Hermetica staking contract
;; @param - staking-silo-trait: Hermetica silo for withdrawal claims
;; @param - hbtc-vault-trait: Vault for sBTC collateral claims
;; @param - sbtc-token-trait: sBTC token contract
;; @param - usdh-token-trait: USDh token contract
;; @param - susdh-amount: Amount of sUSDh to unstake from Hermetica
;; @param - collateral-amount: Amount of sBTC collateral to remove
;; @param - claim-ids: List of claim IDs to fund with sBTC (optional, can be empty)
;; @param - price-feed-1: Pyth price feed data for sBTC
;; @param - price-feed-2: Secondary price feed data
(define-public (zest-close-remove
  (market-trait <zest-market>) (staking-trait <staking>) (staking-silo-trait <staking-silo>) (hbtc-vault-trait <hbtc-vault>)
  (sbtc-token-trait <ft>) (usdh-token-trait <ft>)
  (susdh-amount uint) (collateral-amount uint)
  (claim-ids (list 100 uint))
  (price-feed-1 (optional (buff 8192))) (price-feed-2 (optional (buff 8192))))
  (begin
    (try! (contract-call? .hq-hbtc-v1 check-is-trader contract-caller))
    (asserts! (> susdh-amount u0) ERR_INVALID_AMOUNT)
    (asserts! (> collateral-amount u0) ERR_INVALID_AMOUNT)

    ;; Step 1: Unstake sUSDh and repay USDh loan
    (try! (zest-close market-trait staking-trait staking-silo-trait usdh-token-trait susdh-amount price-feed-1 price-feed-2))

    ;; Step 2: Remove sBTC collateral
    (try! (contract-call? .zest-interface-v0-2 zest-collateral-remove market-trait sbtc-token-trait collateral-amount price-feed-1 price-feed-2))
    
    ;; Step 3: Optional - Fund claims with sBTC now in reserve
    (if (> (len claim-ids) u0)
      (begin
        (try! (contract-call? .hq-hbtc-v1 check-is-protocol (contract-of hbtc-vault-trait)))
        (try! (contract-call? hbtc-vault-trait fund-claim-many claim-ids))
      )
      true)

    (print { action: "zest-close-remove", user: contract-caller, data: { susdh-amount: susdh-amount, collateral-amount: collateral-amount, claim-ids: claim-ids } })
    (ok true)
  )
)

;;=====================================
;; VAULT PATH (sBTC -> z-tokens)
;;=====================================

;;-------------------------------------
;; Open Position - Vault Path
;;-------------------------------------

;; @desc - Opens a leveraged position using vault path
;; @note - Deposits sBTC to vault, receives z-tokens, uses z-tokens as collateral
;; @param - market-trait: Zest v2 market contract
;; @param - vault-trait: Zest v2 vault contract
;; @param - staking-trait: Hermetica staking contract
;; @param - sbtc-token-trait: sBTC token contract
;; @param - z-token-trait: Z-token from vault
;; @param - usdh-token-trait: USDh token contract
;; @param - sbtc-amount: Amount of sBTC to supply to vault
;; @param - usdh-amount: Amount of USDh to borrow
;; @param - min-shares: Minimum vault shares to receive
;; @param - price-feed-1: Pyth price feed data for sBTC
;; @param - price-feed-2: Secondary price feed data
(define-public (zest-open-add-deposit
  (market-trait <zest-market>) (vault-trait <zest-vault>) (staking-trait <staking>)
  (sbtc-token-trait <ft>) (z-token-trait <ft>) (usdh-token-trait <ft>)
  (sbtc-amount uint) (usdh-amount uint) (min-shares uint)
  (price-feed-1 (optional (buff 8192))) (price-feed-2 (optional (buff 8192))))
  (begin
    (try! (contract-call? .hq-hbtc-v1 check-is-trader contract-caller))
    (asserts! (> sbtc-amount u0) ERR_INVALID_AMOUNT)
    (asserts! (> usdh-amount u0) ERR_INVALID_AMOUNT)
    (let (
      ;; Step 1: Deposit sBTC to vault and get z-tokens
      (z-tokens-received (try! (contract-call? .zest-interface-v0-2 zest-deposit vault-trait z-token-trait sbtc-token-trait sbtc-amount min-shares price-feed-1 price-feed-2))))
      
      ;; Step 1b: Add z-tokens as collateral to Zest market
      (try! (contract-call? .zest-interface-v0-2 zest-collateral-add market-trait z-token-trait z-tokens-received price-feed-1 price-feed-2))

      ;; Step 2: Borrow USDh and stake it in Hermetica
      (try! (zest-open market-trait staking-trait usdh-token-trait usdh-amount price-feed-1 price-feed-2))

      (print { action: "zest-open-add-deposit", user: contract-caller, data: { sbtc-amount: sbtc-amount, usdh-amount: usdh-amount } })
      (ok true)
    )
  )
)

;;-------------------------------------
;; Close Position - Vault Paths
;;-------------------------------------

;; @desc - Closes a leveraged position using vault path
;; @note - Removes z-tokens from collateral, redeems them for sBTC from vault
;; @param - market-trait: Zest v2 market contract
;; @param - vault-trait: Zest v2 vault contract
;; @param - staking-trait: Hermetica staking contract
;; @param - staking-silo-trait: Hermetica silo for withdrawal claims
;; @param - hbtc-vault-trait: Vault for sBTC collateral claims
;; @param - sbtc-token-trait: sBTC token contract
;; @param - z-token-trait: Z-token from vault
;; @param - usdh-token-trait: USDh token contract
;; @param - susdh-amount: Amount of sUSDh to unstake from Hermetica
;; @param - collateral-amount: Amount of z-token collateral to remove
;; @param - min-sbtc-amount: Minimum sBTC to receive from vault withdrawal
;; @param - claim-ids: List of claim IDs to fund with sBTC after all operations complete
;; @param - price-feed-1: Pyth price feed data for sBTC
;; @param - price-feed-2: Secondary price feed data
(define-public (zest-close-remove-redeem
  (market-trait <zest-market>) (vault-trait <zest-vault>) (staking-trait <staking>) (staking-silo-trait <staking-silo>) (hbtc-vault-trait <hbtc-vault>)
  (sbtc-token-trait <ft>) (z-token-trait <ft>) (usdh-token-trait <ft>)
  (susdh-amount uint) (collateral-amount uint) (min-sbtc-amount uint)
  (claim-ids (list 100 uint))
  (price-feed-1 (optional (buff 8192))) (price-feed-2 (optional (buff 8192))))
  (begin
    (try! (contract-call? .hq-hbtc-v1 check-is-trader contract-caller))
    (asserts! (> susdh-amount u0) ERR_INVALID_AMOUNT)
    (asserts! (> collateral-amount u0) ERR_INVALID_AMOUNT)

    ;; Step 1: Unstake sUSDh and repay USDh loan
    (try! (zest-close market-trait staking-trait staking-silo-trait usdh-token-trait susdh-amount price-feed-1 price-feed-2))

    ;; Step 2: Remove z-token collateral
    (try! (contract-call? .zest-interface-v0-2 zest-collateral-remove market-trait z-token-trait collateral-amount price-feed-1 price-feed-2))
    
    ;; Step 3: Redeem sBTC from vault (burn z-tokens, get actual sBTC amount)
    (try! (contract-call? .zest-interface-v0-2 zest-redeem vault-trait z-token-trait sbtc-token-trait collateral-amount min-sbtc-amount price-feed-1 price-feed-2))
    
    ;; Step 4: Optional - Fund claims with sBTC now in reserve
    (if (> (len claim-ids) u0)
      (begin
        (try! (contract-call? .hq-hbtc-v1 check-is-protocol (contract-of hbtc-vault-trait)))
        (try! (contract-call? hbtc-vault-trait fund-claim-many claim-ids))
      )
      true)

    (print { action: "zest-close-remove-redeem", user: contract-caller, data: { susdh-amount: susdh-amount, collateral-amount: collateral-amount, claim-ids: claim-ids } })
    (ok true)
  )
)