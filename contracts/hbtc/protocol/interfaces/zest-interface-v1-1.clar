;; @contract Zest Interface v2
;; @version 1.1
;; @desc Interface for Zest v2 lending protocol integration

(use-trait ft 'SP2VCQJGH7PHP2DJK7Z0V48AGBHQAW3R3ZW1QF4N.ft-trait.ft-trait)
(use-trait zest-market .zest-market-trait-v1.zest-market-trait)
(use-trait zest-vault .zest-vault-trait-v1.zest-vault-trait)

(define-constant ERR_INVALID_AMOUNT (err u111001))
(define-constant ERR_INSUFFICIENT_BALANCE (err u111002))

(define-constant this-contract (as-contract tx-sender))
(define-constant reserve .reserve-v1)


;;-------------------------------------
;; Trader - Collateral Management
;;-------------------------------------

;; @desc - Adds collateral to Zest v2 market
;; @param - market-trait: Zest v2 market contract
;; @param - asset-trait: Token to supply as collateral
;; @param - amount: Amount of tokens to supply
;; @param - price-feed-1: Optional Pyth price feed data for sBTC
;; @param - price-feed-2: Optional Pyth price feed data (secondary)
(define-public (zest-collateral-add
  (market-trait <zest-market>)
  (asset-trait <ft>)
  (amount uint)
  (price-feed-1 (optional (buff 8192)))
  (price-feed-2 (optional (buff 8192))))
  (begin
    (try! (contract-call? .hq-hbtc-v1 check-is-trader contract-caller))
    (try! (contract-call? .state-v1 check-trading-auth (contract-of market-trait) none (some (contract-of asset-trait)) none))
    (asserts! (> amount u0) ERR_INVALID_AMOUNT)
    
    ;; Update Pyth price feed for sBTC before operation (DIA handles USDh)
    (try! (write-feed price-feed-1))
    (try! (write-feed price-feed-2))
    
    ;; Transfer tokens from reserve to this interface
    (try! (contract-call? .reserve-v1 transfer asset-trait amount this-contract))
    
    ;; Add collateral to Zest market (position owned by this interface contract)
    (try! (as-contract (contract-call? market-trait collateral-add asset-trait amount this-contract)))
    
    (print { action: "zest-collateral-add", user: contract-caller, data: { market: market-trait, asset: asset-trait, amount: amount } })
    (ok true)
  )
)

;; @desc - Removes collateral from Zest v2 market
;; @param - market-trait: Zest v2 market contract
;; @param - asset-trait: Token to remove from collateral
;; @param - amount: Amount of tokens to remove
;; @param - price-feed-1: Optional Pyth price feed data for sBTC
;; @param - price-feed-2: Optional Pyth price feed data (secondary)
(define-public (zest-collateral-remove
  (market-trait <zest-market>)
  (asset-trait <ft>)
  (amount uint)
  (price-feed-1 (optional (buff 8192)))
  (price-feed-2 (optional (buff 8192))))
  (begin
    (try! (contract-call? .hq-hbtc-v1 check-is-trader contract-caller))
    (try! (contract-call? .state-v1 check-trading-auth (contract-of market-trait) none (some (contract-of asset-trait)) none))
    (asserts! (> amount u0) ERR_INVALID_AMOUNT)
    
    ;; Update Pyth price feed for sBTC before operation (DIA handles USDh)
    (try! (write-feed price-feed-1))
    (try! (write-feed price-feed-2))
    
    ;; Remove collateral from Zest market
    (try! (as-contract (contract-call? market-trait collateral-remove asset-trait amount this-contract)))
    
    ;; Transfer tokens back to reserve
    (try! (as-contract (contract-call? asset-trait transfer amount this-contract .reserve-v1 none)))
    
    (print { action: "zest-collateral-remove", user: contract-caller, data: { market: market-trait, asset: asset-trait, amount: amount } })
    (ok true)
  )
)

;;-------------------------------------
;; Trader - Borrowing
;;-------------------------------------

;; @desc - Borrows assets from Zest v2 market
;; @param - market-trait: Zest v2 market contract
;; @param - asset-trait: Token to borrow
;; @param - amount: Amount of tokens to borrow
;; @param - price-feed-1: Optional Pyth price feed data for sBTC
;; @param - price-feed-2: Optional Pyth price feed data (secondary)
(define-public (zest-borrow
  (market-trait <zest-market>)
  (asset-trait <ft>)
  (amount uint)
  (price-feed-1 (optional (buff 8192)))
  (price-feed-2 (optional (buff 8192))))
  (begin
    (try! (contract-call? .hq-hbtc-v1 check-is-trader contract-caller))
    (try! (contract-call? .state-v1 check-trading-auth (contract-of market-trait) none (some (contract-of asset-trait)) none))
    (asserts! (> amount u0) ERR_INVALID_AMOUNT)
    
    ;; Update Pyth price feed for sBTC before operation (DIA handles USDh)
    (try! (write-feed price-feed-1))
    (try! (write-feed price-feed-2))
    
    ;; Borrow from Zest market (debt recorded under this interface contract)
    (try! (as-contract (contract-call? market-trait borrow asset-trait amount this-contract)))
    
    ;; Transfer borrowed tokens to reserve
    (try! (as-contract (contract-call? asset-trait transfer amount this-contract .reserve-v1 none)))
    
    (print { action: "zest-borrow", user: contract-caller, data: { market: market-trait, asset: asset-trait, amount: amount } })
    (ok true)
  )
)

;; @desc - Repays borrowed assets to Zest v2 market
;; @param - market-trait: Zest v2 market contract
;; @param - asset-trait: Token to repay
;; @param - amount: Amount of tokens to repay
;; @param - price-feed-1: Optional Pyth price feed data for sBTC
;; @param - price-feed-2: Optional Pyth price feed data (secondary)
(define-public (zest-repay
  (market-trait <zest-market>)
  (asset-trait <ft>)
  (amount uint)
  (price-feed-1 (optional (buff 8192)))
  (price-feed-2 (optional (buff 8192))))
  (begin
    (try! (contract-call? .hq-hbtc-v1 check-is-trader contract-caller))
    (try! (contract-call? .state-v1 check-trading-auth (contract-of market-trait) none (some (contract-of asset-trait)) none))
    (asserts! (> amount u0) ERR_INVALID_AMOUNT)
    
    ;; Update Pyth price feed for sBTC before operation (DIA handles USDh)
    (try! (write-feed price-feed-1))
    (try! (write-feed price-feed-2))
    
    ;; Transfer repayment from reserve to this interface
    (try! (contract-call? .reserve-v1 transfer asset-trait amount this-contract))
    
    ;; Repay to Zest market
    (try! (as-contract (contract-call? market-trait repay asset-trait amount this-contract)))
    
    (print { action: "zest-repay", user: contract-caller, data: { market: market-trait, asset: asset-trait, amount: amount } })
    (ok true)
  )
)

;;-------------------------------------
;; Liquidity Provider - Vault Management
;;-------------------------------------

;; @desc - Deposits assets to Zest v2 vault as liquidity provider
;; @param - vault-trait: Zest v2 vault contract
;; @param - z-token-trait: Z-token (vault shares) to receive
;; @param - asset-trait: Token to deposit to vault
;; @param - amount: Amount of tokens to deposit
;; @param - min-shares: Minimum vault shares to receive (slippage protection)
;; @param - price-feed-1: Optional Pyth price feed data for sBTC
;; @param - price-feed-2: Optional Pyth price feed data (secondary)
(define-public (zest-deposit
  (vault-trait <zest-vault>)
  (z-token-trait <ft>)
  (asset-trait <ft>)
  (amount uint)
  (min-shares uint)
  (price-feed-1 (optional (buff 8192)))
  (price-feed-2 (optional (buff 8192))))
  (begin
    (try! (contract-call? .hq-hbtc-v1 check-is-trader contract-caller))
    (try! (contract-call? .state-v1 check-trading-auth (contract-of vault-trait) none (some (contract-of asset-trait)) none))
    (asserts! (> amount u0) ERR_INVALID_AMOUNT)
    
    ;; Update Pyth price feed for sBTC before operation (DIA handles USDh)
    (try! (write-feed price-feed-1))
    (try! (write-feed price-feed-2))
    
    ;; Transfer tokens from reserve to this interface
    (try! (contract-call? .reserve-v1 transfer asset-trait amount this-contract))
    
    ;; Deposit to Zest vault (z-tokens minted to this interface contract)
    (let (
      (received (try! (as-contract (contract-call? vault-trait deposit amount min-shares this-contract))))
    )
      ;; Transfer z-tokens (vault shares) to reserve
      (try! (as-contract (contract-call? z-token-trait transfer received this-contract .reserve-v1 none)))
      
      (print { action: "zest-deposit", user: contract-caller, data: { vault: vault-trait, asset: asset-trait, amount: amount, shares: received } })
      (ok received)
    )
  )
)

;; @desc - Redeems vault shares from Zest v2 vault
;; @param - vault-trait: Zest v2 vault contract
;; @param - z-token-trait: Z-token (vault shares) to redeem
;; @param - asset-trait: Token to receive from vault
;; @param - shares: Amount of vault shares to redeem
;; @param - min-amount: Minimum underlying tokens to receive (slippage protection)
;; @param - price-feed-1: Optional Pyth price feed data for sBTC
;; @param - price-feed-2: Optional Pyth price feed data (secondary)
(define-public (zest-redeem
  (vault-trait <zest-vault>)
  (z-token-trait <ft>)
  (asset-trait <ft>)
  (shares uint)
  (min-amount uint)
  (price-feed-1 (optional (buff 8192)))
  (price-feed-2 (optional (buff 8192))))
  (begin
    (try! (contract-call? .hq-hbtc-v1 check-is-trader contract-caller))
    (try! (contract-call? .state-v1 check-trading-auth (contract-of vault-trait) none (some (contract-of asset-trait)) none))
    (asserts! (> shares u0) ERR_INVALID_AMOUNT)
    
    ;; Update Pyth price feed for sBTC before operation (DIA handles USDh)
    (try! (write-feed price-feed-1))
    (try! (write-feed price-feed-2))
    
    ;; Transfer z-tokens from reserve to this interface
    (try! (contract-call? .reserve-v1 transfer z-token-trait shares this-contract))

    ;; Get actual amount received
    (let (
      ;; Redeem from Zest vault (burns z-tokens, receives underlying tokens)
      (received (try! (as-contract (contract-call? vault-trait redeem shares min-amount this-contract))))
    )
      ;; Transfer received tokens back to reserve
      (try! (as-contract (contract-call? asset-trait transfer received this-contract .reserve-v1 none)))
      
      (print { action: "zest-redeem", user: contract-caller, data: { vault: vault-trait, asset: asset-trait, shares: shares, amount: received } })
      (ok received)
    )
  )
)

;;-------------------------------------
;; Admin
;;-------------------------------------

;; @desc - sweeps any leftover tokens from interface contract to reserve
;; @param - asset-trait: the token to sweep
;; @param - amount: the amount to sweep
(define-public (sweep (asset-trait <ft>) (amount uint))
  (begin
    (try! (contract-call? .hq-hbtc-v1 check-is-trader contract-caller))
    (try! (contract-call? .state-v1 check-is-asset (contract-of asset-trait)))
    (asserts! (> amount u0) ERR_INVALID_AMOUNT)
    (asserts! (<= amount (unwrap-panic (contract-call? asset-trait get-balance this-contract))) ERR_INSUFFICIENT_BALANCE)
    (try! (as-contract (contract-call? asset-trait transfer amount this-contract reserve none)))
    (print { action: "sweep", user: contract-caller, data: { asset: asset-trait, amount: amount, sender: this-contract, recipient: reserve } })
    (ok amount)
  )
)

;;-------------------------------------
;; Helper
;;-------------------------------------

(define-private (write-feed (price-feed (optional (buff 8192))))
  (match price-feed bytes 
    (begin
      (try! (contract-call? 'SP1CGXWEAMG6P6FT04W66NVGJ7PQWMDAC19R7PJ0Y.pyth-oracle-v4 verify-and-update-price-feeds
        bytes
        {
          pyth-storage-contract: 'SP1CGXWEAMG6P6FT04W66NVGJ7PQWMDAC19R7PJ0Y.pyth-storage-v4,
          pyth-decoder-contract: 'SP1CGXWEAMG6P6FT04W66NVGJ7PQWMDAC19R7PJ0Y.pyth-pnau-decoder-v3,
          wormhole-core-contract: 'SP1CGXWEAMG6P6FT04W66NVGJ7PQWMDAC19R7PJ0Y.wormhole-core-v4,
        }
      ))
      (ok true)
    )
    ;; do nothing if none
    (ok true)
  )
)