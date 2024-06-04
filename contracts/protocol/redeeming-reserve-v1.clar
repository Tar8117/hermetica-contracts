;; @contract Redeeming Reserve
;; @version 0.1

(use-trait sip-010-trait .sip-010-trait.sip-010-trait)

;;-------------------------------------
;; Get USDh
;;-------------------------------------

(define-public (transfer (amount uint) (recipient principal) (redeeming-asset <sip-010-trait>))
  (begin 
    (try! (contract-call? .hq check-is-protocol contract-caller))

    (try! (as-contract (contract-call? redeeming-asset transfer amount tx-sender recipient none)))
    (ok true)
  )
)