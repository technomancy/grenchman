# Grenchman

Fast invocation of Clojure code over nREPL.

<a href="http://achewood.com/index.php?date=04022007">
  <img src="comic.gif" align="right"></a>

## Install

You will need to install [opam](http://opam.ocamlpro.com/) and OCaml 4.x to be
able to build Grenchman.

If you're not sure whether you have 4.x installed or not, you can ensure
yourself as follows:

    $ opam switch list
    # If your system compiler is 4.x or above, you're ready to go.
    # Otherwise, issue the following command:
    $ opam switch 4.00.1

To build, run the following commands:

    $ git clone git@github.com:technomancy/grenchman.git grenchman
    $ cd grenchman
    $ opam install ocamlfind core async ctypes
    $ ocamlbuild -use-ocamlfind grench.native
    $ ln -s $PWD/grench.native ~/bin/grench # or somewhere on your $PATH

## Usage

Grenchman has four main commands:

* `grench main my.main.ns arg1 arg2` - to run an existing `-main` defn
* `grench eval "(+ 12 49)"` - to run code provided as argument
* `grench repl` or `grench repl :connect $PORT` - to connect a repl
* `grench lein $TASK` - to run Leiningen tasks

Each of these commands connects to a running nREPL server in order to
avoid JVM startup time. The simplest way to start a project JVM is to
run `lein trampoline repl :headless` from the project directory in
another shell. By default the port will be determined by traversing up
the directory tree until an `.nrepl-port` file is found. Setting the
`GRENCH_PORT` environment variable overrides this. The `lein`
invocation above writes the `.nrepl-port` file in the project root for you.

### Leiningen

The `grench lein` subcommand is the exception to this; it connects to
a Leiningen JVM rather than a project JVM. It looks for the port in
`~/.lein/repl-port` or `$LEIN_REPL_PORT`; you can launch this server
using `lein repl :headless` from outside a project directory.

Using Grenchman avoids waiting for Leiningen's JVM to start, but
project JVMs are still launched like normal by default for most task
invocations if Leiningen can't find a running project JVM.

Currently the Leiningen integration requires running from lein's git
master (newer than 2.3.2).

## Gotchas

If you get no output from `grench lein ...` but your Leiningen process
emits an `java.io.FileNotFoundException: project.clj` error message,
this might mean your version of Leiningen is too old; you need at
least 2.3.3.

Tasks for all projects will share the same Leiningen instance, so
projects with have conflicting plugins or hooks may behave unpredictably.

If Grenchman cannot connect on the port specified, it will terminate
with an exit code of 111, which may be useful for scripting it.

## License

Copyright © 2013 Phil Hagelberg and
[contributors](https://github.com/technomancy/grenchman/contributors). Bencode
implementation by Prashanth Mundkur. Licensed under the GNU General
Public License, version 3 or later. See COPYING for details.
