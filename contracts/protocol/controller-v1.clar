;; @contract Controller
;; @version 0.1

;;-------------------------------------
;; Constants 
;;-------------------------------------

(define-constant ERR_NOT_UPDATER (err u5001))
(define-constant ERR_UPDATE_WINDOW_CLOSED (err u5002))
(define-constant ERR_ABOVE_MAX (err u5003))
(define-constant ERR_BELOW_MIN (err u5005))

(define-constant max-pnl u20)                     ;; bps
(define-constant min-update-window (* u6 u6))     ;; burn-block-height

(define-constant bps-base (pow u10 u4))

;;-------------------------------------
;; Variables
;;-------------------------------------

(define-data-var max-pnl-per-window uint u10)                     ;; bps
(define-data-var update-window uint (* u6 u8))                    ;; burn-block-height

(define-data-var last-log-block-height uint burn-block-height)    ;; burn-block-height

;;-------------------------------------
;; Maps 
;;-------------------------------------

(define-map updaters
  { 
    address: principal 
  }
  {
    active: bool,
  }
)

;;-------------------------------------
;; Getters 
;;-------------------------------------

(define-read-only (get-max-pnl-per-window) 
  (var-get max-pnl-per-window)
)

(define-read-only (get-update-window) 
  (var-get update-window)
)

(define-read-only (get-last-log-block-height) 
  (var-get last-log-block-height)
)

(define-read-only (get-updater (address principal))
  (get active 
    (default-to 
      { active: false }
      (map-get? updaters { address: address })
    )
  )
)

;;-------------------------------------
;; Checks  
;;-------------------------------------

(define-public (check-is-updater (contract principal))
  (begin
    (asserts! (get-updater contract) ERR_NOT_UPDATER)
    (ok true)
  )
)

;;-------------------------------------
;; Updater
;;-------------------------------------

;; @desc - Log and distribute the pnl to the staking contract
;; @param pnl-usdh - the pnl to be sent to the staking-reserve (in USDh, 10**8)
(define-public (log-pnl (pnl-usdh uint))
  (let (
    (total-usdh-supply (unwrap-panic (contract-call? .usdh-token get-total-supply)))
    (total-usdh-supply-staked (unwrap-panic (contract-call? .usdh-token get-balance .staking-reserve)))
  )
    (try! (contract-call? .hq check-is-enabled))
    (try! (check-is-updater tx-sender))
    (asserts! (> burn-block-height (+ (var-get last-log-block-height) (var-get update-window))) ERR_UPDATE_WINDOW_CLOSED)
    (asserts! (<= pnl-usdh (/ (* (var-get max-pnl-per-window) total-usdh-supply) bps-base)) ERR_ABOVE_MAX)
    (if (> pnl-usdh u0)
      (begin
        (print { 
          return-percent-of-bps: (/ (* pnl-usdh bps-base u100) total-usdh-supply-staked),
          total-usdh-supply: total-usdh-supply,
          total-usdh-supply-staked: total-usdh-supply-staked,
          pnl-usdh: pnl-usdh
        })
        (try! (contract-call? .usdh-token mint-for-protocol pnl-usdh .staking-reserve))
      )
      true
    )
    (var-set last-log-block-height burn-block-height)
    (ok true)
  )
)

;;-------------------------------------
;; Admin
;;-------------------------------------

(define-public (set-max-pnl-per-window (new-max-pnl-per-window uint))
  (begin
    (try! (contract-call? .hq check-is-protocol tx-sender))
    (asserts! (<= new-max-pnl-per-window max-pnl) ERR_ABOVE_MAX)
    (var-set max-pnl-per-window new-max-pnl-per-window)
    (ok true)
  )
)

(define-public (set-update-window (new-update-window uint))
  (begin
    (try! (contract-call? .hq check-is-protocol tx-sender))
    (asserts! (>= new-update-window min-update-window) ERR_BELOW_MIN)
    (var-set update-window new-update-window)
    (ok true)
  )
)

(define-public (set-updater (address principal) (active bool))
  (begin
    (try! (contract-call? .hq check-is-protocol tx-sender))
    (map-set updaters { address: address } { active: active })
    (ok true)
  )
)

;;-------------------------------------
;; Init 
;;-------------------------------------

(map-set updaters { address: tx-sender } { active: true })