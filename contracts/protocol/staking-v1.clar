;; @contract Staking
;; @version 0.1
;;-------------------------------------
;; Constants 
;;-------------------------------------

(define-constant ERR_INVALID_AMOUNT (err u3001))

;;-------------------------------------
;; Constants 
;;-------------------------------------

(define-constant usdh-base (pow u10 u8))

;;-------------------------------------
;; Getters 
;;-------------------------------------

(define-read-only (get-usdh-per-susdh) 
  (let (
    (total-usdh-staked (unwrap-panic (contract-call? .usdh-token get-balance .staking-reserve)))
    (total-susdh-supply (unwrap-panic (contract-call? .susdh-token get-total-supply)))
  )
    (if (and (> total-usdh-staked u0) (> total-susdh-supply u0))   
      (/ 
        (* 
          total-usdh-staked
          usdh-base
        )
        total-susdh-supply
      )
      usdh-base
    )
  )
)

;;-------------------------------------
;; User  
;;-------------------------------------

(define-public (stake (amount uint))
  (let (
    (ratio (get-usdh-per-susdh))
    (amount-susdh (/ (* amount usdh-base) ratio))
  )
    (asserts! (> amount u0) ERR_INVALID_AMOUNT)
    (try! (contract-call? .blacklist-susdh check-is-not-soft-blacklist tx-sender))
    (try! (contract-call? .hq check-is-enabled))

    (try! (contract-call? .usdh-token transfer amount tx-sender .staking-reserve none))
    (try! (contract-call? .susdh-token mint-for-protocol amount-susdh tx-sender))
    (ok true)
  )
)

(define-public (unstake (amount uint))
  (let (
    (ratio (get-usdh-per-susdh))
    (amount-usdh (/ (* amount ratio) usdh-base))
  )
    (asserts! (> amount u0) ERR_INVALID_AMOUNT)
    (try! (contract-call? .blacklist-susdh check-is-not-soft-blacklist tx-sender))
    
    (try! (contract-call? .susdh-token burn-for-protocol amount tx-sender))
    (try! (contract-call? .staking-silo create-claim amount-usdh tx-sender))
    (try! (contract-call? .staking-reserve transfer amount-usdh .staking-silo))
    (print { amount-susdh: amount, amount-usdh: amount-usdh, ratio: ratio })
    (ok true)
  )
)

;; init

(begin 
  (try! (contract-call? .susdh-token mint-for-protocol usdh-base .staking))
  (try! (contract-call? .usdh-token mint-for-protocol usdh-base .staking-reserve))
)