(in-package :th.pp)

(defgeneric r/deviance (rv))

(defclass r/cvar (r/continuous)
  ((deviance :initform nil)))

(defclass r/dvar (r/discrete)
  ((deviance :initform nil)))

(defun r/cvar (value &optional deviance)
  (let ((rv (make-instance 'r/cvar))
        (dev deviance))
    (with-slots (deviance) rv
      (setf ($data rv) value)
      (when dev (setf deviance dev)))
    rv))

(defun r/dvar (value &optional deviance)
  (let ((rv (make-instance 'r/dvar))
        (dev deviance))
    (with-slots (deviance) rv
      (setf ($data rv) value)
      (when dev (setf deviance dev)))
    rv))

(defmethod r/deviance ((rv r/variable)))

(defmethod r/deviance ((rv r/cvar))
  (with-slots (deviance) rv
    deviance))

(defmethod r/deviance ((rv r/dvar))
  (with-slots (deviance) rv
    deviance))

(defgeneric proposal/scale! (proposal s))
(defgeneric proposal/rescale! (proposal))
(defgeneric proposal/accepted! (proposal acceptedp))
(defgeneric proposal/propose (proposal value))

(defgeneric r/proposal (rv &optional dev))
(defgeneric r/propose! (rv proposal))
(defgeneric r/accept! (rv proposal acceptedp))

(defclass r/proposal ()
  ((accepted :initform 0)
   (rejected :initform 0)
   (factor :initform 1.0)
   (scale :initform 1.0)
   (pvalue :initform nil :accessor $data)))

(defmethod proposal/scale! ((proposal r/proposal) s)
  (with-slots (factor scale) proposal
    (setf factor 1.0
          scale s)))

(defmethod proposal/rescale! ((proposal r/proposal))
  (with-slots (accepted rejected factor) proposal
    (let ((total (+ accepted rejected)))
      (when (> total 0)
        (let ((r (/ accepted total)))
          (cond ((< r 0.001) (setf factor (* factor 0.1)))
                ((< r 0.05) (setf factor (* factor 0.5)))
                ((< r 0.2) (setf factor (* factor 0.9)))
                ((> r 0.95) (setf factor (* factor 10.0)))
                ((> r 0.75) (setf factor (* factor 2.0)))
                ((> r 0.5) (setf factor (* factor 1.1))))
          (setf accepted 0
                rejected 0))))))

(defmethod proposal/accepted! ((proposal r/proposal) acceptedp)
  (with-slots (accepted rejected) proposal
    (if acceptedp
        (incf accepted)
        (incf rejected))
    proposal))

(defmethod r/propose! ((rv r/variable) (proposal r/proposal))
  (let ((proposed (proposal/propose proposal ($data rv))))
    (setf ($data proposal) ($data rv))
    (setf ($data rv) (car proposed))
    (cdr proposed)))

(defmethod r/accept! ((rv r/variable) (proposal r/proposal) acceptedp)
  (proposal/accepted! proposal acceptedp)
  (unless acceptedp
    (setf ($data rv) ($data proposal)
          ($data proposal) nil))
  rv)

(defclass proposal/gaussian (r/proposal) ())

(defun proposal/gaussian (&optional (scale 1.0))
  (let ((n (make-instance 'proposal/gaussian))
        (s scale))
    (with-slots (scale) n
      (setf scale s))
    n))

(defmethod proposal/propose ((proposal proposal/gaussian) value)
  (with-slots (scale factor) proposal
    (cons (sample/gaussian value (max 1E-7 (* factor scale))) 0.0)))

(defclass proposal/discrete-gaussian (r/proposal) ())

(defun proposal/discrete-gaussian (&optional (scale 2.0))
  (let ((n (make-instance 'proposal/discrete-gaussian))
        (s scale))
    (with-slots (scale) n
      (setf scale s))
    n))

(defmethod proposal/propose ((proposal proposal/discrete-gaussian) value)
  (with-slots (scale factor) proposal
    (cons (round (sample/gaussian value (max 1E-7 (* factor scale)))) 0.0)))

(defclass proposal/poisson (r/proposal) ())

(defun proposal/poisson (&optional (scale 1.0))
  (let ((n (make-instance 'proposal/poisson))
        (s scale))
    (with-slots (scale) n
      (setf scale s))
    n))

(defmethod proposal/propose ((proposal proposal/poisson) value)
  (with-slots (scale factor) proposal
    (cons (+ value (* (sample/poisson (max 1E-7 (* factor scale)))
                      (if (= 1 (random 2)) -1 1)))
          0.0)))

(defmethod r/proposal ((rv r/discrete) &optional dev)
  (let ((p (proposal/poisson)))
    (unless (zerop ($data rv))
      (with-slots (scale) p
        (if dev
            (setf scale dev)
            (if (r/deviance rv)
                (setf scale (if (zerop (r/deviance rv)) 1 (r/deviance rv)))
                (let ((absv ($abs ($data rv))))
                  (setf scale (* scale (if (zerop absv) 1 absv))))))))
    p))

(defmethod r/proposal ((rv r/continuous) &optional dev)
  (let ((p (proposal/gaussian)))
    (unless (zerop ($data rv))
      (with-slots (scale) p
        (if dev
            (setf scale dev)
            (if (r/deviance rv)
                (setf scale (if (zerop (r/deviance rv)) 1 (r/deviance rv)))
                (let ((absv ($abs ($data rv))))
                  (setf scale (* scale (if (zerop absv) 1 absv))))))))
    p))

(defclass rstat ()
  ((n :initform 0.0)
   (pm :initform 0.0)
   (nm :initform 0.0)
   (ps :initform 0.0)
   (ns :initform 0.0)))

(defun rstat () (make-instance 'rstat))

(defun rstat/push! (rstat x)
  (with-slots (n pm nm ps ns) rstat
    (incf n)
    (if (= n 1)
        (setf pm x
              nm x
              ps 0.0)
        (setf nm (+ pm (/ (- x pm) n))
              ns (+ ps (* (- x pm) (- x nm)))))
    (setf pm nm
          ps ns)))

(defun rstat/mean (rstat)
  (with-slots (n nm) rstat
    (if (> n 0)
        nm
        0.0)))

(defun rstat/variance (rstat)
  (with-slots (n ns) rstat
    (if (> n 1)
        (/ ns n)
        0.0)))

(defun mh/accepted (prob nprob log-hastings-ratio)
  (when (and prob nprob log-hastings-ratio)
    (let ((alpha (+ (- nprob prob) log-hastings-ratio)))
      (> alpha (log (random 1.0))))))

(defun mcmc/mh-emam (parameters posterior-function
                     &key (iterations 50000) (burn-in 10000) (thin 1) (tune-steps 1000)
                       deviances)
  (labels ((posterior (vs) (apply posterior-function vs))
           (vals (parameters) (mapcar #'$data parameters)))
    (let ((prob (posterior (vals parameters)))
          (tune-steps (or tune-steps 1000)))
      (when prob
        (let ((proposals (mapcar #'r/proposal parameters))
              (traces (r/traces (mapcar #'$clone (mapcar #'$data parameters))
                                :n iterations :burn-in burn-in :thin thin))
              (candidates (mapcar #'$clone parameters))
              (nsize (+ iterations burn-in))
              (bstep (round (/ burn-in 10)))
              (pstep (round (/ iterations 10)))
              (maxprob prob)
              (naccepted 0))
          (when deviances
            (loop :for s :in deviances
                  :for pd :in proposals
                  :do (proposal/scale! pd s)))
          (prn (format nil "[MH/EMAM: BURNING"))
          (loop :repeat nsize
                :for iter :from 1
                :for burning = (<= iter burn-in)
                :for tuneable = (zerop (rem iter tune-steps))
                :do (progn
                      (when (and burning (zerop (rem iter bstep)))
                        (prns "."))
                      (when (= burn-in iter)
                        (prns (format nil " DONE. SAMPLING")))
                      (when (and (not burning) (zerop (rem (- iter burn-in) pstep)))
                        (prns "."))
                      (loop :for proposal :in proposals
                            :for candidate :in candidates
                            :for trace :in traces
                            :for lhr = (r/propose! candidate proposal)
                            :for nprob = (posterior (vals candidates))
                            :do (let ((accepted (mh/accepted prob nprob lhr)))
                                  (r/accept! candidate proposal accepted)
                                  (setf ($ trace (1- iter)) ($clone ($data candidate)))
                                  (when accepted
                                    (incf naccepted)
                                    (setf prob nprob)
                                    (when (> prob maxprob)
                                      (setf maxprob prob)
                                      (loop :for tr :in traces
                                            :for c :in candidates
                                            :do (setf ($data tr) ($clone ($data c))))))
                                  (when tuneable
                                    (proposal/rescale! proposal))))))
          (if (zerop naccepted)
              (prns (format nil " FAILED]~%"))
              (prns (format nil " DONE]~%")))
          traces)))))

(defun mcmc/mh-scam (parameters posterior-function
                     &key (iterations 50000) (burn-in 10000) (thin 1) (tune-steps 1)
                       deviances)
  (labels ((posterior (vs) (apply posterior-function vs))
           (vals (parameters) (mapcar #'$data parameters)))
    (let ((prob (posterior (vals parameters)))
          (tune-steps (or tune-steps 1)))
      (when prob
        (let ((proposals (mapcar (lambda (p)
                                   (if (r/deviance p)
                                       (r/proposal p)
                                       (r/proposal p 5.0)))
                                 parameters))
              (traces (r/traces (mapcar #'$clone (mapcar #'$data parameters))
                                :n iterations :burn-in burn-in :thin thin))
              (candidates (mapcar #'$clone parameters))
              (rstats (loop :for p :in parameters :collect (rstat)))
              (nsize (+ iterations burn-in))
              (bstep (round (/ burn-in 10)))
              (pstep (round (/ iterations 10)))
              (maxprob prob)
              (naccepted 0)
              (cf (* 2.4 2.4)))
          (when deviances
            (loop :for s :in deviances
                  :for pd :in proposals
                  :do (proposal/scale! pd s)))
          (prn (format nil "[MH/SCAM: BURNING"))
          (loop :repeat nsize
                :for iter :from 1
                :for burning = (<= iter burn-in)
                :for tuneable = (and (>= iter 11) (zerop (rem iter tune-steps)))
                :do (progn
                      (when (and burning (zerop (rem iter bstep)))
                        (prns "."))
                      (when (and (not burning) (zerop (rem (- iter burn-in) pstep)))
                        (prns "."))
                      (when (= burn-in iter)
                        (prns (format nil " DONE. SAMPLING")))
                      (loop :for proposal :in proposals
                            :for candidate :in candidates
                            :for trace :in traces
                            :for rs :in rstats
                            :for lhr = (r/propose! candidate proposal)
                            :for nprob = (posterior (vals candidates))
                            :do (let ((accepted (mh/accepted prob nprob lhr)))
                                  (r/accept! candidate proposal accepted)
                                  (setf ($ trace (1- iter)) ($clone ($data candidate)))
                                  (rstat/push! rs ($data candidate))
                                  (when tuneable
                                    (let ((g (* cf (+ (rstat/variance rs) 0.05))))
                                      (proposal/scale! proposal (sqrt g))))
                                  (when accepted
                                    (incf naccepted)
                                    (setf prob nprob)
                                    (when (> prob maxprob)
                                      (setf maxprob prob)
                                      (loop :for tr :in traces
                                            :for c :in candidates
                                            :do (setf ($data tr) ($clone ($data c))))))))))
          (if (zerop naccepted)
              (prns (format nil " FAILED]~%"))
              (prns (format nil " DONE]~%")))
          traces)))))

(defun wrap-parameters (parameters)
  (->> parameters
       (mapcar (lambda (p)
                 (cond ((r/variablep p) p)
                       ((integerp p) (r/dvar p))
                       ((floatp p) (r/cvar p))
                       ((listp p) (cond ((integerp (car p)) (r/dvar (car p) (cadr p)))
                                        ((floatp (car p)) (r/cvar (car p) (cadr p)))
                                        (T (r/cvar (car p) (cadr p)))))
                       (T (r/cvar p)))))))

(defun mcmc/mh (parameters posterior-function
                &key (iterations 30000) (burn-in 10000) (thin 1) tune-steps (type :scam)
                  deviances)
  (let ((parameters (wrap-parameters parameters)))
    (cond ((eq type :emam) (mcmc/mh-emam parameters posterior-function
                                         :iterations iterations :burn-in burn-in
                                         :thin thin :tune-steps tune-steps
                                         :deviances deviances))
          ((eq type :scam) (mcmc/mh-scam parameters posterior-function
                                         :iterations iterations :burn-in burn-in
                                         :thin thin :tune-steps tune-steps
                                         :deviances deviances)))))
