;; contracts/chinese-coin.clar
;; SIP-010 FT with security features (pause, blacklist, capped supply, admin)


(define-constant ERR-NOT-AUTHORIZED u100)
(define-constant ERR-PAUSED u101)
(define-constant ERR-BLACKLISTED u102)
(define-constant ERR-INSUFFICIENT-BALANCE u103)
(define-constant ERR-INSUFFICIENT-ALLOWANCE u104)
(define-constant ERR-SUPPLY-CAP u105)
(define-constant ERR-INITIALIZED u106)

(define-constant TOKEN-NAME (some "Chinese-coin"))
(define-constant TOKEN-SYMBOL (some "CHNC"))
(define-constant TOKEN-DECIMALS u8)

;; Max supply: 21,000,000 * 10^8 = 2,100,000,000,000,000
(define-data-var max-supply uint u2100000000000000)
(define-data-var total-supply uint u0)

;; Owner (set once via initialize)
(define-data-var owner (optional principal) none)
(define-data-var paused bool false)

(define-map balances { account: principal } { balance: uint })
(define-map allowances { owner: principal, spender: principal } { amount: uint })
(define-map blacklisted { account: principal } { flagged: bool })

;; --- internal helpers ---
(define-read-only (balance-of (who principal))
  (default-to u0 (get balance (unwrap-panic (ok (map-get? balances { account: who }))))))

(define-read-only (allowance-of (own principal) (spend principal))
  (default-to u0 (get amount (unwrap-panic (ok (map-get? allowances { owner: own, spender: spend }))))))

(define-read-only (is-owner (who principal))
  (is-eq (var-get owner) (some who)))

(define-read-only (not-paused)
  (is-eq (var-get paused) false))

(define-read-only (not-blacklisted (who principal))
  (is-none (map-get? blacklisted { account: who })))

(define-private (ensure-owner)
  (begin
    (asserts! (is-some (var-get owner)) (err ERR-INITIALIZED))
    (asserts! (is-owner tx-sender) (err ERR-NOT-AUTHORIZED))
    (ok true)))

(define-private (ensure-transferable (sender principal) (recipient principal))
  (begin
    (asserts! (not-paused) (err ERR-PAUSED))
    (asserts! (not-blacklisted sender) (err ERR-BLACKLISTED))
    (asserts! (not-blacklisted recipient) (err ERR-BLACKLISTED))
    (ok true)))

;; --- SIP-010 required functions ---
(define-read-only (get-name)
  (ok (default-to "" TOKEN-NAME)))

(define-read-only (get-symbol)
  (ok (default-to "" TOKEN-SYMBOL)))

(define-read-only (get-decimals)
  (ok TOKEN-DECIMALS))

(define-read-only (get-total-supply)
  (ok (var-get total-supply)))

(define-read-only (get-balance (who principal))
  (ok (balance-of who)))

(define-read-only (get-allowance (own principal) (spend principal))
  (ok (allowance-of own spend)))

(define-public (approve (spender principal) (amount uint))
  (begin
    (map-set allowances { owner: tx-sender, spender: spender } { amount: amount })
    (ok true)))

(define-public (transfer (amount uint) (sender principal) (recipient principal) (memo (optional (buff 34))))
  (begin
    (try! (ensure-transferable sender recipient))
    (let ((from-bal (balance-of sender)))
      (begin
        (asserts! (<= amount from-bal) (err ERR-INSUFFICIENT-BALANCE))
        ;; debit sender
        (map-set balances { account: sender } { balance: (- from-bal amount) })
        ;; credit recipient
        (let ((to-bal (balance-of recipient)))
          (map-set balances { account: recipient } { balance: (+ to-bal amount) })
        )
        (ok true)
      )
    )
  ))

(define-public (transfer-from (sender principal) (recipient principal) (amount uint) (memo (optional (buff 34))))
  (begin
    (try! (ensure-transferable sender recipient))
    (let (
          (from-bal (balance-of sender))
          (allow (allowance-of sender tx-sender))
        )
      (begin
        (asserts! (<= amount from-bal) (err ERR-INSUFFICIENT-BALANCE))
        (asserts! (<= amount allow) (err ERR-INSUFFICIENT-ALLOWANCE))
        ;; update allowance
        (map-set allowances { owner: sender, spender: tx-sender } { amount: (- allow amount) })
        ;; move funds
        (map-set balances { account: sender } { balance: (- from-bal amount) })
        (let ((to-bal (balance-of recipient)))
          (map-set balances { account: recipient } { balance: (+ to-bal amount) })
        )
        (ok true)
      )
    )
  ))

;; --- admin & security ---
(define-public (initialize (new-owner principal))
  (begin
    (asserts! (is-none (var-get owner)) (err ERR-INITIALIZED))
    (var-set owner (some new-owner))
    (ok true)))

(define-public (set-owner (new-owner principal))
  (begin
    (try! (ensure-owner))
    (var-set owner (some new-owner))
    (ok true)))

(define-public (set-paused (flag bool))
  (begin
    (try! (ensure-owner))
    (var-set paused flag)
    (ok true)))

(define-public (set-blacklist (who principal) (flag bool))
  (begin
    (try! (ensure-owner))
    (if flag
      (map-set blacklisted { account: who } { flagged: true })
      (map-delete blacklisted { account: who })
    )
    (ok true)))

(define-public (mint (recipient principal) (amount uint))
  (begin
    (try! (ensure-owner))
    (asserts! (not-paused) (err ERR-PAUSED))
    (let ((ts (var-get total-supply))
          (cap (var-get max-supply)))
      (begin
        (asserts! (<= (+ ts amount) cap) (err ERR-SUPPLY-CAP))
        (var-set total-supply (+ ts amount))
        (let ((to-bal (balance-of recipient)))
          (map-set balances { account: recipient } { balance: (+ to-bal amount) })
        )
        (ok true)
      )
    )
  ))

(define-public (burn (amount uint))
  (begin
    (let ((bal (balance-of tx-sender)))
      (begin
        (asserts! (<= amount bal) (err ERR-INSUFFICIENT-BALANCE))
        (map-set balances { account: tx-sender } { balance: (- bal amount) })
        (var-set total-supply (- (var-get total-supply) amount))
        (ok true)
      )
    )
  ))

;; --- extra views ---
(define-read-only (get-owner)
  (ok (var-get owner)))

(define-read-only (is-paused)
  (ok (var-get paused)))

(define-read-only (is-blacklisted (who principal))
  (ok (is-some (map-get? blacklisted { account: who }))))
