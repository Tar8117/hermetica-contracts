;; @contract Zest Vault Trait v1
;; @version 1.0
;; @desc Trait definition for Zest v2 vault contract

(define-trait zest-vault-trait
  (
    (deposit (uint uint principal) (response uint uint))
    (redeem (uint uint principal) (response uint uint))
  )
)

