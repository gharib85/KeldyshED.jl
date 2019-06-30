KeldyshED.jl
============

Equilibrium Exact Diagonalization solver for finite fermionic models that can
compute Green's functions on the Keldysh contour.

Copyright (c) 2019 Igor Krivenko

This is my first attempt at writing Julia 1.1 code and, to a large extent, a
simplified port of the `TRIQS/atom_diag` library.

Special thanks to Joseph Kleinhenz for reviewing my code, as well as for writing
the [Keldysh.jl](https://github.com/kleinhenz/Keldysh.jl) library, which `KeldyshED.jl`
depends on.

Usage
-----

Run `JULIA_PROJECT="<path_to_sources>" julia -p <n_cpu_cores> <path_to_sources>/bin/anderson.jl`
to compute Green's functions of the single orbital Anderson model with descrete bath.
