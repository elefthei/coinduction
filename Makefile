install: build
	dune build -p coq-coinduction @install
	dune install
build:
	dune build

clean:
	dune clean

