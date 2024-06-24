;; @contract Blacklist sUSDh
;; @version 0.1

;;-------------------------------------
;; Constants 
;;-------------------------------------

(define-constant ERR_NOT_BLACKLISTER (err u6001))
(define-constant ERR_SOFT_BLACKLISTED (err u6002))
(define-constant ERR_FULLY_BLACKLISTED (err u6003))

;;-------------------------------------
;; Variables 
;;-------------------------------------

(define-data-var soft-blacklist-enabled bool true)

;;-------------------------------------
;; Maps 
;;-------------------------------------

(define-map blacklister
  {
    address: principal
  }
  {
    active: bool,
  }
)

(define-map blacklist
  {
    address: principal
  }
  {
    soft: bool,
    full: bool
  }
)

;;-------------------------------------
;; Getters 
;;-------------------------------------

(define-read-only (get-soft-blacklist-enabled) 
  (var-get soft-blacklist-enabled)
)

(define-read-only (get-blacklister (address principal))
  (get active 
    (default-to 
      { active: false }
      (map-get? blacklister { address: address })
    )
  )
)

(define-read-only (get-soft-blacklist (address principal))
  (get soft 
    (default-to 
      { soft: false }
      (map-get? blacklist { address: address })
    )
  )
)

(define-read-only (get-full-blacklist (address principal))
  (get full 
    (default-to 
      { full: false }
      (map-get? blacklist { address: address })
    )
  )
)

;;-------------------------------------
;; Checks  
;;-------------------------------------

(define-public (check-is-blacklister (contract principal))
  (begin
    (asserts! (get-blacklister contract) ERR_NOT_BLACKLISTER)
    (ok true)
  )
)

(define-public (check-is-not-soft-blacklist (contract principal))
  (begin
    (if (get-soft-blacklist-enabled)
      (asserts! (not (get-soft-blacklist contract)) ERR_SOFT_BLACKLISTED)
      true
    )
    (ok true)
  )
)

(define-public (check-is-not-full-blacklist (contract principal))
  (begin
    (asserts! (not (get-full-blacklist contract)) ERR_FULLY_BLACKLISTED)
    (ok true)
  )
)

(define-public (check-is-not-full-blacklist-two (contract1 principal) (contract2 principal))
  (ok (asserts! (and 
    (not (get-full-blacklist contract1))
    (not (get-full-blacklist contract2))
  ) ERR_FULLY_BLACKLISTED))
)

;;-------------------------------------
;; Update  
;;-------------------------------------

(define-private (blacklist-processor (entry { address: principal, full: bool }))
  (if (get full entry)
    (map-set blacklist { address: (get address entry) } { soft: true, full: true })
    (map-set blacklist { address: (get address entry) } { soft: true, full: false })
  )
)

(define-private (blacklist-remover (address principal)) 
    (map-delete blacklist { address: address })
)

(define-public (add-blacklist (entries (list 1000 { address: principal, full: bool })))
  (begin
    (try! (check-is-blacklister tx-sender))
    (ok (map blacklist-processor entries))
  )
)

(define-public (remove-blacklist (entries (list 1000 principal)))
  (begin
    (try! (check-is-blacklister tx-sender))
    (ok (map blacklist-remover entries))
  )
)

;;-------------------------------------
;; Admin
;;-------------------------------------

(define-public (set-blacklister (address principal) (active bool))
  (begin
    (try! (contract-call? .hq check-is-protocol tx-sender))
    (map-set blacklister { address: address } { active: active })
    (ok true)
  )
)

(define-public (set-soft-blacklist-enabled (active bool))
  (begin
    (try! (contract-call? .hq check-is-protocol tx-sender))
    (ok (var-set soft-blacklist-enabled active))
  )
)