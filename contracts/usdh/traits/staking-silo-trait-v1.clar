;; @contract Staking Silo Trait
;; @version 1

;;-------------------------------------
;; Trait Definition
;;-------------------------------------

(define-trait staking-silo-trait
  (
    ;;-------------------------------------
    ;; Getters
    ;;-------------------------------------

    ;; @desc - Get claim data by ID
    (get-claim (uint) (response {recipient: principal, amount: uint, ts: uint} uint))

    ;;-------------------------------------
    ;; User Functions
    ;;-------------------------------------

    ;; @desc - Transfer USDh to recipient after cooldown window has passed
    (withdraw (uint) (response bool uint))

  )
)