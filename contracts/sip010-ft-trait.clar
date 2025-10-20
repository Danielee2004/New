(define-trait sip010-ft-standard
  (
    (transfer (uint principal principal (optional (buff 34))) (response bool uint))
    (get-balance (principal) (response uint uint))
    (get-total-supply () (response uint uint))
    (get-decimals () (response uint uint))
    (get-symbol () (response (string-ascii 32) uint))
    (get-name () (response (string-ascii 32) uint))
    (get-allowance (principal principal) (response uint uint))
    (approve (principal uint) (response bool uint))
    (transfer-from (principal principal uint (optional (buff 34))) (response bool uint))
  )
)
