;; @contract State
;; @version 0.1

;;-------------------------------------
;; Constants 
;;-------------------------------------

(define-constant ERR_NOT_GATEKEEPER (err u2001))
(define-constant ERR_NOT_WHITELISTED (err u2002))
(define-constant ERR_ABOVE_MAX (err u2003))

(define-constant usdh-base (pow u10 u8))
(define-constant max-confirmation-window u144)
(define-constant max-fee u200)                                          ;; bps (2%)

;;-------------------------------------
;; Variables 
;;-------------------------------------

(define-data-var mint-confirmation-window uint u10)                     ;; burn-block-height
(define-data-var redeem-confirmation-window uint u10)                   ;; burn-block-height

(define-data-var whitelist-enabled bool true)                           ;; disable whitelist
(define-data-var mint-enabled bool true)                                ;; disable request-mint, confirm-mint, cancel-unconfirmed-mint
(define-data-var redeem-enabled bool true)                              ;; disable request-redeem, confirm-redeem, cancel-unconfirmed-redeem

(define-data-var min-amount-usdh-requested uint (* u1000 usdh-base))    ;; usdh 

(define-data-var fee-address principal tx-sender)
(define-data-var mint-fee-usdh uint u10)                                ;; bps
(define-data-var redeem-fee-usdh uint u10)                              ;; bps
(define-data-var mint-fee-asset uint u10)                               ;; bps
(define-data-var redeem-fee-asset uint u10)                             ;; bps

;;-------------------------------------
;; Maps 
;;-------------------------------------

(define-map whitelist
  { 
    address: principal 
  }
  {
    minter: bool,
    redeemer: bool
  }
)

(define-map gatekeepers
  { 
    address: principal 
  }
  {
    active: bool
  }
)

;;-------------------------------------
;; Getters 
;;-------------------------------------

(define-read-only (get-mint-confirmation-window) 
  (var-get mint-confirmation-window)
)

(define-read-only (get-redeem-confirmation-window) 
  (var-get redeem-confirmation-window)
)

(define-read-only (get-whitelist-enabled) 
  (var-get whitelist-enabled)
)

(define-read-only (get-mint-enabled) 
  (var-get mint-enabled)
)

(define-read-only (get-redeem-enabled) 
  (var-get redeem-enabled)
)

(define-read-only (get-fee-address) 
  (var-get fee-address)
)

(define-read-only (get-min-amount-usdh-requested) 
  (var-get min-amount-usdh-requested)
)

(define-read-only (get-mint-fee-usdh) 
  (var-get mint-fee-usdh)
)

(define-read-only (get-redeem-fee-usdh) 
  (var-get redeem-fee-usdh)
)

(define-read-only (get-mint-fee-asset) 
  (var-get mint-fee-asset)
)

(define-read-only (get-redeem-fee-asset) 
  (var-get redeem-fee-asset)
)

(define-read-only (get-whitelist (address principal))
  (default-to 
    { minter: false, redeemer: false }
    (map-get? whitelist { address: address })
  )
)

(define-read-only (get-gatekeeper-active (address principal))
  (get active 
    (default-to 
      { active: false }
      (map-get? gatekeepers { address: address })
    )
  )
)

;;-------------------------------------
;; Checks
;;-------------------------------------

(define-read-only (check-is-gatekeeper (address principal))
  (begin
    (asserts! (get-gatekeeper-active address) ERR_NOT_GATEKEEPER)
    (ok true)
  )
)

(define-read-only (check-is-minter (address principal))
  (begin
    (if (get-whitelist-enabled) (asserts! (get minter (get-whitelist address)) ERR_NOT_WHITELISTED) true)
    (ok true)
  )
)

(define-read-only (check-is-redeemer (address principal))
  (begin
    (if (get-whitelist-enabled) (asserts! (get redeemer (get-whitelist address)) ERR_NOT_WHITELISTED) true)
    (ok true)
  )
)

;;-------------------------------------
;; Admin
;;-------------------------------------

(define-public (set-mint-confirmation-window (new-window uint))
  (begin
    (try! (contract-call? .hq check-is-protocol tx-sender))
    (asserts! (<= new-window max-confirmation-window) ERR_ABOVE_MAX)
    (var-set mint-confirmation-window new-window)
    (ok true)
  )
)

