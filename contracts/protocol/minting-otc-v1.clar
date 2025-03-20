;; @contract Minting OTC
;; @version 0.1

;;-------------------------------------
;; Constants 
;;-------------------------------------

(define-constant ERR_NO_REQUEST_FOR_ID (err u2101))
(define-constant ERR_BELOW_MIN (err u2102))
(define-constant ERR_NOT_ALLOWED (err u2103))
(define-constant ERR_TRADING_DISABLED (err u2104))
(define-constant ERR_CONFIRMATION_OPEN (err u2105))
(define-constant ERR_MINT_LIMIT_EXCEEDED (err u2106))
(define-constant ERR_AMOUNT_MISMATCH (err u2107))
(define-constant ERR_SLIPPAGE_TOO_HIGH (err u2108))
(define-constant ERR_ABOVE_MAX (err u2109))
(define-constant ERR_ALREADY_CONFIRMED (err u2110))

(define-constant minting-contract (as-contract tx-sender))
(define-constant max-confirmation-window u144)
(define-constant max-fee u200)                            ;; bps
(define-constant bps-base (pow u10 u4))
(define-constant usdh-base (pow u10 u8))
(define-constant oracle-base (pow u10 u8))

(define-constant max-mint-limit (* u250000 usdh-base))
(define-constant min-mint-limit-reset-window u6)

;;-------------------------------------
;; Variables
;;-------------------------------------

(define-data-var current-redeem-id uint u0)

(define-data-var mint-limit uint (* u100000 usdh-base))         ;; usdh
(define-data-var current-mint-limit uint (* u100000 usdh-base)) ;; usdh
(define-data-var mint-limit-reset-window uint u6)               ;; burn-block-height
(define-data-var last-mint-limit-reset uint burn-block-height)  ;; burn-block-height

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
    request-id: (string-ascii 36)
  } 
  { 
    confirmed: bool 
  }
)

(define-map redeem-requests
  { 
    request-id: uint 
  }
  {
    requester: principal,
    btc-address: (string-ascii 64),
    amount-usdh: uint,            ;; USDh; usdh-base
    price: uint,                  ;; BTCUSD; oracle-base
    slippage: uint,               ;; bps
    block-height: uint,           ;; burn-block-height
  }
)

;;-------------------------------------
;; Getters 
;;-------------------------------------

