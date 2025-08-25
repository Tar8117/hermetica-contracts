;; @contract Staking Silo
;; @version 1.1

;;-------------------------------------
;; Constants
;;-------------------------------------

(define-constant ERR_NO_CLAIM_FOR_ID (err u4001))
(define-constant ERR_NOT_COOLED_DOWN (err u4002))
(define-constant ERR_ONLY_STAKING_CONTRACT (err u4003))

;;-------------------------------------
;; Variables
;;-------------------------------------

(define-data-var current-claim-id uint u0)

;;-------------------------------------
;; Maps
;;-------------------------------------

(define-map claims
  { 
    claim-id: uint
  }
  {
    recipient: principal,
    amount: uint,
    ts: uint,
  }
)

;;-------------------------------------
;; Getters
;;-------------------------------------

(define-read-only (get-current-ts)
  (unwrap-panic (get-stacks-block-info? time (- stacks-block-height u1)))
)

(define-read-only (get-current-claim-id)
  (var-get current-claim-id)
)

(define-read-only (get-claim (id uint))
  (ok (unwrap! (map-get? claims { claim-id: id }) ERR_NO_CLAIM_FOR_ID))
)

;;-------------------------------------
;; User
;;-------------------------------------

(define-public (withdraw-many (entries (list 1000 uint)))
  (ok (map withdraw entries)))

(define-public (withdraw (claim-id uint))
  (let (
    (current-claim (try! (get-claim claim-id)))
  )
    (asserts! (>= (get-current-ts) (get ts current-claim)) ERR_NOT_COOLED_DOWN)
    (try! (contract-call? .usdh-token transfer (get amount current-claim) (as-contract tx-sender) (get recipient current-claim) none))
    (print {action: "withdraw", user: contract-caller, data: {claim-id: claim-id, claim-data: current-claim}})
    (ok (map-delete claims { claim-id: claim-id }))
  )
)

;;-------------------------------------
;; Protocol
;;-------------------------------------

(define-public (create-claim (amount uint) (recipient principal))
  (let (
    (next-claim-id (+ (get-current-claim-id) u1))
    (ts (+ (get-current-ts) (contract-call? .staking-state get-custom-cooldown recipient)))
  )
    (asserts! (is-eq contract-caller .staking) ERR_ONLY_STAKING_CONTRACT)
    (map-set claims { claim-id: next-claim-id } 
      {
        recipient: recipient,
        amount: amount,
        ts: ts
      }
    )
    (print {action: "create-claim", user: contract-caller, data: {claim-id: next-claim-id, recipient: recipient, amount: amount, claim-ts: ts}})
    (ok (var-set current-claim-id next-claim-id))
  )
)