(lang dune 3.12)
(using coq 0.8)
(name coq-coinduction)

(package
 (name     coq-coinduction)
 (synopsis "A library for doing proofs by (enhanced) coinduction.")
 (depends
  (coq (>= 9.0))
  (dune      (>= 2.8))
 )
)
