(lang dune 3.21)
(using rocq 0.11)
(name rocq-coinduction)

(package
 (name     rocq-coinduction)
 (synopsis "A library for doing proofs by (enhanced) coinduction.")
 (depends
  (rocq-prover (>= 9.0))
  (dune        (>= 3.21))
 )
)
