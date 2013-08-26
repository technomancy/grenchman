# Grenchman

Fast invocation of Leiningen tasks over nREPL.

<a href="http://achewood.com/index.php?date=04022007">
  <img src="comic.gif" align="right"></a>

## Install

You would need to install [opam](http://opam.ocamlpro.com/) and OCaml 4.x to be
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
    $ opam install core async
    $ ocamlbuild -use-ocamlfind grench.native
    $ ln -s $PWD/grench.native ~/bin/grench # or somewhere on your $PATH

## Usage

You can use `grench` as a replacement launcher for `lein` for most
non-interactive tasks. When used together with `:eval-in :nrepl`, you
can eval Clojure code inside your project in under 0.15 seconds.

Currently requires Leiningen from git master (newer than 2.3.2). It's
up to you to launch your own Leiningen process separately:

    $ cd ~/.lein && lein repl :headless

Tasks for all projects will share the same Leiningen instance, so
projects with have conflicting plugins may behave unpredictably.

## License

Copyright © 2013 Phil Hagelberg. Bencode implementation by Prashanth
Mundkur. Licensed under the GNU General Public License, version 3 or
later. See COPYING for details.
