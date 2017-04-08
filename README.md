# Grenchman

Fast invocation of Clojure code over nREPL.

<a href="http://achewood.com/index.php?date=04022007">
  <img src="comic.gif" align="right"></a>

To install, download the appropriate binary from
https://leiningen.org/grench.html and place it on your path. If
downloads for your platform are not provided you can compile your own;
see "Building" below.

## Usage

Grenchman has five main commands:

* `grench eval "(+ 12 49)"` - evals given form
* `grench main my.main.ns/entry-point arg1 arg2` - runs existing defn
* `grench repl` or `grench repl :connect $PORT` - connects a repl
* `grench load path/to/file.clj` - load a file
* `grench lein test` - runs a Leiningen task

Running with no arguments will read code from stdin to accomodate shebangs.

The first four commands connect to a running nREPL project server in
order to avoid JVM startup time. The simplest way to start a project
nREPL server is to run `lein trampoline repl :headless` from the
project directory in another shell. All non-lein `grench` invocations
from inside the project directory will use that nREPL, but by setting
the `GRENCH_PORT` environment variable you can connect to it from
outside.

### Leiningen

The `grench lein` subcommand is the exception to this; it connects to
a Leiningen nREPL server rather than a project nREPL. It looks for the
port in `~/.lein/repl-port` or `$LEIN_REPL_PORT`; you can launch this
server using `lein repl :headless` from outside a project directory.

Using Grenchman avoids waiting for Leiningen's JVM to start, but
project JVMs are still launched like normal when necessary if
Leiningen can't find a running project nREPL server. Note that this
goes through Leiningen by looking for `.nrepl-port` and doesn't check
`$GRENCH_PORT`.

Currently the Leiningen integration requires Leiningen 2.3.3 or newer.
If you get no output from `grench lein ...` but your Leiningen process
emits an `java.io.FileNotFoundException: project.clj` error message,
upgrading Leiningen should fix it.

## Building

Building grenchman typically requires compiling the whole OCaml
toolchain (two compilers, two standard libraries, a package manager,
and a handful of other third-party libraries) from scratch and can
take up to an hour. Please use the
[precompiled binaries](https://leiningen.org/grench.html#download) if
possible.

You will need to
[install opam](http://opam.ocaml.org/doc/Install.html) and
OCaml 4.x to be able to build Grenchman. You'll also need `libffi` as
well as `libreadline-dev` (sometimes called `readline-devel` on RPM
systems).

If you're not sure whether you have 4.x installed or not, you can check with:

    $ opam switch list
    # If your system compiler is 4.x or above, you're ready to go.
    # Otherwise, issue the following command:
    $ opam switch 4.04.0
    # Don't forget to add ~/.opam/4.04.0/bin/ to your $PATH

    $ sudo apt install ocaml ocaml-native-compilers opam camlp4 aspcud \
        libreadline-dev libffi-dev

To build, run the following commands:

    $ git clone git@github.com:technomancy/grenchman.git grenchman
    $ cd grenchman
    $ opam install ocamlfind core async ctypes ctypes-foreign
    $ ocamlbuild -use-ocamlfind -lflags -cclib,-lreadline grench.native
    $ ln -s $PWD/grench.native ~/bin/grench # or somewhere on your $PATH

## Gotchas

By default Leiningen uses compilation settings which trade long-term
performance for boot speed. With Grenchman you have long-running nREPL
processes which start rarely, so you should disable this by putting
`:jvm-opts []` in your `:user` profile.

Tasks for all projects will share the same Leiningen instance, so
projects with have conflicting plugins or hooks may behave unpredictably.

If Grenchman cannot connect on the port specified, it will terminate
with an exit code of 111, which may be useful for scripting it.

## License

Copyright © 2013, 2017 Phil Hagelberg and
[contributors](https://github.com/technomancy/grenchman/contributors). Bencode
implementation by Prashanth Mundkur. Licensed under the GNU General
Public License, version 3 or later. See COPYING for details.
