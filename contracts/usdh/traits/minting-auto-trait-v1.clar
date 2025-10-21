;; @contract Minting Auto Trait
;; @version 1

(use-trait ft .sip-010-trait.sip-010-trait)
(use-trait pyth-storage-trait .pyth-traits-v2.storage-trait)
(use-trait pyth-decoder-trait .pyth-traits-v2.decoder-trait)
(use-trait wormhole-core-trait .wormhole-traits-v2.core-trait) 

;;-------------------------------------
;; Trait Definition
;;-------------------------------------

(define-trait minting-auto-trait
  (
    ;;-------------------------------------
    ;; User Functions
    ;;-------------------------------------

    ;; @desc - Mint USDh using supported assets
    ;; @param - minting-asset: SIP-010 trait of the minting asset
    ;; @param - amount-usdh-requested: amount of USDh to mint (10**8)
    ;; @param - price-slippage-tolerance: slippage tolerance in basis points
    ;; @param - memo: optional memo for the transfer call
    ;; @param - price-feed-bytes: optional Pyth price feed data
    ;; @param - execution-plan: Pyth contracts configuration
    ;; @return - (ok bool) on success, (err uint) on failure
    (mint 
      (
        <ft> 
        uint 
        uint 
        (optional (buff 34))
        (optional (buff 8192))
        {
          pyth-storage-contract: <pyth-storage-trait>,
          pyth-decoder-contract: <pyth-decoder-trait>,
          wormhole-core-contract: <wormhole-core-trait>
        }
      ) 
      (response bool uint)
    )

    ;; @desc - Redeem USDh for supported assets
    ;; @param - redeeming-asset: SIP-010 trait of the redeeming asset
    ;; @param - amount-usdh-requested: amount of USDh to redeem (10**8)
    ;; @param - price-slippage-tolerance: slippage tolerance in basis points
    ;; @param - memo: optional memo for the transfer call
    ;; @param - price-feed-bytes: optional Pyth price feed data
    ;; @param - execution-plan: Pyth contracts configuration
    ;; @return - (ok bool) on success, (err uint) on failure
    (redeem 
      (
        <ft> 
        uint 
        uint 
        (optional (buff 34))
        (optional (buff 8192))
        {
          pyth-storage-contract: <pyth-storage-trait>,
          pyth-decoder-contract: <pyth-decoder-trait>,
          wormhole-core-contract: <wormhole-core-trait>
        }
      ) 
      (response bool uint)
    )
  )
)