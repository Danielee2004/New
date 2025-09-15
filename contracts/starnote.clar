;; contracts/starnote.clar
;; StarNote - on-chain micro-poems & likes
;; - Users post short ASCII notes (<=140 chars)
;; - Users can like a post (one like per user per post)
;; - Contract tracks leading post (most likes, earliest wins ties)

(define-data-var post-count uint u0)
(define-data-var leading-post uint u0)
(define-data-var leading-likes uint u0)

(define-map posts
    { id: uint }
    {
        author: principal,
        content: (string-ascii 140),
        timestamp: uint,
        likes: uint,
    }
)

(define-map liked
    {
        post-id: uint,
        liker: principal,
    }
    { marker: bool }
)

(define-constant ERR-NO-POST u100)
(define-constant ERR-ALREADY-LIKED u101)

;; Post a micro-poem / note -> returns post id
(define-public (post (text (string-ascii 140)))
    (let ((id (+ u1 (var-get post-count))))
        (begin
            (var-set post-count id)
            (map-set posts { id: id } {
                author: tx-sender,
                content: text,
                timestamp: block-height,
                likes: u0,
            })
            (ok id)
        )
    )
)

;; Like a post (one like per user per post)
(define-public (like (post-id uint))
    (let (
            (p (map-get? posts { id: post-id }))
            (was (map-get? liked {
                post-id: post-id,
                liker: tx-sender,
            }))
        )
        (begin
            (asserts! (is-some p) (err ERR-NO-POST))
            (asserts! (is-none was) (err ERR-ALREADY-LIKED))

            (let (
                    (post (unwrap! p (err ERR-NO-POST)))
                    (new-likes (+ (get likes (unwrap! p (err ERR-NO-POST))) u1))
                )
                ;; update post likes
                (map-set posts { id: post-id } {
                    author: (get author post),
                    content: (get content post),
                    timestamp: (get timestamp post),
                    likes: new-likes,
                })
                ;; mark liker
                (map-set liked {
                    post-id: post-id,
                    liker: tx-sender,
                } { marker: true }
                )
                ;; update leading post if needed (earlier post wins ties because > only)
                (if (> new-likes (var-get leading-likes))
                    (begin
                        (var-set leading-post post-id)
                        (var-set leading-likes new-likes)
                        (ok true)
                    )
                    (ok true)
                )
            )
        )
    )
)

;; --- read-only views ---
(define-read-only (get-post (post-id uint))
    (map-get? posts { id: post-id })
)

(define-read-only (get-count)
    (var-get post-count)
)

(define-read-only (get-leading-id)
    (var-get leading-post)
)

(define-read-only (get-leading-likes)
    (var-get leading-likes)
)