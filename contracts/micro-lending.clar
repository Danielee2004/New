;; micro-lending.clar
;; Micro-Lending Pool with Automatic Risk Control
;; - Contributors fund treasury via contribute
;; - Borrowers deposit collateral
;; - Borrower requests loan; if collateral >= required ratio, loan issued
;; - Borrower repays principal + interest; collateral returned on repayment
;; - Anyone can liquidate undercollateralized / overdue loans

(define-constant ERR_NOT_ENOUGH_COLLATERAL u100)
(define-constant ERR_TREASURY_INSUFFICIENT u101)
(define-constant ERR_ALREADY_HAS_LOAN u102)
(define-constant ERR_NO_SUCH_LOAN u103)
(define-constant ERR_NOT_BORROWER u104)
(define-constant ERR_NOT_REPAID u105)
(define-constant ERR_BAD_AMOUNT u106)
(define-constant ERR_NOT_ENOUGH_COLLATERAL_FOR_REQUEST u107)
(define-constant ERR_DEADLINE_NOT_REACHED u108)
(define-constant ERR_ALREADY_REPAID u109)
(define-constant ERR_NOT_GUARDIAN u110)

;; admin (deployer) set on first call to init-admin
(define-data-var admin (optional principal) none)

(define-data-var treasury uint u0) ;; tracked treasury (ustx)
(define-data-var loan-count uint u0)

;; collateral per address
(define-map collaterals principal (tuple (amount uint)))

;; loan structure: id -> tuple(borrower, principal, interest, start-block, due-block, collateral-locked, repaid uint)
(define-map loans uint
  (tuple
    (borrower principal)
    (principal uint)         ;; principal amount lent
    (interest uint)          ;; total interest to be repaid (computed at creation)
    (start_block uint)
    (due_block uint)
    (collateral uint)        ;; collateral amount locked for this loan
    (repaid uint)            ;; 0/1
  )
)

