(import
  atexit
  io
  json
  readline
  socket
  struct
  subprocess [Popen]
  time
  traceback

  hy.models [Expression Symbol]
  hyrule [dec parse-args]
  hyrule.hypprint [pprint]
  serial

  compile
  link)
(require
  hyrule [unless]
  hyrule.oop [meth])

(setv SEGMENT:BC 0
      SEGMENT:FUNC 1
      SEGMENT:GLOB 2)

(setv
  OP:BEGIN-EXEC (ord "x")
  OP:RESET      (ord "r")
  OP:WRITE-MEM  (ord "w"))

;; Stream-oriented transport -- need to do our own framing
(defclass StreamTransport []
  (meth send-frame [frame-bytes]
    (let [f (io.BytesIO)]
      (for [chr frame-bytes]
        (if (in chr #{0x7D 0x7E})
            (f.write (bytes [0x7D (^ chr 0x20)]))
            (f.write (bytes [chr]))))
      (f.write b"\x7E")

      (@send (f.getvalue)))))

(defclass SerialTransport [StreamTransport]
  (meth __init__ [#* args]
    (setv @ser (serial.Serial #* args)))

  (meth close []
    (@ser.close))

  (meth recvall [count]
    (@ser.read count))

  (meth send [data]
    (@ser.write data)))

(defclass SocketTransport [StreamTransport]
  (meth __init__ [address-tuple]
    (setv @sock (socket.socket socket.AF_INET socket.SOCK_STREAM))
    (@sock.connect address-tuple))

  (meth close []
    (@sock.close))

  (meth recvall [count]
    (let [f (io.BytesIO)
          received 0]
      (while (< received count)
        (f.write (@sock.recv (- count received)))
        (setv received (. f (getbuffer) nbytes)))
      (f.getvalue)))

  (meth send [data]
    (@sock.send data)))

;; Keep trying to connect for up to 3 seconds
(defn retry-connect [process address-tuple [attempts 30] [interval-sec 0.1]]
  (for [i (range attempts)]
    (try
      (when (is-not (process.poll) None)
        (raise (Exception f"Interpreter exited with code {process.returncode}")))

      (let [t (SocketTransport address-tuple)]
        (return t))

      (except [ConnectionRefusedError]
        (when (= i (dec attempts))
          (raise))
        (time.sleep interval-sec)
        (continue)))))

;; MAIN

(setv args (parse-args :spec [["-t" "--target"
                               :help "Attach to a running target (instead of starting new interpreter). Use 'tcp:<host>:<port>' or 'serial:<port>:<baudrate>'"]]))

(with [f (open "constants.json")]
  (setv builtin-constants (json.load f)))

(cond
  (is args.target None) (do
    (setv process (Popen ["./interp/interp" "-g"]))

    ;; make sure interpreter doesn't outlive us
    (atexit.register process.terminate)

    (setv t (retry-connect process #("localhost" 5000))))
  (args.target.startswith "tcp:") (do
    (let [[_ host port-str] (args.target.split ":")
          port (int port-str)]
      (setv t (SocketTransport #(host port)))))
  (args.target.startswith "serial:") (do
    (let [[_ port baud-str] (args.target.split ":")
          baud (int baud-str)]
      (try
        (setv t (SerialTransport port baud))
        (except [exc serial.SerialException]
          (print exc)
          (exit 1)))))
  :else (do
    (print "Invalid target format. See(k) help.")
    (exit 1)))

(t.send b"\x7Eh\x7E")  ;; send hello

(defn expect [expected]
  (setv reply (t.recvall (len expected)))
  ;; (print (hello.hex) (hello.decode :errors "ignore"))
  (unless (= reply expected)
    (raise (Exception f"bad reply, expected {(expected.hex " ")}, received {(reply.hex " ")}"))))

(expect b"\x7EhSTAK\x7E")

(setv program-state (link.LinkInfo :bc-end 0
                                   :function-table {}
                                   :global-table {}))

(defn eval [program execute [filename "stdin"]]
  (global program-state)

  ;; (draw-line 15 0 0 100 100) (pause-frames 1)
  ;; (for (i (range 16)) (draw-line i (* 21 i) 0 160 200))
  (setv unit (compile.compile-unit builtin-constants
                                   filename
                                   program
                                   :repl-globals (list (.keys program-state.global-table))))
  (print unit)

  ;; link

  (with [f (open "builtins.json")]
    (setv builtin-functions (json.load f)))

  (setv link-info (link.link-program [unit]
                                   :output "lnk.tmp"
                                   :builtin-functions builtin-functions
                                   :repl-initial-state program-state
                                   :allow-no-main True))
  (with [f (open "lnk.tmp" "rb")]
    ;; read header
    (setv #(bc-len num-func num-glob main-func-idx) (struct.unpack "<HBBBxxx" (f.read 8)))

    ;; functions
    (setv functions-bytes (f.read (* num-func 4)))
    ;; (for [func program.functions]
    ;;   (f.write (struct.pack "<BBHHxx" func.argc func.num-locals func.bytecode-offset func.constants-offset)))

    ;; globals
    (setv globals-bytes (f.read (* num-glob 2)))

    ;; bytecode
    (setv bc-bytes (f.read bc-len))
    )

  (defn write-memory [segment offset data]
    (t.send-frame (+ (struct.pack "<BBHH" OP:WRITE-MEM segment offset (len data)) data))
    (expect (bytes [OP:WRITE-MEM 0x7E])))

  (write-memory SEGMENT:BC    program-state.bc-end                      bc-bytes)
  (write-memory SEGMENT:FUNC  (* 4 (len program-state.function-table))  functions-bytes)
  (write-memory SEGMENT:GLOB  (* 2 (len program-state.global-table))    globals-bytes)

  (when execute
    (t.send-frame (struct.pack "<BBB" OP:BEGIN-EXEC main-func-idx 0))
    (expect (bytes [OP:BEGIN-EXEC 0x7E])))

  (let [function-table link-info.function-table]
    (when (in "main" function-table)
      ;; Make sure "main" is the last function and erase it
      ;; Length of function table is used to allocate function ids, so can't delete in the middle
      (assert (= (. function-table ["main"] id) (dec (len function-table))))
      (del (get function-table "main"))
      ;; TODO: can also trim bc-end
      ))

  (setv program-state link-info)
  (print "New program-state:" :end " ")
  (pprint program-state)
  )

(while True
  (try
    (let [inp (input ">")
          f   (io.StringIO inp)]
      ;; (print "input: " inp)
      (cond
        (= inp "reset") (do
          (t.send-frame (bytes [OP:RESET]))
          (expect (bytes [OP:RESET 0x7E]))
          (setv program-state (link.LinkInfo :bc-end 0
                                             :function-table {}
                                             :global-table {})))

        (.startswith inp "exec ") (do
          (let [filename (.removeprefix inp "exec ")]
            (with [f2 (open filename "r")]
              (setv forms (list (hy.read-many f2))))
            (eval forms :execute True :filename filename)))

        :else (do
          (setv forms (list (hy.read-many f)))

          ;; Iterate over forms. Some forms must be evaluated in global context (define), the rest are banched and evaluated in the context of a function.
          ;; (define <var> <value>) is special. It is split up into a global declaration, and the assignment of the initial value which is done in a functional context.
          ;; This way, it can be initialized with an expression, which is normally not possible (globals must be initialized with a literal)
          (setv batch [])

          (defn flush []
            (when (> (len batch) 0)
              (eval [`(define (main) ~@batch)]
                    :execute True)
              (batch.clear)))

          (for [form forms]
            (if (and (isinstance form Expression)
                    (>= (len form) 1)
                    (= (get form 0) (Symbol "define")))
                (do
                  (flush)
                  (eval [form] :execute False))
                ;; not a (define) form
                (batch.append form)
              )
            )

          (flush))))

    (except [EOFError]
      (break))
    (except [e Exception]
      (traceback.print-exc))
    )
  )

(t.close)
