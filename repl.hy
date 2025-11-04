(import
  atexit
  io
  json
  os
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
  tqdm

  compile
  link)
(require
  hyrule [unless]
  hyrule.oop [meth])

;;;
;;; Low-level debug protocol
;;;

(setv SEGMENT:BC 0
      SEGMENT:FUNC 1
      SEGMENT:GLOB 2)

(setv
  OP:BEGIN-EXEC (ord "x")
  OP:SUSPEND    (ord "s")
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
  (meth __init__ [port baud #* args]
    (setv @baud baud)
    (setv @ser (serial.Serial port baud #* args)))

  (meth close []
    (@ser.close))

  (meth recvall [count]
    (@ser.read count))

  (meth send [data]
    ;; if transmission is due to take more than a half-second, display a progress bar
    (defn tqdm-chunked [sliceable chunk-size #* args #** kwargs]
      (let [progress (tqdm.tqdm :total (len sliceable) #* args #** kwargs)]
        (for [offset (range 0 (len sliceable) chunk-size)]
          (let [chunk (cut data offset (+ offset chunk-size))]
            (yield chunk)
            (progress.update (len chunk))))))

    (if (>= (* (len data) 8) (* 0.5 @baud))
      (for [chunk (tqdm-chunked data :chunk-size 100 :desc "Transferring")]
        (@ser.write chunk))
      (@ser.write data))))

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

(defn expect [t expected]
  (setv reply (.recvall t (len expected)))
  ;; (print (hello.hex) (hello.decode :errors "ignore"))
  (unless (= reply expected)
    (raise (Exception f"bad reply, expected {(expected.hex " ")}, received {(reply.hex " ")}"))))

(defn write-memory [t segment offset data]
  (when (> (len data) 0)
    (.send-frame t (+ (struct.pack "<BBHH" OP:WRITE-MEM segment offset (len data)) data))
    (expect t (bytes [OP:WRITE-MEM 0x7E]))))

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

;;;
;;; Higher-level operations
;;;

(defclass Session []
  (meth __init__ [transport]
    (setv @transport transport)
    (setv @program-state
      (link.LinkInfo :bc-end 0
                     :function-table {}
                     :global-table {})))

  (meth close []
    (.close @transport))

  (meth eval [program
              execute
              [filename "stdin"]]
    ;; If "main" exists in function table, erase it
    ;; When executing a stand-alone program, self.program-state will be empty,
    ;; but for REPL'd statements this matters
    (let [function-table @program-state.function-table]
      (when (in "main" function-table)
        ;; Make sure "main" is the last function and erase it
        ;; Length of function table is used to allocate function ids, so can't delete in the middle
        (assert (= (. function-table ["main"] id) (dec (len function-table))))
        (del (get function-table "main"))
        ;; TODO: can also trim bc-end
        ))

    (setv unit (compile.compile-unit builtin-constants
                                     builtin-functions
                                     filename
                                     program
                                     :repl-globals (list (.keys @program-state.global-table))))
    (print unit)

    ;; link

    (setv link-info (link.link-program [unit]
                                       :output "lnk.tmp"
                                       :builtin-functions builtin-functions
                                       :repl-initial-state @program-state
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

    ;; make sure program is not running before we start to patch up memory
    ;; (it may also be in TERMINATED state, that's fine too)
    (.suspend self)

    (let [t @transport]
      (write-memory t SEGMENT:BC    @program-state.bc-end                     bc-bytes)
      (write-memory t SEGMENT:FUNC  (* 4 (len @program-state.function-table)) functions-bytes)
      (write-memory t SEGMENT:GLOB  (* 2 (len @program-state.global-table))   globals-bytes)

      (when execute
        (t.send-frame (struct.pack "<BBB" OP:BEGIN-EXEC main-func-idx 0))
        (expect t (bytes [OP:BEGIN-EXEC 0x7E]))))

    (setv @program-state link-info)
    (print "New program-state:" :end " ")
    (pprint @program-state))

  ;; reset REPL state
  (meth reset []
    (setv @program-state (link.LinkInfo :bc-end 0
                                        :function-table {}
                                        :global-table {})))

  (meth suspend []
    (.send-frame @transport (bytes [OP:SUSPEND]))
    (expect @transport (bytes [OP:SUSPEND 0x7E]))))

;; Compile and execute a complete STAK program
(defn execute-file [session filename]
  (with [f (open filename "r")]
    (let [forms (list (hy.read-many f))]
      (.eval session
             forms
             :execute True
             :filename filename))))

;;;
;;; Misc
;;;

(defn alternative-filenames [filename]
  ;; If file doesn't exist, try appending .scm
  (when (not (os.path.exists filename))
    (let [alt-filename (+ filename ".scm")]
      (when (os.path.exists alt-filename)
        (setv filename alt-filename))))

  filename)

;; Execute callback once and then each time the file changes
;; Can be interrupted by an exception (e.g., KeyboardInterrupt)
(defn watch-file [path callback]
  (let [last-stamp None]
    (while True
      (let [stamp (. (os.stat path) st_mtime)]
        (when (!= stamp last-stamp)
          (callback)
          (setv last-stamp stamp))
        (time.sleep 0.5)))))

;;;
;;; MAIN
;;;

(setv args (parse-args :spec [["-t" "--target"
                               :help "Attach to a running target (instead of starting new interpreter). Use 'tcp:<host>:<port>' or 'serial:<port>:<baudrate>'"]]))

(with [f (open "constants.json")]
  (setv builtin-constants (json.load f)))

(with [f (open "builtins.json")]
  (setv builtin-functions (json.load f)))

(cond
  ;; no target provided (launch our own)
  (is args.target None) (do
    (setv process (Popen ["./vm/stak" "-g"]
                         ;; prevent Ctrl-C (SIGINT) propagating to VM and killing it
                         ;; credit to https://stackoverflow.com/questions/3232613/how-to-stop-sigint-being-passed-to-subprocess-in-python#comment55906369_3731948
                         :preexec-fn os.setpgrp))

    ;; make sure interpreter doesn't outlive us
    (atexit.register process.terminate)

    (setv transport (retry-connect process #("localhost" 5000))))
  ;; TCP target
  (args.target.startswith "tcp:") (do
    (let [[_ host port-str] (args.target.split ":")
          port (int port-str)]
      (setv transport (SocketTransport #(host port)))))
  ;; serial target
  (args.target.startswith "serial:") (do
    (let [[_ port baud-str] (args.target.split ":")
          baud (int baud-str)]
      (try
        (setv transport (SerialTransport port baud))
        (except [exc serial.SerialException]
          (print exc)
          (exit 1)))))
  :else (do
    (print "Invalid target format. See(k) help.")
    (exit 1)))

(.send transport b"\x7Eh\x7E")  ;; send hello
(expect transport b"\x7EhSTAK\x7E")

(print "REPL is connected. Press Ctrl-D to exit.")

(setv session (Session transport))

(while True
  (try
    (let [inp (input ">")
          f   (io.StringIO inp)]
      ;; (print "input: " inp)
      (cond
        (= inp "reset") (do
          (.reset session))

        (.startswith inp "exec ") (do
          (let [filename (.removeprefix inp "exec ")
                filename (alternative-filenames filename)]
            (execute-file session filename)))

        (.startswith inp "watch ") (do
          (let [filename (.removeprefix inp "watch ")
                filename (alternative-filenames filename)]
            (try
              (watch-file filename (fn []
                ;; source changed; reset compiler state and re-run
                (.reset session)
                (try
                  (execute-file session filename)
                  (except [exc Exception]
                    ;; in case of an error, print it, but keep watching the file
                    (print exc)))))
              (except [exc FileNotFoundError]
                (print exc))
              (except [KeyboardInterrupt]
                (print)))))

        :else (do
          (setv forms (list (hy.read-many f)))

          ;; Iterate over forms. Some forms must be evaluated in global context (define), the rest are banched and evaluated in the context of a function.
          ;; (define <var> <value>) is special. It is split up into a global declaration, and the assignment of the initial value which is done in a functional context.
          ;; This way, it can be initialized with an expression, which is normally not possible (globals must be initialized with a literal)
          (setv batch [])

          (defn flush []
            (when (> (len batch) 0)
              (.eval session
                     [`(define (main) ~@batch)]
                     :execute True)
              (batch.clear)))

          (for [form forms]
            (if (and (isinstance form Expression)
                    (>= (len form) 1)
                    (= (get form 0) (Symbol "define")))
                (do
                  (flush)
                  (.eval session
                         [form]
                         :execute False))
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

(.close session)
