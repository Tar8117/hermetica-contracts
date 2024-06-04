;; @contract Reserve
;; @version 0.1

;;-------------------------------------
;; Get USDh
;;-------------------------------------

(define-public (get-usdh (requested-amount uint) (recipient principal))
  (begin
    (try! (contract-call? .hq check-is-protocol contract-caller))

    (try! (as-contract (contract-call? .usdh-token transfer requested-amount tx-sender recipient none)))
    (ok requested-amount)
  )
)