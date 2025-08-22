;; Consensus Forge - Advanced Governance Protocol with Enhanced Security and Validation

;; Define constants
(define-constant PROTOCOL_GUARDIAN tx-sender)
(define-constant ERR_UNAUTHORIZED_ACCESS (err u100))
(define-constant ERR_DUPLICATE_PARTICIPATION (err u101))
(define-constant ERR_INVALID_INITIATIVE (err u102))
(define-constant ERR_DELIBERATION_EXPIRED (err u103))
(define-constant ERR_MALFORMED_INPUT (err u104))
(define-constant ERR_INITIATIVE_NOT_FOUND (err u105))
(define-constant ERR_DELIBERATION_WINDOW_EXCEEDED (err u106))
(define-constant MAX_DELIBERATION_SPAN u2592000) ;; 30 days in seconds
(define-constant MIN_DELIBERATION_SPAN u86400) ;; 1 day in seconds

;; Define data maps
(define-map governance-initiatives
  { initiative-id: uint }
  { 
    initiative-title: (string-ascii 50), 
    initiative-summary: (string-ascii 500), 
    consensus-tally: uint, 
    is-active-deliberation: bool,
    initiative-author: principal,
    genesis-block: uint,
    deliberation-span: uint
  }
)

(define-map participant-records
  { participant: principal, initiative-id: uint }
  { 
    has-participated: bool,
    participation-block: uint
  }
)

;; Define data variables
(define-data-var total-initiatives uint u0)
(define-data-var standard-deliberation-span uint u604800) ;; 7 days in seconds

;; Private functions
;; Validate initiative input parameters
(define-private (validate-initiative-parameters (title (string-ascii 50)) (summary (string-ascii 500)))
  (and 
    (> (len title) u0) 
    (<= (len title) u50)
    (> (len summary) u0)
    (<= (len summary) u500)
  )
)

;; Validate initiative identifier
(define-private (validate-initiative-identifier (initiative-id uint))
  (and 
    (> initiative-id u0)
    (<= initiative-id (var-get total-initiatives))
  )
)

;; Check if an initiative exists and is still within deliberation period
(define-private (is-deliberation-active (initiative-id uint))
  (match (map-get? governance-initiatives { initiative-id: initiative-id })
    initiative 
      (and 
        (get is-active-deliberation initiative)
        (< block-height (+ (get genesis-block initiative) (get deliberation-span initiative)))
      )
    false
  )
)

;; Validate deliberation timeframe
(define-private (validate-deliberation-timeframe (timeframe uint))
  (and (>= timeframe MIN_DELIBERATION_SPAN) (<= timeframe MAX_DELIBERATION_SPAN))
)

;; Public functions
;; Create a new governance initiative with optional custom deliberation period
(define-public (forge-initiative 
  (title (string-ascii 50)) 
  (summary (string-ascii 500))
  (custom-timeframe (optional uint))
)
  (let (
    (new-initiative-id (+ (var-get total-initiatives) u1))
    (deliberation-timeframe (default-to (var-get standard-deliberation-span) custom-timeframe))
  )
    ;; Validate sender is protocol guardian
    (asserts! (is-eq tx-sender PROTOCOL_GUARDIAN) ERR_UNAUTHORIZED_ACCESS)
    
    ;; Validate initiative parameters
    (asserts! (validate-initiative-parameters title summary) ERR_MALFORMED_INPUT)
    
    ;; Validate deliberation timeframe
    (asserts! (validate-deliberation-timeframe deliberation-timeframe) ERR_MALFORMED_INPUT)
    
    ;; Create initiative with comprehensive metadata
    (map-set governance-initiatives
      { initiative-id: new-initiative-id }
      { 
        initiative-title: title, 
        initiative-summary: summary, 
        consensus-tally: u0, 
        is-active-deliberation: true,
        initiative-author: tx-sender,
        genesis-block: block-height,
        deliberation-span: deliberation-timeframe
      }
    )
    
    ;; Update initiative counter
    (var-set total-initiatives new-initiative-id)
    
    (ok new-initiative-id)
  )
)