(define-public (set-redeem-confirmation-window (new-window uint))
  (begin
    (try! (contract-call? .hq check-is-protocol tx-sender))
    (asserts! (<= new-window max-confirmation-window) ERR_ABOVE_MAX)
    (var-set redeem-confirmation-window new-window)
    (ok true)
  )
)

(define-public (set-whitelist-enabled (whitelist-enabled-set bool))
  (begin
    (try! (contract-call? .hq check-is-protocol tx-sender))
    (var-set whitelist-enabled whitelist-enabled-set)
    (ok true)
  )
)

(define-public (set-mint-enabled (mint-enabled-set bool))
  (begin
    (try! (contract-call? .hq check-is-protocol tx-sender))
    (var-set mint-enabled mint-enabled-set)
    (ok true)
  )
)

(define-public (set-redeem-enabled (redeem-enabled-set bool))
  (begin
    (try! (contract-call? .hq check-is-protocol tx-sender))
    (var-set redeem-enabled redeem-enabled-set)
    (ok true)
  )
)

(define-public (set-min-amount-usdh-requested (new-min-amount-usdh-requested uint))
  (begin
    (try! (contract-call? .hq check-is-protocol tx-sender))
    (ok (var-set min-amount-usdh-requested new-min-amount-usdh-requested))
  )
)

(define-public (set-fee-address (new-fee-address principal))
  (begin
    (try! (contract-call? .hq check-is-protocol tx-sender))
    (ok (var-set fee-address new-fee-address)))
)

(define-public (set-mint-fee-usdh (new-mint-fee-usdh uint))
  (begin
    (try! (contract-call? .hq check-is-protocol tx-sender))
    (asserts! (<= new-mint-fee-usdh max-fee) ERR_ABOVE_MAX)
    (ok (var-set mint-fee-usdh new-mint-fee-usdh)))
)

(define-public (set-redeem-fee-usdh (new-redeem-fee-usdh uint))
  (begin
    (try! (contract-call? .hq check-is-protocol tx-sender))
    (asserts! (<= new-redeem-fee-usdh max-fee) ERR_ABOVE_MAX)
    (ok (var-set redeem-fee-usdh new-redeem-fee-usdh)))
)

(define-public (set-mint-fee-asset (new-mint-fee-asset uint))
  (begin
    (try! (contract-call? .hq check-is-protocol tx-sender))
    (asserts! (<= new-mint-fee-asset max-fee) ERR_ABOVE_MAX)
    (ok (var-set mint-fee-asset new-mint-fee-asset)))
)

(define-public (set-redeem-fee-asset (new-redeem-fee-asset uint))
  (begin
    (try! (contract-call? .hq check-is-protocol tx-sender))
    (asserts! (<= new-redeem-fee-asset max-fee) ERR_ABOVE_MAX)
    (ok (var-set redeem-fee-asset new-redeem-fee-asset)))
)

(define-public (set-gatekeeper (address principal) (active bool))
  (begin
    (try! (contract-call? .hq check-is-protocol tx-sender))
    (map-set gatekeepers { address: address } { active: active })
    (ok true)
  )
)

;;-------------------------------------
;; Gatekeeper  
;;-------------------------------------

(define-public (set-trading-disabled)
  (begin 
    (try! (check-is-gatekeeper tx-sender))
    (var-set mint-enabled false)
    (var-set redeem-enabled false)
    (ok true)
  )
)

(define-public (set-mint-disabled)
  (begin 
    (try! (check-is-gatekeeper tx-sender))
    (var-set mint-enabled false)
    (ok true)
  )
)

(define-public (set-redeem-disabled)
  (begin 
    (try! (check-is-gatekeeper tx-sender))
    (var-set redeem-enabled false)
    (ok true)
  )
)

(define-private (whitelist-processor (entry {address: principal, mint: bool, redeem: bool}))
  (map-set whitelist { address: (get address entry) } { minter: (get mint entry), redeemer: (get redeem entry)})
)

(define-private (whitelist-remover (address principal)) 
  (map-delete whitelist { address: address })
)

(define-public (add-whitelist (entries (list 1000 {address: principal, mint: bool, redeem: bool})))
  (begin
    (try! (check-is-gatekeeper tx-sender))
    (ok (map whitelist-processor entries)))
)

(define-public (remove-whitelist (entries (list 1000 principal)))
  (begin
    (try! (check-is-gatekeeper tx-sender))
    (ok (map whitelist-remover entries)))
)

;;-------------------------------------
;; Init
;;-------------------------------------

(map-set gatekeepers { address: tx-sender } { active: true })
