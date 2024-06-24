;; @contract Recover
;; @version 0.1

;;-------------------------------------
;; Constants
;;-------------------------------------

(define-constant ERR_NOT_BLACKLISTED (err u7001))

;;-------------------------------------
;; Recover
;;-------------------------------------

(define-public (recover-usdh (address principal) (recipient principal))
  (let (
     (balance (unwrap-panic (contract-call? .usdh-token get-balance address)))
  )
  (try! (contract-call? .hq check-is-enabled))
  (try! (contract-call? .hq check-is-protocol tx-sender))

  (try! (as-contract (contract-call? .usdh-token burn-for-protocol balance address)))
  (try! (as-contract (contract-call? .usdh-token mint-for-protocol balance recipient)))
  (ok true))
)

(define-public (recover-susdh (address principal) (recipient principal))
  (let (
     (balance (unwrap-panic (contract-call? .susdh-token get-balance address)))
  )
  (try! (contract-call? .hq check-is-enabled))
  (try! (contract-call? .hq check-is-protocol tx-sender))
  
  (if (contract-call? .susdh-token get-blacklist-enabled)
    (begin 
      (try! (contract-call? .blacklist-susdh check-is-not-full-blacklist recipient))
      (asserts! (contract-call? .blacklist-susdh get-full-blacklist address) ERR_NOT_BLACKLISTED)
    )
    true
  )

  (try! (as-contract (contract-call? .susdh-token burn-for-protocol balance address)))
  (try! (as-contract (contract-call? .susdh-token mint-for-protocol balance recipient)))
  (ok true))
)