(define-read-only (get-current-redeem-id) 
  (var-get current-redeem-id)
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

(define-read-only (get-trader (address principal))
  (default-to 
    { minter: false, redeemer: false }
    (map-get? traders { address: address })
  )
)

(define-read-only (get-mint-request-confirmed (request-id (string-ascii 36))) 
  (default-to 
    false
    (get confirmed (map-get? mint-requests { request-id: request-id }))
  )
)

(define-read-only (get-redeem-request (request-id uint))
  (ok (unwrap! (map-get? redeem-requests { request-id: request-id }) ERR_NO_REQUEST_FOR_ID))
) 

;;-------------------------------------
;; User
;;-------------------------------------

(define-public (request-redeem (btc-address (string-ascii 64)) (amount-usdh uint) (price uint) (slippage uint))
  (let (
    (next-redeem-id (+ (get-current-redeem-id) u1))
  )
    (try! (contract-call? .hq check-is-enabled))
    (asserts! (contract-call? .minting-state get-redeem-enabled) ERR_TRADING_DISABLED)
    (try! (contract-call? .minting-state check-is-redeemer tx-sender))
    (asserts! (>= amount-usdh (contract-call? .minting-state get-min-amount-usdh-requested)) ERR_BELOW_MIN)
    (asserts! (<= slippage bps-base) ERR_ABOVE_MAX)

    (try! (contract-call? .usdh-token transfer amount-usdh tx-sender minting-contract none))

    (map-set redeem-requests { request-id: next-redeem-id } 
      {   
        requester: tx-sender,
        btc-address: btc-address,
        amount-usdh: amount-usdh,                       ;; USDh
        price: price,                                   ;; BTCUSD
        slippage: slippage,                             ;; bps
        block-height: burn-block-height,
      }
    )

    (print { request-id: next-redeem-id, requester: tx-sender, btc-address: btc-address, amount-usdh: amount-usdh, price: price, slippage: slippage, block-height: burn-block-height })
    (var-set current-redeem-id next-redeem-id)
    (ok true)
  )
)

(define-public (claim-unconfirmed-redeem (redeem-id uint))
  (let (
    (redeem-request (try! (get-redeem-request redeem-id)))
    (requester (get requester redeem-request))
  )
    (asserts! (is-eq requester tx-sender) ERR_NOT_ALLOWED)
    (asserts! (> burn-block-height (+ (get block-height redeem-request) (contract-call? .minting-state get-redeem-confirmation-window))) ERR_CONFIRMATION_OPEN)
    
    (try! (as-contract (contract-call? .usdh-token transfer (get amount-usdh redeem-request) tx-sender requester none)))
    (map-delete redeem-requests { request-id: redeem-id })
    (ok true)
  )
)

;;-------------------------------------
;; Trader
;;-------------------------------------

(define-public (confirm-mint (request-id (string-ascii 36)) (requester principal) (amount-asset uint) (price uint))
  (let (
    (amount-usdh (/ (* amount-asset price) oracle-base))
    (amount-usdh-fee (/ (* amount-usdh (contract-call? .minting-state get-mint-fee-usdh)) bps-base))
    (amount-usdh-confirmed (- amount-usdh amount-usdh-fee))
  )
    (try! (contract-call? .hq check-is-enabled))
    (try! (contract-call? .minting-state check-is-minter requester))
    (asserts! (contract-call? .minting-state get-mint-enabled) ERR_TRADING_DISABLED)
    (asserts! (get minter (get-trader tx-sender)) ERR_NOT_ALLOWED)
    (asserts! (not (get-mint-request-confirmed request-id)) ERR_ALREADY_CONFIRMED)

    (if (>= burn-block-height (+ (get-last-mint-limit-reset) (get-mint-limit-reset-window))) 
      (begin
        (var-set current-mint-limit (get-mint-limit))
        (var-set last-mint-limit-reset burn-block-height) 
      )
      true
    )
    (asserts! (<= amount-usdh (get-current-mint-limit)) ERR_MINT_LIMIT_EXCEEDED)

    (try! (contract-call? .usdh-token mint-for-protocol amount-usdh-confirmed requester))
    (if (> amount-usdh-fee u0) (try! (contract-call? .usdh-token mint-for-protocol amount-usdh-fee (contract-call? .minting-state get-fee-address))) true)

    (print { request-id: request-id, requester: requester, price: price, amount-usdh: amount-usdh, amount-usdh-confirmed: amount-usdh-confirmed, block-height: burn-block-height })
    (var-set current-mint-limit (- (get-current-mint-limit) amount-usdh))
    (map-insert mint-requests { request-id: request-id } { confirmed: true })
    (ok true)
  )
)

;; @desc - confirms a redeem request and burns USDh
;; @param - request-id: id of the redeem request
;; @param - price: price rate confirmed in BTCUSD (10**8, oracle-base)
;; @param - amount-usdh: USDh (10**8, usdh-base)
(define-public (confirm-redeem (request-id uint) (price  uint) (amount-usdh uint))
  (let (
    (redeem-request (try! (get-redeem-request request-id)))
    (price-requested (get price redeem-request))
    (slippage-tolerance (/ (* price-requested (get slippage redeem-request)) bps-base))
    (amount-usdh-fee (/ (* amount-usdh (contract-call? .minting-state get-redeem-fee-usdh)) bps-base))
    (amount-usdh-confirmed (- amount-usdh amount-usdh-fee))
    (amount-asset-confirmed (/ (* (/ (* amount-usdh-confirmed oracle-base) price) (- bps-base (contract-call? .minting-state get-redeem-fee-asset))) bps-base))
  )
    (try! (contract-call? .hq check-is-enabled))
    (asserts! (contract-call? .minting-state get-redeem-enabled) ERR_TRADING_DISABLED)
    (asserts! (get redeemer (get-trader tx-sender)) ERR_NOT_ALLOWED)
    (asserts! (is-eq amount-usdh (get amount-usdh redeem-request)) ERR_AMOUNT_MISMATCH)
    (asserts! (<= price (+ price-requested slippage-tolerance)) ERR_SLIPPAGE_TOO_HIGH)

    (print { request-id: request-id, price: price, amount-usdh: amount-usdh, amount-usdh-confirmed: amount-usdh-confirmed, amount-asset-confirmed: amount-asset-confirmed, btc-address: (get btc-address redeem-request) })
    (try! (as-contract (contract-call? .usdh-token burn-for-protocol amount-usdh-confirmed tx-sender)))
    (if (> amount-usdh-fee u0) (try! (as-contract (contract-call? .usdh-token transfer amount-usdh-fee tx-sender (contract-call? .minting-state get-fee-address) none))) true)

    (map-delete redeem-requests { request-id: request-id })
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
    (asserts! (contract-call? .minting-state  get-redeem-enabled) ERR_TRADING_DISABLED)
    (asserts! (get redeemer (get-trader tx-sender)) ERR_NOT_ALLOWED)

    (try! (as-contract (contract-call? .usdh-token transfer (get amount-usdh redeem-request) tx-sender (get requester redeem-request) none)))
    (map-delete redeem-requests { request-id: request-id })
    (ok true)
  )
)

;;-------------------------------------
;; Admin
;;-------------------------------------

(define-public (set-mint-limit (new-limit uint))
  (begin
    (try! (contract-call? .hq check-is-protocol tx-sender))
    (asserts! (<= new-limit max-mint-limit) ERR_ABOVE_MAX)
    (ok (var-set mint-limit new-limit)))
)

(define-public (set-mint-limit-reset-window (new-window uint))
  (begin
    (try! (contract-call? .hq check-is-protocol tx-sender))
    (asserts! (>= new-window min-mint-limit-reset-window) ERR_BELOW_MIN)
    (ok (var-set mint-limit-reset-window new-window)))
)

(define-public (set-trader (address principal) (mint bool) (redeem bool))
  (begin
    (try! (contract-call? .hq check-is-protocol tx-sender))
    (map-set traders { address: address } { minter: mint, redeemer: redeem})
    (ok true)
  )
)

;;-------------------------------------
;; Init 
;;-------------------------------------

(map-set traders { address: tx-sender } { minter: true, redeemer: true })