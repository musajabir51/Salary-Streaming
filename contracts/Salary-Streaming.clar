(define-constant ERR-NOT-AUTHORIZED (err u100))
(define-constant ERR-INVALID-AMOUNT (err u101))
(define-constant ERR-INSUFFICIENT-BALANCE (err u102))
(define-constant ERR-EMPLOYEE-EXISTS (err u103))
(define-constant ERR-NO-EMPLOYEE (err u104))
(define-constant ERR-STREAM-ACTIVE (err u105))
(define-constant ERR-STREAM-PAUSED (err u106))
(define-constant ERR-STREAM-NOT-PAUSED (err u107))
(define-constant ERR-INVALID-PERFORMANCE-RATING (err u108))
(define-constant ERR-NO-PERFORMANCE-RATING (err u109))

(define-data-var contract-owner principal tx-sender)
(define-map Employees
    principal
    {
        hourly-rate: uint,
        last-stream: uint,
        total-earned: uint,
        active: bool,
        start-date: uint,
    }
)

(define-map StreamingPayments
    principal
    {
        amount: uint,
        start-block: uint,
        end-block: uint,
        claimed: uint,
        paused: bool,
        paused-at-block: uint,
        total-paused-blocks: uint,
    }
)

(define-data-var treasury-balance uint u0)

(define-map PerformanceRatings
    principal
    {
        rating: uint,
        bonus-multiplier: uint,
        evaluation-period-start: uint,
        evaluation-period-end: uint,
        bonus-claimed: bool,
    }
)

(define-public (initialize-contract)
    (begin
        (asserts! (is-eq tx-sender (var-get contract-owner)) ERR-NOT-AUTHORIZED)
        (ok true)
    )
)

(define-public (add-employee
        (employee-address principal)
        (rate uint)
    )
    (begin
        (asserts! (is-eq tx-sender (var-get contract-owner)) ERR-NOT-AUTHORIZED)
        (asserts! (> rate u0) ERR-INVALID-AMOUNT)
        (asserts! (is-none (map-get? Employees employee-address))
            ERR-EMPLOYEE-EXISTS
        )
        (map-set Employees employee-address {
            hourly-rate: rate,
            last-stream: burn-block-height,
            total-earned: u0,
            active: true,
            start-date: burn-block-height,
        })
        (ok true)
    )
)

(define-public (update-employee-rate
        (employee-address principal)
        (new-rate uint)
    )
    (begin
        (asserts! (is-eq tx-sender (var-get contract-owner)) ERR-NOT-AUTHORIZED)
        (asserts! (> new-rate u0) ERR-INVALID-AMOUNT)
        (asserts! (is-some (map-get? Employees employee-address)) ERR-NO-EMPLOYEE)
        (let ((employee (unwrap! (map-get? Employees employee-address) ERR-NO-EMPLOYEE)))
            (map-set Employees employee-address
                (merge employee { hourly-rate: new-rate })
            )
            (ok true)
        )
    )
)

(define-public (deposit-funds (amount uint))
    (begin
        (asserts! (> amount u0) ERR-INVALID-AMOUNT)
        (var-set treasury-balance (+ (var-get treasury-balance) amount))
        (ok true)
    )
)

(define-public (start-stream
        (employee principal)
        (amount uint)
        (duration uint)
    )
    (begin
        (asserts! (is-eq tx-sender (var-get contract-owner)) ERR-NOT-AUTHORIZED)
        (asserts! (>= (var-get treasury-balance) amount) ERR-INSUFFICIENT-BALANCE)
        (asserts! (is-some (map-get? Employees employee)) ERR-NO-EMPLOYEE)
        (asserts! (is-none (map-get? StreamingPayments employee))
            ERR-STREAM-ACTIVE
        )
        (map-set StreamingPayments employee {
            amount: amount,
            start-block: burn-block-height,
            end-block: (+ burn-block-height duration),
            claimed: u0,
            paused: false,
            paused-at-block: u0,
            total-paused-blocks: u0,
        })
        (var-set treasury-balance (- (var-get treasury-balance) amount))
        (ok true)
    )
)

(define-read-only (get-claimable-amount (employee principal))
    (let ((stream (unwrap! (map-get? StreamingPayments employee) (ok u0))))
        (if (get paused stream)
            (ok u0)
            (let (
                    (total-blocks (- (get end-block stream) (get start-block stream)))
                    (effective-elapsed (- (- burn-block-height (get start-block stream))
                        (get total-paused-blocks stream)
                    ))
                    (stream-amount (get amount stream))
                    (already-claimed (get claimed stream))
                )
                (if (>= burn-block-height (get end-block stream))
                    (ok (- stream-amount already-claimed))
                    (ok (- (/ (* stream-amount effective-elapsed) total-blocks)
                        already-claimed
                    ))
                )
            )
        )
    )
)

(define-public (claim-stream)
    (let (
            (employee tx-sender)
            (stream (unwrap! (map-get? StreamingPayments employee) ERR-NO-EMPLOYEE))
            (claimable-amount (unwrap! (get-claimable-amount employee) ERR-INVALID-AMOUNT))
        )
        (asserts! (not (get paused stream)) ERR-STREAM-PAUSED)
        (asserts! (> claimable-amount u0) ERR-INVALID-AMOUNT)
        (map-set StreamingPayments employee
            (merge stream { claimed: (+ (get claimed stream) claimable-amount) })
        )
        (ok claimable-amount)
    )
)