;; settings (can be updated by admin)
(define-data-var COLLATERAL_RATIO uint u150) ;; percent (e.g., 150 = 150%)
(define-data-var INTEREST_PER_BLOCK uint u10) ;; interest per block in ustx per 1_000_000 principal? (we'll use interest = principal * INTEREST_PER_BLOCK * duration / 1_000_000)
(define-data-var MIN_LOAN uint u1000) ;; minimum loan (ustx)

;; ------------------------
;; Helper read-only
;; ------------------------
(define-read-only (get-treasury) (var-get treasury))
(define-read-only (get-loan-count) (var-get loan-count))
(define-read-only (get-collateral (who principal))
  (match (map-get? collaterals who) c (get amount c) u0)
)
(define-read-only (get-loan (id uint))
  (map-get? loans id)
)
(define-read-only (get-collateral-ratio) (var-get COLLATERAL_RATIO))
(define-read-only (get-interest-per-block) (var-get INTEREST_PER_BLOCK))
(define-read-only (get-min-loan) (var-get MIN_LOAN))
(define-read-only (get-admin) (var-get admin))

;; ------------------------
;; Admin initialization (call once)
;; ------------------------
(define-public (init-admin (who principal))
  (begin
    (match (var-get admin)
      none
        (begin
          (var-set admin (some who))
          (ok u1))
      (some _) (err u201)
    )
  )
)

(define-read-only (is-admin (who principal))
  (is-eq (var-get admin) (some who))
)

;; ------------------------
;; Contribute to treasury (anyone)
;; Caller must pass `amount` as parameter and transfer STX to contract
;; ------------------------
(define-public (contribute (amount uint))
  (begin
    (asserts! (>= amount u1) (err ERR_BAD_AMOUNT))
    (try! (stx-transfer? amount tx-sender (as-contract tx-sender)))
    (var-set treasury (+ (var-get treasury) amount))
    (ok u1)
  )
)

;; ------------------------
;; Deposit collateral (caller transfers STX to contract)
;; ------------------------
(define-public (deposit-collateral (amount uint))
  (begin
    (asserts! (>= amount u1) (err ERR_BAD_AMOUNT))
    (try! (stx-transfer? amount tx-sender (as-contract tx-sender)))
    (let ((maybe (map-get? collaterals tx-sender)))
      (if (is-some maybe)
          (let ((c (unwrap-panic maybe)))
            (map-set collaterals tx-sender (tuple (amount (+ (get amount c) amount))))
          )
          (map-set collaterals tx-sender (tuple (amount amount)))
      )
    )
    (ok u1)
  )
)

;; ------------------------
;; Withdraw collateral that is not locked in loans (simple rule: allow withdraw only if collateral >= sum of locked collateral)
;; NOTE: For simplicity we do not track per-loan collateral separately beyond loans mapping; on withdraw we check total collateral and total locked by scanning loans (inefficient but OK for demo)
;; ------------------------
(define-public (withdraw-collateral (amount uint))
  (begin
    (asserts! (>= amount u1) (err ERR_BAD_AMOUNT))
    (let ((current (get-collateral tx-sender)))
      (asserts! (>= current amount) (err ERR_NOT_ENOUGH_COLLATERAL))
      ;; compute total locked by this borrower across loans
      (let ((locked u0) (i u0) (n (var-get loan-count)))
        (let loop ((i i) (locked locked))
          (if (< i n)
              (let ((maybe-loan (map-get? loans i)))
                (if (is-some maybe-loan)
                    (begin
                      (let ((l (unwrap-panic maybe-loan)))
                        (if (is-eq (get borrower l) tx-sender)
                            (loop (+ i u1) (+ locked (get collateral l)))
                            (loop (+ i u1) locked)
                        )
                      )
                    )
                    (loop (+ i u1) locked)
                )
              ;; end loop: ensure remaining collateral after withdraw >= locked
              (begin
                (asserts! (>= (- current amount) locked) (err ERR_NOT_ENOUGH_COLLATERAL))
                ;; update map and transfer
                (let ((new (- current amount)))
                  (map-set collaterals tx-sender (tuple (amount new))) 
                  (try! (stx-transfer? amount (as-contract tx-sender) tx-sender))
                  (ok u1)
                )
              )
          )
        )
      )
    )
  )
)

;; ------------------------
;; Request Loan:
;; - borrower calls request-loan with desired principal and duration (blocks)
;; - contract verifies borrower has enough collateral: collateral >= principal * COLLATERAL_RATIO / 100
;; - create loan, lock collateral (we simply reference collateral and record locked collateral amount)
;; - transfer principal to borrower (if treasury has funds)
;; ------------------------
(define-public (request-loan (principal uint) (duration_blocks uint))
  (begin
    (asserts! (>= principal (var-get MIN_LOAN)) (err ERR_BAD_AMOUNT))
    (let ((coll (get-collateral tx-sender)))
      (asserts! (>= coll u1) (err ERR_NOT_ENOUGH_COLLATERAL))
      ;; required collateral = principal * COLLATERAL_RATIO / 100
      (let ((req (* principal (var-get COLLATERAL_RATIO))))
        (let ((reqdiv (/ req u100)))
          (asserts! (>= coll reqdiv) (err ERR_NOT_ENOUGH_COLLATERAL_FOR_REQUEST))
          ;; check treasury
          (asserts! (>= (var-get treasury) principal) (err ERR_TREASURY_INSUFFICIENT))
          ;; compute interest: interest = principal * INTEREST_PER_BLOCK * duration_blocks / 1_000_000
          (let ((interest-mul (* principal (var-get INTEREST_PER_BLOCK)))
                (dur duration_blocks))
            (let ((interest (/ (* interest-mul dur) u1000000)))
              ;; create loan record
              (let ((id (var-get loan-count))
                    (start (get-block-height))
                    (due (+ (get-block-height) dur)))
                (map-set loans id (tuple (borrower tx-sender) (principal principal) (interest interest) (start_block start) (due_block due) (collateral coll) (repaid u0)))
                ;; reduce treasury
                (var-set treasury (- (var-get treasury) principal))
                ;; transfer principal to borrower
                (try! (stx-transfer? principal (as-contract tx-sender) tx-sender))
                ;; increment count
                (var-set loan-count (+ id u1))
                (ok id)
              )
            )
          )
        )
      )
    )
  )
)

;; ------------------------
;; Repay loan:
;; - borrower must call repay with loan id and send principal+interest as STX to contract
;; - on success, mark repaid=1 and release collateral back to borrower
;; ------------------------
(define-public (repay-loan (id uint))
  (begin
    (let ((maybe (map-get? loans id)))
      (asserts! (is-some maybe) (err ERR_NO_SUCH_LOAN))
      (let ((l (unwrap-panic maybe)))
        (asserts! (is-eq (get borrower l) tx-sender) (err ERR_NOT_BORROWER))
        (asserts! (is-eq (get repaid l) u0) (err ERR_ALREADY_REPAID))
        (let ((due-amount (+ (get principal l) (get interest l))))
          ;; caller must transfer due-amount to contract
          (try! (stx-transfer? due-amount tx-sender (as-contract tx-sender)))
          ;; increase treasury
          (var-set treasury (+ (var-get treasury) due-amount))
          ;; mark repaid
          (map-set loans id (merge l { repaid: u1 }))
          ;; release collateral: subtract collateral from collaterals map and transfer back
          (let ((collamt (get collateral l)))
            (let ((curcoll (get-collateral tx-sender)))
              (let ((newcoll (- curcoll collamt)))
                (map-set collaterals tx-sender (tuple (amount newcoll)))
                (try! (stx-transfer? collamt (as-contract tx-sender) tx-sender))
                (ok u1)
              )
            )
          )
        )
      )
    )
  )
)

;; ------------------------
;; Liquidate loan:
;; - Anyone can call if loan is overdue (current block > due_block) OR collateral < required ratio
;; - Seize collateral into treasury; mark loan repaid (effectively closed)
;; ------------------------
(define-public (liquidate-loan (id uint))
  (begin
    (let ((maybe (map-get? loans id)))
      (asserts! (is-some maybe) (err ERR_NO_SUCH_LOAN))
      (let ((l (unwrap-panic maybe)))
        (asserts! (is-eq (get repaid l) u0) (err ERR_ALREADY_REPAID))
        (let ((current-block (get-block-height))
              (due (get due_block l))
              (coll (get collateral l))
              (principal (get principal l)))
          (let ((required (* principal (var-get COLLATERAL_RATIO)))
                (reqdiv ( / (* principal (var-get COLLATERAL_RATIO)) u100)))
            ;; check if overdue OR collateral insufficient
            (if (or (> current-block due) (< coll reqdiv))
                (begin
                  ;; seize collateral to treasury
                  (var-set treasury (+ (var-get treasury) coll))
                  ;; mark loan repaid (closed)
                  (map-set loans id (merge l { repaid: u1 }))
                  ;; reduce collateral map for borrower
                  (let ((borrower (get borrower l))
                        (curcoll (get-collateral (get borrower l))))
                    ;; careful: get borrower collaterals
                    ;; We can't call get-collateral with dynamic principal directly as read-only. Instead use map-get?
                    (let ((maybeColl (map-get? collaterals (get borrower l))))
                      (if (is-some maybeColl)
                          (let ((c (unwrap-panic maybeColl)))
                            (map-set collaterals (get borrower l) (tuple (amount (- (get amount c) coll))))
                          )
                          (map-set collaterals (get borrower l) (tuple (amount u0)))
                      )
                    )
                  )
                  (ok u1)
                )
                (err ERR_DEADLINE_NOT_REACHED)
            )
          )
        )
      )
    )
  )
)