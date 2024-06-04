;; @contract Staking Reserve
;; @version 0.1

;;-------------------------------------
;; Protocol
;;-------------------------------------

(define-public (transfer (amount uint) (recipient principal))
  (begin 
    (try! (contract-call? .hq check-is-protocol contract-caller))
    (try! (as-contract (contract-call? .usdh-token transfer amount tx-sender recipient none)))
    (ok true)
  )
)