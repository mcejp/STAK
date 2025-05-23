(define COLOR:BG 0x68)

;; game state
(define T-PLAYER-1 0)
(define T-PLAYER-2 1)
(define round 1)
(define turn 0)
(define score-plr1 0)
(define score-plr2 0)

; note: gorilla origin is between feet
(define x-plr1  53) (define y-plr1 100) (define aim-dir-plr1 32)
(define x-plr2 267) (define y-plr2 100) (define aim-dir-plr2 32)

(define x-bull@ 0)
(define y-bull@ 0)

;; buildings
(define NUM-BLDGS 5)
(define bldg-w-0 0) (define bldg-w-1 0) (define bldg-w-2 0) (define bldg-w-3 0) (define bldg-w-4 0)
(define bldg-h-0 0) (define bldg-h-1 0) (define bldg-h-2 0) (define bldg-h-3 0) (define bldg-h-4 0)

;; draw state
(define GORILLA:EXCITED 0)
(define GORILLA:UNAMUSED 1)
(define GORILLA:SAD 2)

(define d-color COLOR:BLACK)
(define d-x 0)  ; draw offset
(define d-y 0)
(define d-x-scale 1)  ; applies only to quads!

;;; game logic

(define (main)
  (while 1
    (play-round)
    ;; game over?
    (when (= score-plr1 3)
      (animate-close-in x-plr1 y-plr1)
      (set! score-plr1 0)
      (set! score-plr2 0))
    (when (= score-plr2 3)
      (animate-close-in x-plr2 y-plr2)
      (set! score-plr1 0)
      (set! score-plr2 0))))

(define (play-round)
  ;; init buildings
  (set-random-seed! round)
  (set! round (+ round 1))

  ;; W/5 = 64
  ;; building centers at 64, 128, 192, 256
  (dotimes (j NUM-BLDGS)
    (define player? (or (= j 0) (= j (sub1 NUM-BLDGS))))

    ;; height is in pixels, width is in number of windows
    ;; taller buildings in the middle makes for more interesting gameplay
    (define MIN-H MAX-H (cond player? (values 50 60)
                                    1 (values 70 130)))
    (define MIN-W MAX-W (values 3 7))

    (define w (+ MIN-W (% (random) (- MAX-W MIN-W))))
    (set! w (+ 2 (* w 8)))
    (define h (+ MIN-H (% (random) (- MAX-H MIN-H))))

    (set-bldg-size! j w h))

  (set! y-plr1 (add1 (- H (get-bldg-h 0))))
  (set! y-plr2 (add1 (- H (get-bldg-h (- NUM-BLDGS 1)))))
  (set! aim-dir-plr1 24)
  (set! aim-dir-plr2 24)

  (draw-background)
  (draw-score)

  (define opponent-hit? 0)

  (while (not opponent-hit?)
    ;; draw gorillas
    (set! d-x x-plr1)
    (set! d-y y-plr1)
    (set! d-x-scale 1)
    (set! d-color COLOR:GREEN)
    (gorilla (cond (= turn T-PLAYER-1) GORILLA:EXCITED 1 GORILLA:UNAMUSED))

    (set! d-x x-plr2)
    (set! d-y y-plr2)
    (set! d-x-scale -1)
    (set! d-color COLOR:LIGHTRED)
    (gorilla (cond (= turn T-PLAYER-2) GORILLA:EXCITED 1 GORILLA:UNAMUSED))

    ;; load current player's x, y and aim direction + other player's x, y & color
    (define xx yy xx* yy* aim-dir x-scale color* (cond
      (= turn T-PLAYER-1) (values x-plr1 y-plr1 x-plr2 y-plr2 aim-dir-plr1  1 COLOR:LIGHTRED)
                        1 (values x-plr2 y-plr2 x-plr1 y-plr1 aim-dir-plr2 -1 COLOR:GREEN)))

    (define SHOOT-OFS-X (* x-scale -12))
    (define SHOOT-OFS-Y -35)

    ;; erase crosshairs
    (set! d-x (+ xx SHOOT-OFS-X))
    (set! d-y (+ yy SHOOT-OFS-Y))
    (set! d-color COLOR:BG)
    (draw-crosshairs aim-dir x-scale)

    ;; shooting
    (cond (key-held? KEY:CTRL) (do
      ;; initialize "bullet" (banana)
      (set! x-bull@ (from-int@ (+ xx SHOOT-OFS-X)))
      (set! y-bull@ (from-int@ (+ yy SHOOT-OFS-Y)))

      (define speed 5)
      (define vx-bull@   (* (* (cos@ aim-dir) speed) x-scale))
      (define vy-bull@ (- 0 (* (sin@ aim-dir) speed)))

      (set! x-bull@ (+ x-bull@ vx-bull@))
      (set! y-bull@ (+ y-bull@ vy-bull@))

      (define angle-bull (+ 128 (* 64 x-scale)))

      (define bldg-hit? 0)

      ;; trace bullet until it hits something or goes off screen
      (while (and (> x-bull@ -50)
             (and (<= (to-int y-bull@) H)
             (and (<= (to-int x-bull@) W)
             (and (not opponent-hit?)
                  (not bldg-hit?)))))
        ;; draw spinning banana
        (set! d-color 0x44)
        (draw-banana x-bull@ y-bull@ angle-bull)
        ;; display
        (pause-frames 1)
        ;; erase bullet
        (set! d-color COLOR:BG)
        (draw-banana x-bull@ y-bull@ angle-bull)
        ;; bullet physics
        (set! x-bull@ (+ x-bull@ vx-bull@))
        (set! y-bull@ (+ y-bull@ vy-bull@))
        (set! vy-bull@ (+ vy-bull@ 6))
        (set! angle-bull (+ angle-bull (* 16 x-scale)))

        ;; test for hit of opponent
        (when (and (>= x-bull@ (from-int@ (- xx* 12)))
              (and (<= x-bull@ (from-int@ (+ xx* 12)))
              (and (>= y-bull@ (from-int@ (- yy* 30)))
                   (<= y-bull@ (from-int@ (- yy* 5))))))
          ;; it's a hit!
          (set! opponent-hit? 1)
          (set! d-color COLOR:LIGHTRED)
          (draw-banana x-bull@ y-bull@ angle-bull)
          (animate-damage xx* yy* (- 0 x-scale) color*)

          ;; update score
          (cond (= turn T-PLAYER-1) (set! score-plr1 (add1 score-plr1))
                                  1 (set! score-plr2 (add1 score-plr2)))
          (draw-score))

        ;; test for collision with environment
        (set! bldg-hit? (building-hit?)))

      ;; switch turns
      (set! turn (cond
        (= turn T-PLAYER-1) T-PLAYER-2
                          1 T-PLAYER-1)))
    ;; else - CTRL *not* pressed
    1 (do
      (cond (key-held? KEY:UP)    (set! aim-dir (+ aim-dir 1))
            (key-held? KEY:DOWN)  (set! aim-dir (- aim-dir 1)))

      (set! d-color COLOR:WHITE)
      (set! d-x (+ xx SHOOT-OFS-X))
      (set! d-y (+ yy SHOOT-OFS-Y))
      (draw-crosshairs aim-dir x-scale)

      (cond (= turn T-PLAYER-1) (set! aim-dir-plr1 aim-dir)
            (= turn T-PLAYER-2) (set! aim-dir-plr2 aim-dir)))
      ;; end of big cond
      )

    ;; refresh screen before looping
    (pause-frames 1)
    ;; end of gameplay loop
    )
  )

