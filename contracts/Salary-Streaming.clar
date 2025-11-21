;; Salary Streaming with Employee Leave Management System
;; A comprehensive smart contract for streaming salary payments with integrated leave management

;; Error constants for core functionality
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

;; Error constants for Leave Management System
(define-constant ERR-INVALID-LEAVE-TYPE (err u110))
(define-constant ERR-INSUFFICIENT-LEAVE-BALANCE (err u111))
(define-constant ERR-LEAVE-REQUEST-NOT-FOUND (err u112))
(define-constant ERR-LEAVE-REQUEST-ALREADY-PROCESSED (err u113))
(define-constant ERR-INVALID-LEAVE-DAYS (err u114))
(define-constant ERR-LEAVE-REQUEST-EXPIRED (err u115))
(define-constant ERR-INVALID-DATE-RANGE (err u116))
(define-constant ERR-OVERLAPPING-LEAVE-REQUEST (err u117))

;; Leave type constants
(define-constant LEAVE-TYPE-VACATION u1)
(define-constant LEAVE-TYPE-SICK u2)
(define-constant LEAVE-TYPE-PERSONAL u3)

;; Leave accrual rates (hours per year)
(define-constant VACATION-ACCRUAL-RATE u120) ;; 15 days * 8 hours = 120 hours
(define-constant SICK-ACCRUAL-RATE u80)      ;; 10 days * 8 hours = 80 hours
(define-constant PERSONAL-ACCRUAL-RATE u40)  ;; 5 days * 8 hours = 40 hours

;; Contract variables
(define-data-var contract-owner principal tx-sender)
(define-data-var treasury-balance uint u0)
(define-data-var next-leave-request-id uint u1)

;; Core employee data structure
(define-map Employees
    principal
    {
        hourly-rate: uint,
        last-stream: uint,
        total-earned: uint,
        active: bool,
        start-date: uint,
        last-leave-accrual: uint,
    }
)

;; Streaming payment data structure
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

;; Performance rating data structure
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

;; Leave Management Data Structures

;; Employee leave balances by type
(define-map LeaveBalances
    { employee: principal, leave-type: uint }
    {
        available-hours: uint,
        used-hours: uint,
        accrued-hours: uint,
        last-updated: uint,
    }
)

;; Leave request tracking
(define-map LeaveRequests
    uint ;; request-id
    {
        employee: principal,
        leave-type: uint,
        start-date: uint,
        end-date: uint,
        hours-requested: uint,
        status: uint, ;; 0=pending, 1=approved, 2=denied
        requested-at: uint,
        processed-at: uint,
        processed-by: (optional principal),
        reason: (string-ascii 200),
    }
)

;; Employee leave request history for efficient lookup
(define-map EmployeeLeaveRequests
    principal
    { request-ids: (list 100 uint) }
)

;; ====================
;; CORE FUNCTIONS
;; ====================

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
        (asserts! (is-none (map-get? Employees employee-address)) ERR-EMPLOYEE-EXISTS)
        (map-set Employees employee-address {
            hourly-rate: rate,
            last-stream: burn-block-height,
            total-earned: u0,
            active: true,
            start-date: burn-block-height,
            last-leave-accrual: burn-block-height,
        })
        ;; Initialize leave balances for new employee
        (try! (initialize-leave-balances employee-address))
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
        (asserts! (is-none (map-get? StreamingPayments employee)) ERR-STREAM-ACTIVE)
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

;; ====================
;; PERFORMANCE MANAGEMENT
;; ====================

