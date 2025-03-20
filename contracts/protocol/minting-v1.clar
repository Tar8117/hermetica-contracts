;; @contract Minting
;; @version 0.1

(use-trait sip-010-trait .sip-010-trait.sip-010-trait)
(use-trait pyth-storage-trait 'SP2T5JKWWP3FYYX4YRK8GK5BG2YCNGEAEY2P2PKN0.pyth-traits-v1.storage-trait)
(use-trait pyth-decoder-trait 'SP2T5JKWWP3FYYX4YRK8GK5BG2YCNGEAEY2P2PKN0.pyth-traits-v1.decoder-trait)
(use-trait wormhole-core-trait 'SP2T5JKWWP3FYYX4YRK8GK5BG2YCNGEAEY2P2PKN0.wormhole-traits-v1.core-trait)

;;-------------------------------------
;; Constants 
;;-------------------------------------

(define-constant ERR_NO_REQUEST_FOR_ID (err u2201))
(define-constant ERR_NOT_ALLOWED (err u2202))
(define-constant ERR_TRADING_DISABLED (err u2203))
(define-constant ERR_CONFIRMATION_OPEN (err u2204))
(define-constant ERR_AMOUNT_MISMATCH (err u2205))
(define-constant ERR_SLIPPAGE_TOO_HIGH (err u2206))
(define-constant ERR_NOT_CUSTODY_ADDRESS (err u2207))
(define-constant ERR_NOT_SUPPORTED_ASSET (err u2208))
(define-constant ERR_ASSET_MISMATCH (err u2209))
(define-constant ERR_PRICE_FEED_MISMATCH (err u2210))
(define-constant ERR_STALE_DATA (err u2211))
(define-constant ERR_PRICE_OUT_OF_RANGE (err u2212))
(define-constant ERR_MINT_LIMIT_EXCEEDED (err u2213))
(define-constant ERR_ABOVE_MAX (err u2214))
(define-constant ERR_BELOW_MIN (err u2215))

(define-constant minting-contract (as-contract tx-sender))
(define-constant bps-base (pow u10 u4))
(define-constant oracle-base (pow u10 u8))
(define-constant usdh-base (pow u10 u8))
(define-constant max-price-deviation u500)                        ;; bps (5%)

(define-constant max-mint-limit (* u250000 usdh-base))
(define-constant min-mint-limit-reset-window u3600)

;;-------------------------------------
;; Variables
;;-------------------------------------

(define-data-var current-mint-id uint u0)
(define-data-var current-redeem-id uint u0)

(define-data-var last-oracle-timestamp uint u0)                   ;; timestamp (in s) to prevent using stale prices

(define-data-var mint-limit uint (* u100000 usdh-base))           ;; usdh
(define-data-var current-mint-limit uint (* u100000 usdh-base))   ;; usdh
(define-data-var mint-limit-reset-window uint u3600)              ;; 1 hour in seconds
(define-data-var last-mint-limit-reset uint u0)                   ;; timestamp (in s)
(define-data-var timestamper principal tx-sender)                 ;; update last-mint-reset-reset

;;-------------------------------------
;; Maps 
;;-------------------------------------

(define-map traders
  { 
    address: principal 
  }
  {
    minter: bool,
    redeemer: bool
  }
)

(define-map mint-requests
  { 
    request-id: uint 
  }
  {
    requester: principal,
    minting-asset: principal,
    amount-asset: uint,           ;; BTC; token-base
    price: uint,                  ;; BTCUSD; oracle-base
    slippage: uint,               ;; bps
    block-height: uint,           ;; burn-block-height
  }
)

(define-map redeem-requests
  { 
    request-id: uint 
  }
  {
    requester: principal,
    redeeming-asset: principal,
    amount-usdh: uint,            ;; USDh; usdh-base
    price: uint,                  ;; BTCUSD; oracle-base
    slippage: uint,               ;; bps
    block-height: uint,           ;; burn-block-height
  }
)

(define-map custody-addresses
  { 
    address: principal 
  }
  {
    active: bool
  }
)

(define-map supported-assets
  { 
    contract: principal 
  }
  {
    active: bool,
    price-feed-id: (buff 32),
    token-base: uint
  }
)

;;-------------------------------------
;; Getters 
;;-------------------------------------

(define-read-only (get-current-mint-id) 
  (var-get current-mint-id)
)

(define-read-only (get-current-redeem-id) 
  (var-get current-redeem-id)
)

(define-read-only (get-last-oracle-timestamp) 
  (var-get last-oracle-timestamp)
)

(define-read-only (get-mint-limit) 
  (var-get mint-limit)
)

(define-read-only (get-current-mint-limit) 
  (var-get current-mint-limit)
)

(define-read-only (get-mint-limit-reset-window) 
  (var-get mint-limit-reset-window)
)

(define-read-only (get-last-mint-limit-reset) 
  (var-get last-mint-limit-reset)
)

(define-read-only (get-timestamper) 
  (var-get timestamper)
)

(define-read-only (get-trader (address principal))
  (default-to 
    { minter: false, redeemer: false }
    (map-get? traders { address: address })
  )
)

(define-read-only (get-mint-request (request-id uint))
  (ok (unwrap! (map-get? mint-requests { request-id: request-id }) ERR_NO_REQUEST_FOR_ID))
) 

(define-read-only (get-redeem-request (request-id uint))
  (ok (unwrap! (map-get? redeem-requests { request-id: request-id }) ERR_NO_REQUEST_FOR_ID))
) 

(define-read-only (get-custody-address-active (address principal)) 
  (get active 
    (default-to 
      { active: false }
      (map-get? custody-addresses { address: address })
    )
  )
)

(define-read-only (get-supported-asset (contract principal))
  (ok (unwrap! (map-get? supported-assets { contract: contract }) ERR_NOT_SUPPORTED_ASSET))
)

;;-------------------------------------
;; Checks
;;-------------------------------------

(define-read-only (check-is-supported-asset (contract principal))
  (get active 
    (default-to 
      { active: false }
      (map-get? supported-assets { contract: contract })
    )
  )
)

;;-------------------------------------
;; User  
;;-------------------------------------

(define-public (request-mint 
  (minting-asset <sip-010-trait>)
  (amount-asset uint)
  (price uint)
  (slippage uint)
  (price-feed-bytes (buff 8192))
  (execution-plan {
    pyth-storage-contract: <pyth-storage-trait>,
    pyth-decoder-contract: <pyth-decoder-trait>,
    wormhole-core-contract: <wormhole-core-trait>
  }))
  (let (
    (next-mint-id (+ (get-current-mint-id) u1))
    (minting-asset-contract (contract-of minting-asset))
    (token-base (get token-base (try! (get-supported-asset minting-asset-contract))))
    (amount-usdh-requested (/ (* amount-asset price usdh-base) oracle-base token-base))
    (decoded-price (element-at (try! (contract-call? 'SP2T5JKWWP3FYYX4YRK8GK5BG2YCNGEAEY2P2PKN0.pyth-oracle-v2 decode-price-feeds price-feed-bytes execution-plan)) u0))
    (oracle-price (to-uint (unwrap-panic (get price decoded-price))))
    (timestamp (unwrap-panic (get publish-time decoded-price)))
    (oracle-price-feed-id (unwrap-panic (get price-identifier decoded-price)))
    (max-price (+ oracle-price (/ (* oracle-price max-price-deviation) bps-base)))
    (min-price (- oracle-price (/ (* oracle-price max-price-deviation) bps-base)))
  )
    (try! (contract-call? .hq check-is-enabled))
    (asserts! (contract-call? .minting-state get-mint-enabled) ERR_TRADING_DISABLED)
    (try! (contract-call? .minting-state check-is-minter tx-sender))
    (asserts! (check-is-supported-asset minting-asset-contract) ERR_NOT_SUPPORTED_ASSET)
    (if (>= timestamp (+ (get-last-mint-limit-reset) (get-mint-limit-reset-window)))
      (begin
        (var-set current-mint-limit (get-mint-limit))
        (var-set last-mint-limit-reset timestamp) 
      )
      true
    )
    (asserts! (<= amount-usdh-requested (get-current-mint-limit)) ERR_MINT_LIMIT_EXCEEDED)
    (asserts! (> timestamp (get-last-oracle-timestamp)) ERR_STALE_DATA)
    (asserts! (is-eq oracle-price-feed-id (get price-feed-id (try! (get-supported-asset minting-asset-contract)))) ERR_PRICE_FEED_MISMATCH)
    (asserts! (and (> price min-price) (< price max-price)) ERR_PRICE_OUT_OF_RANGE)
    (asserts! (>= amount-usdh-requested (contract-call? .minting-state get-min-amount-usdh-requested)) ERR_BELOW_MIN)
    (asserts! (<= slippage bps-base) ERR_ABOVE_MAX)
    
    (try! (contract-call? minting-asset transfer amount-asset tx-sender minting-contract none))
    
    (map-set mint-requests { request-id: next-mint-id } 
      {   
        requester: tx-sender,
        minting-asset: minting-asset-contract,
        amount-asset: amount-asset,                     ;; BTC; token-base
        price: price,                                   ;; BTCUSD; oracle-base
        slippage: slippage,                             ;; bps
        block-height: burn-block-height,
      }
    )
    (print { request-id: next-mint-id, requester: tx-sender, minting-asset: minting-asset-contract, amount-asset: amount-asset, price: price, amount-usdh-requested: amount-usdh-requested, slippage: slippage, block-height: burn-block-height })
    (var-set current-mint-id next-mint-id)
    (var-set last-oracle-timestamp timestamp)
    (var-set current-mint-limit (- (get-current-mint-limit) amount-usdh-requested))
    (ok true)
  )
)

(define-public (claim-unconfirmed-mint-many (entries (list 1000 { request-id: uint, minting-asset: <sip-010-trait> })))
  (ok (map claim-unconfirmed-mint entries)))

(define-public (claim-unconfirmed-mint (entry { request-id: uint, minting-asset: <sip-010-trait> }))
  (let (
    (mint-request (try! (get-mint-request (get request-id entry))))
    (minting-asset-entry (get minting-asset entry))
  )
    (asserts! (> burn-block-height (+ (get block-height mint-request) (contract-call? .minting-state get-mint-confirmation-window))) ERR_CONFIRMATION_OPEN)
    (asserts! (is-eq (get minting-asset mint-request) (contract-of minting-asset-entry)) ERR_ASSET_MISMATCH)
    
    (try! (as-contract (contract-call? minting-asset-entry transfer (get amount-asset mint-request) tx-sender (get requester mint-request) none)))
    (map-delete mint-requests { request-id: (get request-id entry)})
    (ok true)
  )
)

(define-public (request-redeem 
  (redeeming-asset <sip-010-trait>) 
  (amount-usdh uint) 
  (price uint) 
  (slippage uint)
  (price-feed-bytes (buff 8192))
  (execution-plan {
    pyth-storage-contract: <pyth-storage-trait>,
    pyth-decoder-contract: <pyth-decoder-trait>,
    wormhole-core-contract: <wormhole-core-trait>
  }))
  (let (
    (next-redeem-id (+ (get-current-redeem-id) u1))
    (redeeming-asset-contract (contract-of redeeming-asset))
    (token-base (get token-base (try! (get-supported-asset redeeming-asset-contract))))
    (amount-asset-requested (/ (* amount-usdh oracle-base token-base) price usdh-base))
    (decoded-price (element-at (try! (contract-call? 'SP2T5JKWWP3FYYX4YRK8GK5BG2YCNGEAEY2P2PKN0.pyth-oracle-v2 decode-price-feeds price-feed-bytes execution-plan)) u0))
    (oracle-price (to-uint (unwrap-panic (get price decoded-price))))
    (timestamp (unwrap-panic (get publish-time decoded-price)))
    (oracle-price-feed-id (unwrap-panic (get price-identifier decoded-price)))
    (max-price (+ oracle-price (/ (* oracle-price max-price-deviation) bps-base)))
    (min-price (- oracle-price (/ (* oracle-price max-price-deviation) bps-base)))
  )
    (try! (contract-call? .hq check-is-enabled))
    (asserts! (contract-call? .minting-state get-redeem-enabled) ERR_TRADING_DISABLED)
    (try! (contract-call? .minting-state check-is-redeemer tx-sender))
    (asserts! (check-is-supported-asset redeeming-asset-contract) ERR_NOT_SUPPORTED_ASSET)
    (asserts! (> timestamp (var-get last-oracle-timestamp)) ERR_STALE_DATA)
    (asserts! (is-eq oracle-price-feed-id (get price-feed-id (try! (get-supported-asset redeeming-asset-contract)))) ERR_PRICE_FEED_MISMATCH)
    (asserts! (and (> price min-price) (< price max-price)) ERR_PRICE_OUT_OF_RANGE)
    (asserts! (>= amount-usdh (contract-call? .minting-state get-min-amount-usdh-requested)) ERR_BELOW_MIN)
    (asserts! (<= slippage bps-base) ERR_ABOVE_MAX)
    
    (try! (contract-call? .usdh-token transfer amount-usdh tx-sender minting-contract none))
    
    (map-set redeem-requests { request-id: next-redeem-id } 
      {   
        requester: tx-sender,
        redeeming-asset: redeeming-asset-contract,
        amount-usdh: amount-usdh,                       ;; USDh; usdh-base
        price: price,                                   ;; BTCUSD; oracle-base
        slippage: slippage,                             ;; bps
        block-height: burn-block-height,
      }
    )
    (print { request-id: next-redeem-id, requester: tx-sender, redeeming-asset: redeeming-asset-contract, amount-asset-requested: amount-asset-requested, amount-usdh: amount-usdh, price: price,  slippage: slippage, block-height: burn-block-height })
    (var-set current-redeem-id next-redeem-id)
    (var-set last-oracle-timestamp timestamp)
    (ok true)
  )
)

(define-public (claim-unconfirmed-redeem-many (entries (list 1000 uint)))
  (ok (map claim-unconfirmed-redeem entries)))

(define-public (claim-unconfirmed-redeem (redeem-id uint))
  (let (
    (redeem-request (try! (get-redeem-request redeem-id)))
  )
    (asserts! (> burn-block-height (+ (get block-height redeem-request) (contract-call? .minting-state get-redeem-confirmation-window))) ERR_CONFIRMATION_OPEN)
    
    (try! (as-contract (contract-call? .usdh-token transfer (get amount-usdh redeem-request) tx-sender (get requester redeem-request) none)))
    (map-delete redeem-requests { request-id: redeem-id })
    (ok true)
  )
)

;;-------------------------------------
;; Trader
;;-------------------------------------

(define-public (confirm-mint (request-id uint) (price uint) (amount-asset uint) (minting-asset <sip-010-trait>) (custody-address principal) (memo (optional (buff 34))))
  (let (
    (mint-request (try! (get-mint-request request-id)))
    (price-requested (get price mint-request))
    (minting-asset-contract (get minting-asset mint-request))
    (slippage-tolerance (/ (* price-requested (get slippage mint-request)) bps-base))
    (token-base (get token-base (try! (get-supported-asset (contract-of minting-asset)))))
    (amount-asset-fee (/ (* amount-asset (contract-call? .minting-state get-mint-fee-asset)) bps-base))
    (amount-usdh (/ (* (- amount-asset amount-asset-fee) price usdh-base) oracle-base token-base))
    (amount-usdh-fee (/ (* amount-usdh (contract-call? .minting-state get-mint-fee-usdh)) bps-base))
    (amount-usdh-confirmed (- amount-usdh amount-usdh-fee))
  )
    (try! (contract-call? .hq check-is-enabled))
    (asserts! (contract-call? .minting-state get-mint-enabled) ERR_TRADING_DISABLED)
    (asserts! (get minter (get-trader tx-sender)) ERR_NOT_ALLOWED)
    (asserts! (get-custody-address-active custody-address) ERR_NOT_CUSTODY_ADDRESS)
    (asserts! (check-is-supported-asset minting-asset-contract) ERR_NOT_SUPPORTED_ASSET)
    (asserts! (is-eq minting-asset-contract (contract-of minting-asset)) ERR_ASSET_MISMATCH)
    (asserts! (is-eq amount-asset (get amount-asset mint-request)) ERR_AMOUNT_MISMATCH)
    (asserts! (>= price (- price-requested slippage-tolerance)) ERR_SLIPPAGE_TOO_HIGH)

    (try! (contract-call? .usdh-token mint-for-protocol amount-usdh-confirmed (get requester mint-request)))
    (if (> amount-usdh-fee u0) (try! (contract-call? .usdh-token mint-for-protocol amount-usdh-fee (contract-call? .minting-state get-fee-address))) true)
    (try! (as-contract (contract-call? minting-asset transfer (- amount-asset amount-asset-fee) tx-sender custody-address memo)))
    (if (> amount-asset-fee u0) (try! (as-contract (contract-call? minting-asset transfer amount-asset-fee tx-sender (contract-call? .minting-state get-fee-address) memo))) true)

    (map-delete mint-requests { request-id: request-id })
    (print { request-id: request-id, price: price, amount-usdh-confirmed: amount-usdh-confirmed, minting-asset: minting-asset-contract })
    (ok true)
  )
)

(define-public (cancel-mint-request-many (entries (list 1000 { request-id: uint, minting-asset: <sip-010-trait> })))
  (ok (map cancel-mint-request entries)))

(define-public (cancel-mint-request (entry { request-id: uint, minting-asset: <sip-010-trait> }))
  (let (
    (mint-request (try! (get-mint-request (get request-id entry))))
    (minting-asset-entry (get minting-asset entry))
    (token-base (get token-base (try! (get-supported-asset (contract-of minting-asset-entry)))))
    (price (get price mint-request))
    (amount-asset (get amount-asset mint-request))
    (amount-usdh-requested (/ (* amount-asset price usdh-base) oracle-base token-base))
    (new-mint-limit (+ (get-current-mint-limit) amount-usdh-requested))
  )
    (try! (contract-call? .hq check-is-enabled))
    (asserts! (contract-call? .minting-state get-mint-enabled) ERR_TRADING_DISABLED)
    (asserts! (get minter (get-trader tx-sender)) ERR_NOT_ALLOWED)
    (asserts! (is-eq (get minting-asset mint-request) (contract-of minting-asset-entry)) ERR_ASSET_MISMATCH)

    (try! (as-contract (contract-call? minting-asset-entry transfer amount-asset tx-sender (get requester mint-request) none)))
    (map-delete mint-requests { request-id: (get request-id entry) })
    (if (<= new-mint-limit (get-mint-limit)) (var-set current-mint-limit new-mint-limit) (var-set current-mint-limit (get-mint-limit)))
    (ok true)
  )
)

(define-public (confirm-redeem (request-id uint) (price uint) (amount-usdh uint) (redeeming-asset <sip-010-trait>))
  (let (
    (redeem-request (try! (get-redeem-request request-id)))
    (price-requested (get price redeem-request))
    (redeeming-asset-contract (get redeeming-asset redeem-request))
    (slippage-tolerance (/ (* price-requested (get slippage redeem-request)) bps-base))
    (token-base (get token-base (try! (get-supported-asset (contract-of redeeming-asset)))))
    (amount-usdh-fee (/ (* amount-usdh (contract-call? .minting-state get-redeem-fee-usdh)) bps-base))
    (amount-asset (/ (* (- amount-usdh amount-usdh-fee) oracle-base token-base) price usdh-base))
    (amount-asset-fee (/ (* amount-asset (contract-call? .minting-state get-redeem-fee-asset)) bps-base))
    (amount-asset-confirmed (- amount-asset amount-asset-fee))
  )
    (try! (contract-call? .hq check-is-enabled))
    (asserts! (contract-call? .minting-state get-redeem-enabled) ERR_TRADING_DISABLED)
    (asserts! (get redeemer (get-trader tx-sender)) ERR_NOT_ALLOWED)
    (asserts! (check-is-supported-asset redeeming-asset-contract) ERR_NOT_SUPPORTED_ASSET)
    (asserts! (is-eq redeeming-asset-contract (contract-of redeeming-asset)) ERR_ASSET_MISMATCH)
    (asserts! (is-eq amount-usdh (get amount-usdh redeem-request)) ERR_AMOUNT_MISMATCH)
    (asserts! (<= price (+ price-requested slippage-tolerance)) ERR_SLIPPAGE_TOO_HIGH)

    (try! (contract-call? .redeeming-reserve transfer amount-asset-confirmed (get requester redeem-request) redeeming-asset))
    (if (> amount-asset-fee u0) (try! (contract-call? .redeeming-reserve transfer amount-asset-fee (contract-call? .minting-state get-fee-address) redeeming-asset)) true)
    (try! (as-contract (contract-call? .usdh-token burn-for-protocol (- amount-usdh amount-usdh-fee) tx-sender)))
    (if (> amount-usdh-fee u0) (try! (as-contract (contract-call? .usdh-token transfer amount-usdh-fee tx-sender (contract-call? .minting-state get-fee-address) none))) true)

    (map-delete redeem-requests { request-id: request-id })
    (print { request-id: request-id, price: price, amount-asset-confirmed: amount-asset-confirmed, redeeming-asset: redeeming-asset-contract })
    (ok true)
  )
)

(define-public (cancel-redeem-request-many (entries (list 1000 uint)))
  (ok (map cancel-redeem-request entries)))

(define-public (cancel-redeem-request (request-id uint))
  (let (
    (redeem-request (try! (get-redeem-request request-id)))
  )
    (try! (contract-call? .hq check-is-enabled))
    (asserts! (contract-call? .minting-state get-redeem-enabled) ERR_TRADING_DISABLED)
    (asserts! (get redeemer (get-trader tx-sender)) ERR_NOT_ALLOWED)

    (try! (as-contract (contract-call? .usdh-token transfer (get amount-usdh redeem-request) tx-sender (get requester redeem-request) none)))
    (map-delete redeem-requests { request-id: request-id })
    (ok true)
  )
)

;;-------------------------------------
;; Admin
;;-------------------------------------

(define-public (set-mint-limit (new-mint-limit uint))
  (begin
    (try! (contract-call? .hq check-is-protocol tx-sender))
    (asserts! (<= new-mint-limit max-mint-limit) ERR_ABOVE_MAX)
    (ok (var-set mint-limit new-mint-limit)))
)

(define-public (set-mint-limit-reset-window (new-window uint))
  (begin
    (try! (contract-call? .hq check-is-protocol tx-sender))
    (asserts! (>= new-window min-mint-limit-reset-window) ERR_BELOW_MIN)
    (ok (var-set mint-limit-reset-window new-window)))
)

(define-public (set-mint-commission-usdh (new-mint-commission-usdh uint))
  (begin
    (try! (contract-call? .hq check-is-protocol tx-sender))
    (asserts! (<= new-mint-commission-usdh max-commission) ERR_ABOVE_MAX)
    (ok (var-set mint-commission-usdh new-mint-commission-usdh)))
)

(define-public (set-redeem-commission-usdh (new-redeem-commission-usdh uint))
  (begin
    (try! (contract-call? .hq check-is-protocol tx-sender))
    (asserts! (<= new-redeem-commission-usdh max-commission) ERR_ABOVE_MAX)
    (ok (var-set redeem-commission-usdh new-redeem-commission-usdh)))
)

(define-public (set-mint-commission-asset (new-mint-commission-asset uint))
  (begin
    (try! (contract-call? .hq check-is-protocol tx-sender))
    (asserts! (<= new-mint-commission-asset max-commission) ERR_ABOVE_MAX)
    (ok (var-set mint-commission-asset new-mint-commission-asset)))
)

(define-public (set-redeem-commission-asset (new-redeem-commission-asset uint))
  (begin
    (try! (contract-call? .hq check-is-protocol tx-sender))
    (asserts! (<= new-redeem-commission-asset max-commission) ERR_ABOVE_MAX)
    (ok (var-set redeem-commission-asset new-redeem-commission-asset)))
)

(define-public (set-min-amount-usdh-requested (new-min-amount-usdh-requested uint))
  (begin
    (try! (contract-call? .hq check-is-protocol tx-sender))
    (ok (var-set min-amount-usdh-requested new-min-amount-usdh-requested))
  )
)

(define-public (set-trader (address principal) (mint bool) (redeem bool))
  (begin
    (try! (contract-call? .hq check-is-protocol tx-sender))
    (map-set traders { address: address } { minter: mint, redeemer: redeem})
    (ok true)
  )
)

(define-public (set-custody-address (custody-address principal) (active bool))
  (begin
    (try! (contract-call? .hq check-is-protocol tx-sender))
    (map-set custody-addresses {address: custody-address} {active: active})
    (ok true)
  )
)

(define-public (set-supported-asset (address principal) (active bool) (price-feed-id (buff 32)) (token-base uint))
  (begin
    (try! (contract-call? .hq check-is-protocol tx-sender))
    (ok (map-set supported-assets { contract: address } { active: active, price-feed-id: price-feed-id, token-base: token-base }))
  )
)

;;-------------------------------------
;; Timestamper  
;;-------------------------------------

(define-public (reset-mint-window
  (price-feed-bytes (buff 8192))
  (execution-plan {
    pyth-storage-contract: <pyth-storage-trait>,
    pyth-decoder-contract: <pyth-decoder-trait>,
    wormhole-core-contract: <wormhole-core-trait>
  }))
  (let (
    (decoded-price (element-at (try! (contract-call? 'SP2T5JKWWP3FYYX4YRK8GK5BG2YCNGEAEY2P2PKN0.pyth-oracle-v2 decode-price-feeds price-feed-bytes execution-plan)) u0))
    (timestamp (unwrap-panic (get publish-time decoded-price)))
  )
    (asserts! (is-eq tx-sender (var-get timestamper)) ERR_NOT_ALLOWED)
    (asserts! (> timestamp (var-get last-oracle-timestamp)) ERR_STALE_DATA)
    (var-set last-mint-limit-reset timestamp)
    (var-set last-oracle-timestamp timestamp)
    (ok true)
  )
)