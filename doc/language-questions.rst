==================
Language questions
==================

cond, case
==========

Highly desirable. They are often the best fit for expressing the mental structure of the logic.

R7RS spells out definitions for these as macros -- naturally, written in Scheme (they're also pretty long).
The difference is that Scheme needs to implement them in terms of the `if` special form.
We have opted for the opposite and implemented `cond` as a built-in (mainly because with a dumb compiler this will lead to much more efficient bytecode).


defconst
========

- we don't seem to need it until we start running into globals limits
- what if we need to import constants from other modules -- will this help/hinder?


define-values
=============

The currently implemented syntax is::

  (define x* y* (transform x y))

But we might want to reclaim this syntax to allow defining multiple variables at once. We would change this to, for example, the standard (Scheme) syntax::

  (define-values (x* y*) (transform x y))


Macros
======

The main question is -- should they simply be Hy code, or something else?

Some other ideas:
- a STAK program is accompanied by an arbitrary executable (Hy, shell, native...) that reads one form at a time from stdin and outputs expanded forms to stdout
  - very flexible, but complicated; need to de/serialize forms back and forth, which seems silly
- a STAK program is accompanied by a Hy module that defines Hy functions/macros, which are then called by the compiler
  - macros can be defined in the standard Hy way, which seems like a win

Questions:
- At which positions should macro expansion be permitted? How is it in LISP, Scheme, Racket...?


Variadic arithmetic
===================

Textbook example::

  (define x* (+ (>> (+ (+ (* m11@ x) (* m12@ y)) (* m13@ z)) 6) m14@))

Having to spell out ``(+ (+`` is just silly.

Unary negation can be considered another case of this, but it requires different handling (dedicated opcode or insertion of 0 as the _first_ operand).