(define-public (set-performance-rating
        (employee principal)
        (rating uint)
        (period-start uint)
        (period-end uint)
    )
    (begin
        (asserts! (is-eq tx-sender (var-get contract-owner)) ERR-NOT-AUTHORIZED)
        (asserts! (is-some (map-get? Employees employee)) ERR-NO-EMPLOYEE)
        (asserts! (and (>= rating u1) (<= rating u10)) ERR-INVALID-PERFORMANCE-RATING)
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
            (performance (unwrap! (map-get? PerformanceRatings employee) ERR-NO-PERFORMANCE-RATING))
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
            (performance (unwrap! (map-get? PerformanceRatings employee) ERR-NO-PERFORMANCE-RATING))
            (bonus-amount (unwrap! (calculate-performance-bonus employee) ERR-INVALID-AMOUNT))
        )
        (asserts! (>= burn-block-height (get evaluation-period-end performance)) ERR-INVALID-AMOUNT)
        (asserts! (not (get bonus-claimed performance)) ERR-INVALID-AMOUNT)
        (asserts! (> bonus-amount u0) ERR-INVALID-AMOUNT)
        (asserts! (>= (var-get treasury-balance) bonus-amount) ERR-INSUFFICIENT-BALANCE)
        (map-set PerformanceRatings employee
            (merge performance { bonus-claimed: true })
        )
        (var-set treasury-balance (- (var-get treasury-balance) bonus-amount))
        (ok bonus-amount)
    )
)

;; ====================
;; EMPLOYEE LEAVE MANAGEMENT SYSTEM
;; ====================

;; Initialize leave balances for a new employee
(define-private (initialize-leave-balances (employee principal))
    (begin
        (map-set LeaveBalances { employee: employee, leave-type: LEAVE-TYPE-VACATION } {
            available-hours: u0,
            used-hours: u0,
            accrued-hours: u0,
            last-updated: burn-block-height,
        })
        (map-set LeaveBalances { employee: employee, leave-type: LEAVE-TYPE-SICK } {
            available-hours: u0,
            used-hours: u0,
            accrued-hours: u0,
            last-updated: burn-block-height,
        })
        (map-set LeaveBalances { employee: employee, leave-type: LEAVE-TYPE-PERSONAL } {
            available-hours: u0,
            used-hours: u0,
            accrued-hours: u0,
            last-updated: burn-block-height,
        })
        (map-set EmployeeLeaveRequests employee { request-ids: (list) })
        (ok true)
    )
)

;; Accrue leave hours based on employment duration
(define-public (accrue-leave-hours (employee principal))
    (let (
            (employee-info (unwrap! (map-get? Employees employee) ERR-NO-EMPLOYEE))
            (employment-blocks (- burn-block-height (get start-date employee-info)))
            (last-accrual (get last-leave-accrual employee-info))
            (blocks-since-accrual (- burn-block-height last-accrual))
        )
        ;; Only accrue if it's been at least 2160 blocks (about 15 days)
        (if (>= blocks-since-accrual u2160)
            (begin
                ;; Calculate monthly accrual (assume 144 blocks per day, 30 days per month = 4320 blocks)
                (let ((months-employed (/ employment-blocks u4320)))
                    ;; Accrue vacation leave
                    (try! (accrue-leave-type employee LEAVE-TYPE-VACATION 
                          (/ VACATION-ACCRUAL-RATE u12))) ;; Monthly accrual
                    ;; Accrue sick leave
                    (try! (accrue-leave-type employee LEAVE-TYPE-SICK 
                          (/ SICK-ACCRUAL-RATE u12))) ;; Monthly accrual
                    ;; Accrue personal leave
                    (try! (accrue-leave-type employee LEAVE-TYPE-PERSONAL 
                          (/ PERSONAL-ACCRUAL-RATE u12))) ;; Monthly accrual
                    ;; Update last accrual time
                    (map-set Employees employee
                        (merge employee-info { last-leave-accrual: burn-block-height })
                    )
                    (ok true)
                )
            )
            (ok false) ;; Not time to accrue yet
        )
    )
)

