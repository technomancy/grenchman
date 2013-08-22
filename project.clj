(defproject dummy "0.0.0."
  :description "Simply for testing."
  :eval-in :leiningen
  :repl-options {:port 50454
                 :nrepl-middleware [(fn [handler]
                                      (fn [& args]
                                        (prn :middle args)
                                        (apply handler args)))]})
