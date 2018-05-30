(defsystem th
  :name "th"
  :author "Sungjin Chun <chunsj@gmail.com>"
  :version "0.1"
  :maintainer "Sungjin Chun <chunsj@gmail.com>"
  :license "GPL3"
  :description "common lisp binding for TH library"
  :long-description "common lisp binding for TH library"
  :depends-on ("cffi"
               "mu")
  :components ((:file "package")
               (:file "th")
               (:file "load")
               (:file "typedefs")
               (:module generator :components ((:file "generator")))
               (:module storage :components ((:file "byte")
                                             (:file "char")
                                             (:file "short")
                                             (:file "int")
                                             (:file "long")
                                             (:file "float")
                                             (:file "double")))
               (:module tensor :components ((:file "byte")
                                            (:file "char")
                                            (:file "short")
                                            (:file "int")
                                            (:file "long")
                                            (:file "float")
                                            (:file "double")))
               (:module file :components ((:file "file")))
               (:module object :components ((:file "object")
                                            (:file "generator")
                                            (:file "storage")
                                            (:file "tensor")
                                            (:file "file")))
               (:module ffi :components ((:file "tensor")))
               (:module binding :components ((:file "generator")
                                             (:file "storage")
                                             (:file "tensor")
                                             (:file "file")))
               (:module nn :components ((:file "ffi")
                                        (:file "nn")))
               (:module ad :components ((:file "autograd")
                                        (:file "gd")
                                        (:file "operator")
                                        (:file "function")
                                        (:file "support")
                                        (:file "utility")))
               (:module db :components ((:file "mnist")))))
