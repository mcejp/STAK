===========
STAK manual
===========

STAK is a programming language and its native execution environment.

The basic building block of a STAK program is the *form*, which is either a function application or one of the so-called *special forms*.
There is a number of built-in functions, and user functions can be defined in the program (in fact, a ``main`` function is always required)

Atoms
=====

- integers ranging from -32768 to 32767
- variables (local, global)
- built-in constants

Built-in functions and constants
================================

Basic arithmetics
-----------------

.. code-block::

  (+  a b)
  (-  a b)
  (*  a b)
  (/  a b)
  (%  a b)
  (<< a b)
  (>> a b)


These work as in C. The value type is always int16.

Fixed-point arithmetic
----------------------

.. code-block::

  (from-int@ value)
  (to-int value@)


Convert between 16-bit integer and 10.6 fixed-point format. Equivalent to shifting left and right by 6 bits, respectively.


.. code-block::

  (mul@ a b)


Multiply values and shift down by 6 bits. The multiplication is computed in full 22-bit resolution. Therefore, ``(mul@ 32767 64)`` will produce the correct result (32767).


.. code-block::

  (sin@ angle)
  (cos@ angle)


Compute the sine or cosine of the given angle.
Angle is specified in units of pi/128, i.e. 256 corresponds to 2pi or 360 degrees. The result is returned in 10.6 fractional format.

Comparison and logical operators
--------------------------------

.. code-block::

  (<  a b)
  (<= a b)
  (=  a b)
  (!= a b)
  (>= a b)
  (>  a b)
  (not a)
  (and a b)
  (or  a b)


These, again, work like in C. The only difference is ``=`` instead of ``==``.
Unlike other LISP-inspired languages, ``and`` and ``or`` can not take more than 2 arguments.

Graphics
--------

.. code-block::

  (define COLOR:BLACK          0)
  (define COLOR:BLUE           1)
  (define COLOR:GREEN          2)
  (define COLOR:CYAN           3)
  (define COLOR:RED            4)
  (define COLOR:MAGENTA        5)
  (define COLOR:BROWN          6)
  (define COLOR:LIGHTGRAY      7)
  (define COLOR:DARKGRAY       8)
  (define COLOR:LIGHTBLUE      9)
  (define COLOR:LIGHTGREEN    10)
  (define COLOR:LIGHTCYAN     11)
  (define COLOR:LIGHTRED      12)
  (define COLOR:LIGHTMAGENTA  13)
  (define COLOR:YELLOW        14)
  (define COLOR:WHITE         15)
  (define COLOR:COUNT        256)
  (define W 320)
  (define H 200)

  (draw-line     color x1 y1 x2 y2)
  (fill-rect     color x1 y1 w h)
  (fill-triangle color x1 y1 x2 y2 x3 y3)
  (pause-frames  count)


These do what you would expect...
The coordinate system is from (0, 0) in the left-top corner to (319, 199).

Keyboard input
--------------

.. code-block::

  (define KEY:UP    <unspecified>)
  (define KEY:DOWN  <unspecified>)
  (define KEY:LEFT  <unspecified>)
  (define KEY:RIGHT <unspecified>)
  (define KEY:CTRL  <unspecified>)

  (key-pressed?  key)
  (key-released? key)
  (key-held?     key)

Random numbers
--------------

.. code-block::

  (random)
  (set-random-seed! seed)


Special forms
=============

define
------

.. code-block::

  (define counter 0)  ; variable definition


.. code-block::

  (define x* y* (transform x y))  ; multiple-variable-unpack definition


.. code-block::

  (define (+ a b) body...)    ; function definition

dotimes
-------

.. code-block::

  (dotimes (color COLOR:COUNT)
    (clear-screen color)
    (pause-frames 10))

set!
----

.. code-block::

  (set! i (+1 i))

values
------

.. code-block::

  (define (add-vec x1 y1 x2 y2)
    (values (+ x1 x2) (+ y1 y2)))

when
----

.. code-block::

  (when (< x 0)
    (set! x 0))

while
-----

.. code-block::

  (while <cond>
    <body> ...)