;;; data functions

(define (get-bldg-pos-&-size n)
  (define w h (cond
    (= n 0) (values bldg-w-0 bldg-h-0)
    (= n 1) (values bldg-w-1 bldg-h-1)
    (= n 2) (values bldg-w-2 bldg-h-2)
    (= n 3) (values bldg-w-3 bldg-h-3)
          1 (values bldg-w-4 bldg-h-4)))
  ;; W/6 * (1 + i) - w/2
  (define x (- (* (/ W 6) (+ 1 n))
                (>> w 1)))
  (values x (- H h) w h))

(define (get-bldg-h n)
  (cond (= n 0) bldg-h-0
        (= n 1) bldg-h-1
        (= n 2) bldg-h-2
        (= n 3) bldg-h-3
              1 bldg-h-4))

(define (set-bldg-size! n w h)
  (cond (= n 0) (do (set! bldg-w-0 w) (set! bldg-h-0 h))
        (= n 1) (do (set! bldg-w-1 w) (set! bldg-h-1 h))
        (= n 2) (do (set! bldg-w-2 w) (set! bldg-h-2 h))
        (= n 3) (do (set! bldg-w-3 w) (set! bldg-h-3 h))
              1 (do (set! bldg-w-4 w) (set! bldg-h-4 h))))

(define (building-hit?)
  (set-random-seed! 0)

  (define hit? 0)
  (dotimes (i NUM-BLDGS)
    (define x y w h (get-bldg-pos-&-size i))

    ;; check if bullet collides with building
    (when (and (>= x-bull@ (from-int@ x))
          (and (<= x-bull@ (from-int@ (+ x w)))
          (and (>= y-bull@ (from-int@ (- H h)))
               (<= y-bull@ (from-int@ H)))))
      ; chip the building
      (set! d-color COLOR:BG)
      (fill-rect d-color (- (to-int x-bull@) 2) (- (to-int y-bull@) 2) 4 4)
      (set! hit? 1)))

  hit?)

;;; drawing functions

