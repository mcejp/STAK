This is _STAK_, a minimalist programming environment based on a programming language with S-expression syntax and a bytecode virtual machine. The intended use is for game prototyping. It was somewhat inspired by the Another World virtual machine, which facilitated the porting of that game to many platforms.

To get started, clone the repository and install the prerequisites.

    sudo apt install gcc make libsdl2-dev  # Ubuntu
    sudo dnf install gcc make SDL2-devel   # Fedora
    pip install hy pyserial tqdm

Build a native version of the VM, then build the examples and run them one by one:

    make -C vm
    make
    ./vm/stak 01fill.bc
    ./vm/stak 02colors.bc
    ./vm/stak 03loop.bc
    ./vm/stak 04input.bc
    ./vm/stak 05lines.bc
    ./vm/stak 06values.bc
    ./vm/stak flower.bc
    ./vm/stak gorillas.bc
    ./vm/stak sin.bc

Alternatively, having built the VM, launch the REPL, which will also start the VM, and execute some code...

    hy repl.hy

    (fill-rect COLOR:BLUE 100 50 50 50)

    (draw-line COLOR:WHITE 0 0 100 100)

    (dotimes (i 15) (draw-line (+ 1 i) (/ (* (- W 1) i) 14) 0 (/ W 2) H))

    (dotimes (x 16) (dotimes (y 16) (fill-rect (+ (* 16 y) x) (* 20 x) (/ (* H y) 16) 20 13)))

    (define (cls) (fill-rect COLOR:WHITE 0 0 W H))
    (cls)

    (define (grid rows cols color) (dotimes (y rows) (draw-line color 0 (* 10 y) W (* 10 y))) (dotimes (x cols) (draw-line color (* 10 x) 0 (* 10 x) H)))

    (dotimes (i 200) (grid 20 32 i) (pause-frames 1))

...or load one of the example programs in _watch_ mode and make changes to its code.

    hy repl.hy
    watch flower.scm

Until there is a better tutorial, the examples (*.scm) files are the best way to learn about the language.

### Build for DOS

You will first need to [download/build the Open Watcom toolchain](https://mcejp.github.io/2021/02/03/open-watcom.html) and set up some environment variables correspondingly.

    export WATCOM=/opt/open-watcom-v2/rel
    export PATH=$WATCOM/binl64:$WATCOM/binl:$PATH
    export INCLUDE=$WATCOM/h
    cd vm
    make -f Makefile.dos

To connect the REPL to DOSBox, launch the VM in one shell:

    make -f Makefile.dos debug

And attach the REPL in another:

    hy repl.hy -t tcp:localhost:5000

If your VM is instead listening on a real DOS machine (`STAK.EXE -g`) you can connect to it over a serial connection:

    hy repl.hy -t serial:/dev/ttyUSB0:9600