;; Private function to accrue specific leave type
(define-private (accrue-leave-type (employee principal) (leave-type uint) (hours uint))
    (let ((balance-key { employee: employee, leave-type: leave-type }))
        (match (map-get? LeaveBalances balance-key)
            existing-balance
                (map-set LeaveBalances balance-key
                    (merge existing-balance {
                        available-hours: (+ (get available-hours existing-balance) hours),
                        accrued-hours: (+ (get accrued-hours existing-balance) hours),
                        last-updated: burn-block-height,
                    })
                )
            ;; Create new balance if it doesn't exist
            (map-set LeaveBalances balance-key {
                available-hours: hours,
                used-hours: u0,
                accrued-hours: hours,
                last-updated: burn-block-height,
            })
        )
        (ok true)
    )
)

;; Submit a leave request
(define-public (submit-leave-request 
        (leave-type uint) 
        (start-date uint) 
        (end-date uint) 
        (hours-requested uint) 
        (reason (string-ascii 200))
    )
    (let (
            (employee tx-sender)
            (request-id (var-get next-leave-request-id))
        )
        ;; Validation
        (asserts! (is-some (map-get? Employees employee)) ERR-NO-EMPLOYEE)
        (asserts! (or (is-eq leave-type LEAVE-TYPE-VACATION)
                     (or (is-eq leave-type LEAVE-TYPE-SICK)
                         (is-eq leave-type LEAVE-TYPE-PERSONAL))) ERR-INVALID-LEAVE-TYPE)
        (asserts! (< start-date end-date) ERR-INVALID-DATE-RANGE)
        (asserts! (> hours-requested u0) ERR-INVALID-LEAVE-DAYS)
        (asserts! (<= hours-requested u320) ERR-INVALID-LEAVE-DAYS) ;; Max 40 days * 8 hours
        
        ;; Check if employee has sufficient leave balance
        (let ((balance (get-leave-balance employee leave-type)))
            (asserts! (>= (get available-hours balance) hours-requested) ERR-INSUFFICIENT-LEAVE-BALANCE)
        )
        
        ;; Check for overlapping requests (basic check)
        (asserts! (not (has-overlapping-leave-request employee start-date end-date)) 
                  ERR-OVERLAPPING-LEAVE-REQUEST)
        
        ;; Create leave request
        (map-set LeaveRequests request-id {
            employee: employee,
            leave-type: leave-type,
            start-date: start-date,
            end-date: end-date,
            hours-requested: hours-requested,
            status: u0, ;; Pending
            requested-at: burn-block-height,
            processed-at: u0,
            processed-by: none,
            reason: reason,
        })
        
        ;; Add request to employee's history
        (let ((employee-requests (default-to { request-ids: (list) } 
                                             (map-get? EmployeeLeaveRequests employee))))
            (map-set EmployeeLeaveRequests employee {
                request-ids: (unwrap! (as-max-len? 
                                     (append (get request-ids employee-requests) request-id) 
                                     u100) ERR-INVALID-AMOUNT)
            })
        )
        
        ;; Increment next request ID
        (var-set next-leave-request-id (+ request-id u1))
        (ok request-id)
    )
)

;; Approve or deny a leave request (only by contract owner)
(define-public (process-leave-request (request-id uint) (approve bool))
    (let (
            (manager tx-sender)
            (request (unwrap! (map-get? LeaveRequests request-id) ERR-LEAVE-REQUEST-NOT-FOUND))
        )
        (asserts! (is-eq manager (var-get contract-owner)) ERR-NOT-AUTHORIZED)
        (asserts! (is-eq (get status request) u0) ERR-LEAVE-REQUEST-ALREADY-PROCESSED) ;; Must be pending
        
        ;; Update request status
        (map-set LeaveRequests request-id
            (merge request {
                status: (if approve u1 u2), ;; 1=approved, 2=denied
                processed-at: burn-block-height,
                processed-by: (some manager),
            })
        )
        
        ;; If approved, deduct from leave balance
        (if approve
            (let (
                    (employee (get employee request))
                    (leave-type (get leave-type request))
                    (hours (get hours-requested request))
                    (balance-key { employee: employee, leave-type: leave-type })
                )
                (match (map-get? LeaveBalances balance-key)
                    existing-balance
                        (map-set LeaveBalances balance-key
                            (merge existing-balance {
                                available-hours: (- (get available-hours existing-balance) hours),
                                used-hours: (+ (get used-hours existing-balance) hours),
                                last-updated: burn-block-height,
                            })
                        )
                    ;; This shouldn't happen if validation worked
                    false
                )
            )
            true ;; Do nothing if denied
        )
        (ok approve)
    )
)