(define (draw-background)
  ;; background with stars
  (fill-rect COLOR:BG 0 0 W H)
  (dotimes (i 70)
    (fill-rect COLOR:YELLOW (% (random) W) (% (random) H) 1 1))

  ;; skyline
  (dotimes (j 9)
    (define color (cond
      (% j 2) 0x14
            1 0x15))
    (define MIN-H MAX-H (values (/ H 6) (/ H 4)))
    (define h* (+ MIN-H (% (random) (- MAX-H MIN-H))))
    (fill-rect color
               (/ (* W j) 9)
               (- H h*)
               (/ W 9)
               h*))

  ;; buildings
  (set-random-seed! 0)

  (dotimes (k NUM-BLDGS)
    (define x y w h (get-bldg-pos-&-size k))

    ;; random pastel color
    (set! color (+ 56 (% (random) 16)))
    (fill-rect color x y w h)

    ;; windows
    (dotimes (xx (/ w 8))
      (dotimes (yy (/ h 8))
        (set! color (cond (% (random) 2) 0x41
                                       1 0x44))
        (fill-rect color
                  (+ (+ x 3) (* xx 8))
                  (+ (+ y 3) (* yy 8))
                  4 4)))))

(define (line* x1 y1 x2 y2)
  (draw-line d-color
    (+ d-x x1) (+ d-y y1)
    (+ d-x x2) (+ d-y y2)))

(define (tri* x1 y1 x2 y2 x3 y3)
  (fill-triangle d-color
    (+ d-x x1) (+ d-y y1)
    (+ d-x x2) (+ d-y y2)
    (+ d-x x3) (+ d-y y3)))

;; draw a quadliteral
;; coordinates can be in clockwise or counter-clockwise order
(define (quad* x1 y1 x2 y2 x3 y3 x4 y4)
  (set! x1 (* d-x-scale x1))
  (set! x2 (* d-x-scale x2))
  (set! x3 (* d-x-scale x3))
  (set! x4 (* d-x-scale x4))

  (tri* x1 y1 x2 y2 x4 y4)
  (tri* x2 y2 x3 y3 x4 y4))

(define (rect* x y w h)
  (fill-rect d-color (+ d-x x) (+ d-y y) w h))

(define (gorilla expression)
  ;; Draw a gorilla using the current color.
  ;; Drawing is transposed so that 0,0 falls in between the gorilla's feet.

  ;; left foot
  (rect* -9 -6 5 5)
  ;; right foot
  (rect* 4 -6 5 5)
  ;; left leg
  (quad* -9 -6 -3 -6 0 -10 -5 -12)
  ;; right leg
  (quad*  9 -6  4 -6  0 -10 5 -12)
  ;; torso
  (rect* -6 -23 12 13)
  ;; left shoulder
  (tri* -6 -24 -9 -21 -6 -18)
  ;; left arm
  (quad* -6  -17 -6 -23 -9 -26 -15 -26)
  (quad* -15 -26 -9 -26 -6 -29  -9 -32)
  ;; right arm
  (quad* 6  -24 6 -18 9 -15 15 -15)
  (quad* 15 -15 9 -15 6 -12  9  -9)

  ;; head
  (rect* -3 -32 6 9)
  (rect* -6 -29 12 3)
  (tri* -3 -32 -6 -29 -3 -29)
  (tri* -3 -23 -6 -26 -3 -26)
  (tri* 3 -32 6 -29 3 -29)
  (tri* 3 -23 6 -26 3 -26)

  ;; face
  (define old-d-color d-color)
  (set! d-color COLOR:WHITE)
  (cond
    (= expression GORILLA:EXCITED) (do
      (rect* -4 -30 2 2)
      (rect* 1 -30 2 2)
      (tri* -3 -26 2 -26 0 -24))
    (= expression GORILLA:UNAMUSED) (do
      (rect* -4 -30 2 2)
      (rect* 1 -30 2 2)
      (rect* -2 -26 3 1))
    (= expression GORILLA:SAD) (do
      (rect* -4 -29 2 1)
      (rect* 1 -29 2 1)
      (tri* -3 -24 2 -24 0 -26)))

  (set! d-color old-d-color))

(define (draw-crosshairs aim-dir x-scale)
  ;; draw crosshairs
  ;; call this with d-x, d-y set to shooting origin
  ;;
  ;; x = len * cos(angle)
  (define the-sin@ (sin@ aim-dir))
  (define the-cos@ (cos@ aim-dir))
  (define x-cross      (>> (* 30 the-cos@) 6))
  (define y-cross (- 0 (>> (* 30 the-sin@) 6)))

  (set! x-cross (* x-cross x-scale))

  (define l1 6)
  (define l2 10)

  ;; draw banana + crosshairs
  ;; banana is drawn in world space + uses fractional coordinates, so we need to convert from local space
  (draw-banana (from-int@ d-x)
               (from-int@ d-y)
               (+ 128 (* 64 x-scale)))

  (line* x-cross        (+ y-cross l1) x-cross      (+ y-cross l2))
  (line* x-cross        (- y-cross l1) x-cross      (- y-cross l2))
  (line* (+ x-cross l1) y-cross       (+ x-cross l2) y-cross)
  (line* (- x-cross l1) y-cross       (- x-cross l2) y-cross)
)

