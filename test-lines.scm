;; transformation matrix
(define m11 64) (define m12 0)  (define m13 0)
(define m21 0)  (define m22 64) (define m23 0)

(define (main)
  (set-video-mode W H)

  (define speed 4)
  (define angle 0)

  (while 1
    (fill-rect 15 0 0 W H)

    (define i 0)
    (while (<= i 255)
      (make-rotation-matrix (+ angle (* 256 i)))
      (set! m13 (>> W 1))
      (set! m23 (>> H 1))
      (line i 0 0 40 0)
      (line i 70 0 110 0)
      (set! i (+ i 1)))
    (pause-frames 1)

    (set! angle (+ angle 256))))

(define (make-rotation-matrix angle)
  ;; the sin function returns -16384..16384, so we need to shift down quite a bit to reach the desired scale of +/- 64
  ;; as for the input, 32768 ~ pi (with wrap-around working naturally)
  (define the-sin (>> (sin angle) 8))
  (define the-cos (>> (sin (+ angle 16384)) 8))

  ;; rotation matrix is:
  ;;   [cos -sin  0]
  ;;   [sin  cos  0]
  ;; TODO: coordinate system to be reviewed
  (set! m11 the-cos)
  (set! m12 (- 0 the-sin))
  (set! m13 0)
  (set! m21 the-sin)
  (set! m22 the-cos)
  (set! m23 0))

;; draw a transformed line;
;; if coords are +/- 512
;; matrix values must be max +/- 64
;; and we shift 6 bits down
(define (line color x1 y1 x2 y2)
  (draw-line color
    (+ (>> (+ (* m11 x1) (* m12 y1)) 6) m13) (+ (>> (+ (* m21 x1) (* m22 y1)) 6) m23)
    (+ (>> (+ (* m11 x2) (* m12 y2)) 6) m13) (+ (>> (+ (* m21 x2) (* m22 y2)) 6) m23)))