;; Cast consensus signal on an initiative
(define-public (signal-consensus (initiative-id uint))
  (let (
    (initiative (unwrap! (map-get? governance-initiatives { initiative-id: initiative-id }) ERR_INVALID_INITIATIVE))
    (has-signaled (default-to false (get has-participated (map-get? participant-records { participant: tx-sender, initiative-id: initiative-id }))))
  )
    ;; Validate initiative identifier
    (asserts! (validate-initiative-identifier initiative-id) ERR_INVALID_INITIATIVE)
    
    ;; Validate initiative is active and within deliberation window
    (asserts! (is-deliberation-active initiative-id) ERR_DELIBERATION_EXPIRED)
    
    ;; Prevent duplicate participation
    (asserts! (not has-signaled) ERR_DUPLICATE_PARTICIPATION)
    
    ;; Record participation
    (map-set participant-records 
      { participant: tx-sender, initiative-id: initiative-id } 
      { 
        has-participated: true,
        participation-block: block-height 
      }
    )
    
    ;; Update initiative consensus tally
    (map-set governance-initiatives
      { initiative-id: initiative-id }
      (merge initiative { consensus-tally: (+ (get consensus-tally initiative) u1) })
    )
    
    (ok true)
  )
)

;; Terminate an initiative manually (can only be done by protocol guardian)
(define-public (terminate-initiative (initiative-id uint))
  (let (
    (initiative (unwrap! (map-get? governance-initiatives { initiative-id: initiative-id }) ERR_INITIATIVE_NOT_FOUND))
  )
    ;; Validate initiative identifier
    (asserts! (validate-initiative-identifier initiative-id) ERR_INVALID_INITIATIVE)
    
    ;; Validate sender is protocol guardian
    (asserts! (is-eq tx-sender PROTOCOL_GUARDIAN) ERR_UNAUTHORIZED_ACCESS)
    
    ;; Terminate the initiative
    (ok (map-set governance-initiatives
      { initiative-id: initiative-id }
      (merge initiative { is-active-deliberation: false })
    ))
  )
)

;; Update standard deliberation timeframe (only by protocol guardian)
(define-public (configure-deliberation-timeframe (timeframe uint))
  (begin
    ;; Validate sender is protocol guardian
    (asserts! (is-eq tx-sender PROTOCOL_GUARDIAN) ERR_UNAUTHORIZED_ACCESS)
    
    ;; Validate timeframe is within acceptable bounds
    (asserts! (validate-deliberation-timeframe timeframe) ERR_MALFORMED_INPUT)
    
    ;; Set new standard timeframe
    (var-set standard-deliberation-span timeframe)
    (ok true)
  )
)

;; Read-only functions
;; Get comprehensive initiative details with contextual information
(define-read-only (get-initiative-status (initiative-id uint))
  (let ((initiative (map-get? governance-initiatives { initiative-id: initiative-id })))
    ;; Validate initiative identifier before processing
    (if (validate-initiative-identifier initiative-id)
        (if (is-some initiative)
            (some {
              initiative-data: initiative,
              is-deliberation-active: (is-deliberation-active initiative-id),
              remaining-blocks: (match initiative
                i (- (+ (get genesis-block i) (get deliberation-span i)) block-height)
                u0)
            })
            none
        )
        none
    )
  )
)

;; Get the total number of governance initiatives
(define-read-only (get-total-initiatives)
  (var-get total-initiatives)
)

;; Check if a participant has signaled consensus on a specific initiative
(define-read-only (has-participant-signaled (participant principal) (initiative-id uint))
  ;; Validate initiative identifier before checking participation
  (if (validate-initiative-identifier initiative-id)
      (default-to false (get has-participated (map-get? participant-records { participant: participant, initiative-id: initiative-id })))
      false
  )
)