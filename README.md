This is _STAK_, a minimalist programming environment based on a programming language with S-expression syntax and a bytecode virtual machine. The intended use is for game prototyping. It was somewhat inspired by the Another World virtual machine, which facilitated the porting of that game to many platforms.

To get started, clone the repository and install prerequisites.

    sudo apt install gcc libsdl2-dev make  # Ubuntu
    sudo dnf install gcc make SDL2-devel   # Fedora
    pip install hy

Build the VM, build the examples and run them one by one:

    make -C vm
    make
    ./vm/stak 01fill.bc
    ./vm/stak 02colors.bc
    ./vm/stak 03loop.bc
    ./vm/stak 04input.bc
    ./vm/stak 05lines.bc

Alternatively, having built the VM, drop into the REPL:

    hy repl.hy

The examples (*.scm) files are the best way to learn about the language.

### Build for DOS

You will need the Open Watcom toolchain and correspondingly set up environment variables.

    export WATCOM=/opt/open-watcom-v2/rel
    export PATH=$WATCOM/binl64:$WATCOM/binl:$PATH
    export INCLUDE=$WATCOM/h
    cd vm
    make -f Makefile.dos

To connect the REPL to DOSBox, launch the VM in one shell:

    make -f Makefile.dos debug

And attach the REPL in another:

    hy repl.hy -t tcp:localhost:5000

If your VM is instead running on a real DOS machine (`INTERP.EXE -g`) you can connect to it over a serial connection:

    hy repl.hy -t serial:/dev/ttyUSB0:9600

### Try these code snippets

```
(draw-line COLOR:WHITE 0 0 100 100)

(dotimes (i 15) (draw-line (+ 1 i) (/ (* (- W 1) i) 14) 0 (/ W 2) H))

(dotimes (x 16) (dotimes (y 16) (fill-rect (+ (* 16 y) x) (* 20 x) (/ (* H y) 16) 20 13)))

(define (cls) (fill-rect COLOR:WHITE 0 0 W H))
(cls)

(define (grid rows cols color) (dotimes (y rows) (draw-line color 0 (* 10 y) W (* 10 y))) (dotimes (x cols) (draw-line color (* 10 x) 0 (* 10 x) H)))

(dotimes (i 200) (grid 20 32 i) (pause-frames 1))
```
