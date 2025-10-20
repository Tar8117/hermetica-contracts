;; @contract Zest Market Trait v1
;; @version 1.0
;; @desc Trait definition for Zest v2 market contract

(use-trait ft 'SP2VCQJGH7PHP2DJK7Z0V48AGBHQAW3R3ZW1QF4N.ft-trait.ft-trait)

(define-trait zest-market-trait
  (
    (collateral-add (<ft> uint principal) (response bool uint))
    (collateral-remove (<ft> uint principal) (response bool uint))
    (borrow (<ft> uint principal) (response bool uint))
    (repay (<ft> uint principal) (response bool uint))
  )
)