(define-public (end-stream (employee principal))
    (begin
        (asserts! (is-eq tx-sender (var-get contract-owner)) ERR-NOT-AUTHORIZED)
        (asserts! (is-some (map-get? StreamingPayments employee)) ERR-NO-EMPLOYEE)
        (map-delete StreamingPayments employee)
        (ok true)
    )
)

(define-read-only (get-employee-info (employee principal))
    (ok (unwrap! (map-get? Employees employee) ERR-NO-EMPLOYEE))
)

(define-read-only (get-stream-info (employee principal))
    (ok (unwrap! (map-get? StreamingPayments employee) ERR-NO-EMPLOYEE))
)

(define-public (pause-stream (employee principal))
    (begin
        (asserts! (is-eq tx-sender (var-get contract-owner)) ERR-NOT-AUTHORIZED)
        (let ((stream (unwrap! (map-get? StreamingPayments employee) ERR-NO-EMPLOYEE)))
            (asserts! (not (get paused stream)) ERR-STREAM-PAUSED)
            (map-set StreamingPayments employee
                (merge stream {
                    paused: true,
                    paused-at-block: burn-block-height,
                })
            )
            (ok true)
        )
    )
)

(define-public (resume-stream (employee principal))
    (begin
        (asserts! (is-eq tx-sender (var-get contract-owner)) ERR-NOT-AUTHORIZED)
        (let ((stream (unwrap! (map-get? StreamingPayments employee) ERR-NO-EMPLOYEE)))
            (asserts! (get paused stream) ERR-STREAM-NOT-PAUSED)
            (let ((paused-duration (- burn-block-height (get paused-at-block stream))))
                (map-set StreamingPayments employee
                    (merge stream {
                        paused: false,
                        paused-at-block: u0,
                        total-paused-blocks: (+ (get total-paused-blocks stream) paused-duration),
                    })
                )
                (ok true)
            )
        )
    )
)

(define-read-only (get-treasury-balance)
    (ok (var-get treasury-balance))
)

(define-public (set-performance-rating
        (employee principal)
        (rating uint)
        (period-start uint)
        (period-end uint)
    )
    (begin
        (asserts! (is-eq tx-sender (var-get contract-owner)) ERR-NOT-AUTHORIZED)
        (asserts! (is-some (map-get? Employees employee)) ERR-NO-EMPLOYEE)
        (asserts! (and (>= rating u1) (<= rating u10))
            ERR-INVALID-PERFORMANCE-RATING
        )
        (asserts! (< period-start period-end) ERR-INVALID-AMOUNT)
        (let ((bonus-multiplier (if (<= rating u3)
                u50
                (if (<= rating u6)
                    u100
                    (if (<= rating u8)
                        u150
                        u200
                    )
                )
            )))
            (map-set PerformanceRatings employee {
                rating: rating,
                bonus-multiplier: bonus-multiplier,
                evaluation-period-start: period-start,
                evaluation-period-end: period-end,
                bonus-claimed: false,
            })
            (ok bonus-multiplier)
        )
    )
)

(define-read-only (calculate-performance-bonus (employee principal))
    (let (
            (employee-info (unwrap! (map-get? Employees employee) ERR-NO-EMPLOYEE))
            (performance (unwrap! (map-get? PerformanceRatings employee)
                ERR-NO-PERFORMANCE-RATING
            ))
            (evaluation-blocks (- (get evaluation-period-end performance)
                (get evaluation-period-start performance)
            ))
            (hourly-rate (get hourly-rate employee-info))
            (bonus-multiplier (get bonus-multiplier performance))
        )
        (if (get bonus-claimed performance)
            (ok u0)
            (let ((base-earnings (/ (* hourly-rate evaluation-blocks) u144)))
                (ok (/ (* base-earnings bonus-multiplier) u100))
            )
        )
    )
)

(define-public (claim-performance-bonus)
    (let (
            (employee tx-sender)
            (performance (unwrap! (map-get? PerformanceRatings employee)
                ERR-NO-PERFORMANCE-RATING
            ))
            (bonus-amount (unwrap! (calculate-performance-bonus employee) ERR-INVALID-AMOUNT))
        )
        (asserts! (>= burn-block-height (get evaluation-period-end performance))
            ERR-INVALID-AMOUNT
        )
        (asserts! (not (get bonus-claimed performance)) ERR-INVALID-AMOUNT)
        (asserts! (> bonus-amount u0) ERR-INVALID-AMOUNT)
        (asserts! (>= (var-get treasury-balance) bonus-amount)
            ERR-INSUFFICIENT-BALANCE
        )
        (map-set PerformanceRatings employee
            (merge performance { bonus-claimed: true })
        )
        (var-set treasury-balance (- (var-get treasury-balance) bonus-amount))
        (ok bonus-amount)
    )
)

(define-read-only (get-performance-rating (employee principal))
    (ok (unwrap! (map-get? PerformanceRatings employee) ERR-NO-PERFORMANCE-RATING))
)
