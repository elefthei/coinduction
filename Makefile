install: build
	opam exec -- dune build -p rocq-coinduction @install
	opam exec -- dune install
build:
	opam exec -- dune build -j4

clean:
	dune clean

