# History of user-visible changes in Grenchman

## 0.2.0 / 06-10-2013

* Read forms from stdin when no args are given.
* Exit with 111 to indicate connection failure.
* Use `libreadline` for all console input.
* Implement `repl` as independent client instead of deferring to Leiningen's.
* Add `eval` and `main` subcommands which don't involve Leiningen.
* Move Leiningen task invocation to `lein` subcommand.

## 0.1.0 / 29-08-2013

* Initial release!