(define (draw-banana x@ y@ angle)
  ;; use sin@ & cos@ to prepare a rotation matrix
  (define m11@ (cos@ angle))
  (define m12@ (- 0 (sin@ angle)))
  (define m21@ (sin@ angle))
  (define m22@ (cos@ angle))

  ;; save d-x, d-y and set up our own at centre of banana
  (define old-d-x d-x)
  (define old-d-y d-y)
  (set! d-x (to-int x@))
  (set! d-y (to-int y@))

  (line* (>> (+ (* -6 m11@) (* 4 m12@)) 6) (>> (+ (* -6 m21@) (* 4 m22@)) 6)
         (>> (+ (* -2 m11@) (* 0 m12@)) 6) (>> (+ (* -2 m21@) (* 0 m22@)) 6))
  (line* (>> (+ (* -2 m11@) (* 0 m12@)) 6) (>> (+ (* -2 m21@) (* 0 m22@)) 6)
         (>> (+ (*  2 m11@) (* 0 m12@)) 6) (>> (+ (*  2 m21@) (* 0 m22@)) 6))
  (line* (>> (+ (* -3 m11@) (* 1 m12@)) 6) (>> (+ (* -3 m21@) (* 1 m22@)) 6)
         (>> (+ (*  3 m11@) (* 1 m12@)) 6) (>> (+ (*  3 m21@) (* 1 m22@)) 6))
  (line* (>> (+ (*  2 m11@) (* 0 m12@)) 6) (>> (+ (*  2 m21@) (* 0 m22@)) 6)
         (>> (+ (*  6 m11@) (* 4 m12@)) 6) (>> (+ (*  6 m21@) (* 4 m22@)) 6))

  ;; restore d-x, d-y
  (set! d-x old-d-x)
  (set! d-y old-d-y))

(define (draw-digit score)
  ;; clear background behind
  (fill-rect COLOR:BG d-x d-y 6 11)
  ;; draw digit
  (cond
    (= score 0) (do
      (line* 0 0 0 10)
      (line* 0 0 5 0)
      (line* 5 0 5 10)
      (line* 0 10 5 10))
    (= score 1) (do
      (line* 2 0 2 10))
    (= score 2) (do
      (line* 0 0 5 0)
      (line* 5 0 5 5)
      (line* 5 5 0 5)
      (line* 0 5 0 10)
      (line* 0 10 5 10))
    (= score 3) (do
      (line* 0 0 5 0)
      (line* 5 0 5 10)
      (line* 0 5 5 5)
      (line* 0 10 5 10))))

(define (draw-score)
  (set! d-color COLOR:WHITE)
  (set! d-x 5)
  (set! d-y 5)
  (draw-digit score-plr1)
  (set! d-x (- W 15))
  (set! d-y 5)
  (draw-digit score-plr2))

;;; animation sequences

(define (animate-damage x y x-scale color)
  ;; flash gorilla, alternating between normal color and background
  (dotimes (i 3)
    (set! d-x x)
    (set! d-y y)
    (set! d-x-scale x-scale)

    (set! d-color COLOR:BG)
    (gorilla GORILLA:SAD)
    (pause-frames 8)

    (set! d-color color)
    (gorilla GORILLA:SAD)
    (pause-frames 8))
)

(define (animate-close-in x-plr y-plr)
  (define WINDOW-W WINDOW-H (values 40 40))

  (set! y-plr (- y-plr 15))

  (define end-w1      (- x-plr (>> WINDOW-W 1)))
  (define end-w2 (- W (+ x-plr (>> WINDOW-W 1))))
  (define end-h1      (- y-plr (>> WINDOW-H 1)))
  (define end-h2 (- H (+ y-plr (>> WINDOW-H 1))))

  (dotimes (i 64)
    (define w1 w2 (values (to-int (* i end-w1)) (to-int (* i end-w2))))
    (define h1 h2 (values (to-int (* i end-h1)) (to-int (* i end-h2))))
    (fill-rect COLOR:BLACK 0 0 w1 H)
    (fill-rect COLOR:BLACK (- W w2) 0 w2 H)
    (define window-w (- W (+ w1 w2)))
    (fill-rect COLOR:BLACK w1        0 window-w h1)
    (fill-rect COLOR:BLACK w1 (- H h2) window-w h2)
    (draw-score)
    (pause-frames 1))
  (pause-frames 120))