;; Helper function to check for overlapping leave requests
(define-read-only (has-overlapping-leave-request (employee principal) (start-date uint) (end-date uint))
    (let ((employee-requests (default-to { request-ids: (list) } 
                                         (map-get? EmployeeLeaveRequests employee))))
        (fold check-request-overlap (get request-ids employee-requests) 
              { employee: employee, start: start-date, end: end-date, has-overlap: false })
        (get has-overlap)
    )
)

;; Private function for fold operation to check overlaps
(define-private (check-request-overlap 
    (request-id uint) 
    (context { employee: principal, start: uint, end: uint, has-overlap: bool })
)
    (if (get has-overlap context)
        context ;; Already found overlap, short circuit
        (match (map-get? LeaveRequests request-id)
            request
                (if (and (is-eq (get employee request) (get employee context))
                        (is-eq (get status request) u1) ;; Only check approved requests
                        (or (and (>= (get start context) (get start-date request))
                                (<= (get start context) (get end-date request)))
                            (and (>= (get end context) (get start-date request))
                                (<= (get end context) (get end-date request)))))
                    (merge context { has-overlap: true })
                    context
                )
            context ;; Request not found
        )
    )
)

;; ====================
;; READ-ONLY FUNCTIONS
;; ====================

(define-read-only (get-employee-info (employee principal))
    (ok (unwrap! (map-get? Employees employee) ERR-NO-EMPLOYEE))
)

(define-read-only (get-stream-info (employee principal))
    (ok (unwrap! (map-get? StreamingPayments employee) ERR-NO-EMPLOYEE))
)

(define-read-only (get-treasury-balance)
    (ok (var-get treasury-balance))
)

(define-read-only (get-performance-rating (employee principal))
    (ok (unwrap! (map-get? PerformanceRatings employee) ERR-NO-PERFORMANCE-RATING))
)

;; Get leave balance for an employee and leave type
(define-read-only (get-leave-balance (employee principal) (leave-type uint))
    (default-to 
        { available-hours: u0, used-hours: u0, accrued-hours: u0, last-updated: u0 }
        (map-get? LeaveBalances { employee: employee, leave-type: leave-type })
    )
)

;; Get all leave balances for an employee
(define-read-only (get-employee-leave-summary (employee principal))
    (ok {
        vacation: (get-leave-balance employee LEAVE-TYPE-VACATION),
        sick: (get-leave-balance employee LEAVE-TYPE-SICK),
        personal: (get-leave-balance employee LEAVE-TYPE-PERSONAL),
    })
)

;; Get leave request details
(define-read-only (get-leave-request (request-id uint))
    (ok (unwrap! (map-get? LeaveRequests request-id) ERR-LEAVE-REQUEST-NOT-FOUND))
)

;; Get all leave request IDs for an employee
(define-read-only (get-employee-leave-requests (employee principal))
    (ok (get request-ids 
           (default-to { request-ids: (list) } 
                       (map-get? EmployeeLeaveRequests employee))))
)

;; Get leave type name (for display purposes)
(define-read-only (get-leave-type-name (leave-type uint))
    (if (is-eq leave-type LEAVE-TYPE-VACATION)
        (ok "Vacation")
        (if (is-eq leave-type LEAVE-TYPE-SICK)
            (ok "Sick")
            (if (is-eq leave-type LEAVE-TYPE-PERSONAL)
                (ok "Personal")
                ERR-INVALID-LEAVE-TYPE
            )
        )
    )
)