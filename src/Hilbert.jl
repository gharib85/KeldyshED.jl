module Hilbert

using LinearAlgebra
using DataStructures
using SparseArrays
using KeldyshED.Operators

export SetOfIndices, reversemap
export FockState, HilbertSpace, FullHilbertSpace, HilbertSubspace, getstateindex
export StateVector, StateDict, State, dot, project
export Operator
export SpacePartition, numsubspaces, merge_subspaces!

################
# SetOfIndices #
################

"""Mapping from Operators.IndicesType to a linear index"""
mutable struct SetOfIndices
  map_index_n::SortedDict{IndicesType, Int}
end

SetOfIndices() = SetOfIndices(SortedDict{IndicesType, Int}())
function SetOfIndices(v::AbstractVector)
  SetOfIndices(SortedDict{IndicesType, Int}(
    IndicesType(i) => n for (n, i) in enumerate(v)))
end

"""Insert a new index sequence"""
function Base.insert!(soi::SetOfIndices, indices::IndicesType)
  insert!(soi.map_index_n, indices, length(soi.map_index_n) + 1)
  # Reorder the linear indices
  soi.map_index_n = SortedDict{IndicesType, Int}(
    k => n for (n, (k, v)) in enumerate(soi.map_index_n)
  )
end

"""Insert a new index sequence"""
function Base.insert!(soi::SetOfIndices, indices...)
  insert!(soi, IndicesType([indices...]))
end

function Base.:(==)(soi1::SetOfIndices, soi2::SetOfIndices)
  soi1.map_index_n == soi2.map_index_n
end

Base.getindex(soi::SetOfIndices, indices) = soi.map_index_n[indices]
function Base.getindex(soi::SetOfIndices, indices...)
  soi.map_index_n[IndicesType([indices...])]
end

Base.in(indices, soi::SetOfIndices) = indices in keys(soi.map_index_n)

"""Build and return the reverse map: Int -> IndicesType"""
reversemap(soi::SetOfIndices) = collect(keys(soi.map_index_n))

#####################################
# SetOfIndices: Iteration interface #
#####################################
Base.eltype(soi::SetOfIndices) = Pair{IndicesType, Int}

Base.length(soi::SetOfIndices) = length(soi.map_index_n)
Base.isempty(soi::SetOfIndices) = isempty(soi.map_index_n)

Base.iterate(soi::SetOfIndices) = iterate(soi.map_index_n)
Base.iterate(soi::SetOfIndices, it) = iterate(soi.map_index_n, it)

Base.keys(soi::SetOfIndices) = keys(soi.map_index_n)
Base.values(soi::SetOfIndices) = values(soi.map_index_n)
Base.pairs(soi::SetOfIndices) = pairs(soi.map_index_n)

################
# HilbertSpace #
################

"""Abstract base for FullHilbertSpace and HilbertSubspace"""
abstract type HilbertSpace end

"""Fermionic Fock state encoded as a sequence of 0/1"""
const FockState = UInt64

####################
# FullHilbertSpace #
####################

"""
  A Hilbert space spanned by all fermionic Fock states generated by a given set
  of creation/annihilation operators.
"""
struct FullHilbertSpace <: HilbertSpace
  soi::SetOfIndices
  dim::UInt64
end

FullHilbertSpace() = FullHilbertSpace(0)
"""Hilbert space generated by creation/annihilation operators with given indices"""
FullHilbertSpace(soi::SetOfIndices) = FullHilbertSpace(soi, 1 << length(soi))

Base.:(==)(fhs1::FullHilbertSpace, fhs2::FullHilbertSpace) = fhs1.dim == fhs2.dim

Base.in(fs::FockState, fhs::FullHilbertSpace) = fs < fhs.dim

function Base.getindex(fhs::FullHilbertSpace, index)
  if index <= fhs.dim
    FockState(index - 1)
  else
    throw(BoundsError(x, "Fock state does not exist (index too big)"))
  end
end

"""Return Fock state generated by a product of creation operators with given indices"""
function Base.getindex(fhs::FullHilbertSpace, soi_indices::Set{IndicesType})
  foldl((fs, ind) -> fs + (FockState(1) << (fhs.soi[ind] - 1)),
        soi_indices;
        init = FockState(0))
end

"""Find the index of a given Fock state within fhs"""
function getstateindex(fhs::FullHilbertSpace, fs::FockState)
  if fs < fhs.dim
    Int(fs + 1)
  else
    throw(BoundsError(x, "Fock state is not part of this Hilbert space"))
  end
end

#########################################
# FullHilbertSpace: Iteration interface #
#########################################
Base.eltype(fhs::FullHilbertSpace) = FockState

Base.length(fhs::FullHilbertSpace)::Int = fhs.dim
Base.isempty(fhs::FullHilbertSpace) = fhs.dim == 0

function Base.iterate(fhs::FullHilbertSpace)
  fhs.dim > 0 ? (FockState(0), 0) : nothing
end
function Base.iterate(fhs::FullHilbertSpace, it)
  it < fhs.dim - 1 ? (FockState(it + 1), it + 1) : nothing
end

Base.keys(fhs::FullHilbertSpace) = LinearIndices(1:fhs.dim)
Base.values(fhs::FullHilbertSpace) = [FockState(i) for i=0:fhs.dim-1]
function Base.pairs(fhs::FullHilbertSpace)
  collect(Iterators.Pairs([FockState(i) for i=0:fhs.dim-1],
                          LinearIndices(1:fhs.dim)))
end

###################
# HilbertSubspace #
###################

"""Hilbert subspace, as an ordered set of basis Fock states."""
struct HilbertSubspace <: HilbertSpace
  # List of all Fock states
  fock_states::Vector{FockState}
  # Reverse map to quickly find the index of a state
  fock_to_index::Dict{FockState,Int}
end

HilbertSubspace() = HilbertSubspace(Vector{FockState}(), Dict{FockState,Int}())

function Base.insert!(hss::HilbertSubspace, fs::FockState)
  push!(hss.fock_states, fs)
  hss.fock_to_index[fs] = length(hss.fock_states)
end

"""
  Two subspaces are considered equal iff they have the same id and
  equal sets of basis Fock states.
"""
function Base.:(==)(hss1::HilbertSubspace, hss2::HilbertSubspace)
  hss1.fock_states == hss2.fock_states
end

Base.in(fs::FockState, hss::HilbertSubspace) = fs in hss.fock_states

Base.getindex(hss::HilbertSubspace, index) = hss.fock_states[index]

"""Find the index of a given Fock state within hss"""
getstateindex(hss::HilbertSubspace, fs::FockState) = hss.fock_to_index[fs]

########################################
# HilbertSubspace: Iteration interface #
########################################
Base.eltype(hss::HilbertSubspace) = FockState

Base.length(hss::HilbertSubspace) = length(hss.fock_states)
Base.isempty(hss::HilbertSubspace) = isempty(hss.fock_states)

Base.iterate(hss::HilbertSubspace) = iterate(hss.fock_states)
Base.iterate(hss::HilbertSubspace, it) = iterate(hss.fock_states, it)

Base.keys(hss::HilbertSubspace) = keys(hss.fock_states)
Base.values(hss::HilbertSubspace) = values(hss.fock_states)
Base.pairs(hss::HilbertSubspace) = pairs(hss.fock_states)

#########
# State #
#########

"""Abstract base for StateVector and StateDict"""
abstract type State{HSType <: HilbertSpace, ScalarType <: Number} end

###############
# StateVector #
###############

"""Quantum state in a Hilbert space/subspace implemented as a vector"""
struct StateVector{HSType, ScalarType} <: State{HSType, ScalarType}
  hs::HSType
  amplitudes::Vector{ScalarType}
end

function StateVector{HSType, S}(hs::HSType) where {HSType, S}
  StateVector{HSType, S}(hs, zeros(S, length(hs)))
end

function Base.similar(sv::StateVector{HSType, S}) where {HSType, S}
  StateVector{HSType, S}(sv.hs)
end

function Base.getindex(sv::StateVector{HSType, S}, index) where {HSType, S}
  getindex(sv.amplitudes, index)
end

function Base.setindex!(sv::StateVector{HSType, S},
                        val::S,
                        index) where {HSType, S}
  setindex!(sv.amplitudes, val, index)
end

function Base.:+(sv1::StateVector{HSType, S},
                 sv2::StateVector{HSType, S}) where {HSType, S}
  StateVector{HSType, S}(sv1.hs, sv1.amplitudes .+ sv2.amplitudes)
end

function Base.:-(sv1::StateVector{HSType, S},
                 sv2::StateVector{HSType, S}) where {HSType, S}
  StateVector{HSType, S}(sv1.hs, sv1.amplitudes .- sv2.amplitudes)
end

function Base.:*(sv::StateVector{HSType, S}, x::S) where {HSType, S}
  StateVector{HSType, S}(sv.hs, sv.amplitudes * x)
end
Base.:*(x::S, sv::StateVector{HSType, S}) where {HSType, S} = sv * x

Base.:/(sv::StateVector{HSType, S}, x::S) where {HSType, S} = sv * (one(S) / x)

function dot(sv1::StateVector, sv2::StateVector)
  LinearAlgebra.dot(sv1.amplitudes, sv2.amplitudes)
end

function Base.firstindex(sv::StateVector{HSType, S}) where {HSType, S}
  firstindex(sv.amplitudes)
end
function Base.lastindex(sv::StateVector{HSType, S}) where {HSType, S}
  lastindex(sv.amplitudes)
end

function Base.show(io::IO, sv::StateVector{HSType, S}) where {HSType, S}
  something_written = false
  for (i, a) in pairs(sv.amplitudes)
    if !isapprox(a, 0, atol = 100*eps(S))
      print(io, " +($a)|" * repr(Int(sv.hs[i])) * ">")
      something_written = true
    end
  end
  if !something_written print(io, "0") end
end

function Base.eltype(sv::StateVector{HSType, S}) where {HSType, S}
  typeof(pairs(sv.amplitudes))
end

"""Project a state from one Hilbert space to another Hilbert space/subspace"""
function project(sv::StateVector{HSType, S},
                 target_space::TargetHSType) where {HSType, S, TargetHSType}
  proj_sv = StateVector{TargetHSType, S}(target_space)
  for (i, a) in pairs(sv.amplitudes)
    f = sv.hs[i]
    if f in target_space
      proj_sv[getstateindex(target_space, f)] = a
    end
  end
  proj_sv
end

#############
# StateDict #
#############

"""Quantum state in a Hilbert space/subspace implemented as a (sparse) dictionary"""
struct StateDict{HSType, ScalarType} <: State{HSType, ScalarType}
  hs::HSType
  amplitudes::Dict{Int, ScalarType}
end

function StateDict{HSType, S}(hs::HSType) where {HSType, S}
  StateDict{HSType, S}(hs, Dict{Int, S}())
end

function Base.similar(sd::StateDict{HSType, S}) where {HSType, S}
  StateDict{HSType, S}(sd.hs)
end

function Base.getindex(sd::StateDict{HSType, S}, index) where {HSType, S}
  get(sd.amplitudes, index, zero(S))
end

function Base.setindex!(sd::StateDict{HSType, S},
                        val::S,
                        index) where {HSType, S}
  if isapprox(val, 0, atol = 1e-10)
    (index in keys(sd.amplitudes)) && delete!(sd.amplitudes, index)
    zero(S)
  else
    sd.amplitudes[index] = val
  end
end

function Base.:+(sd1::StateDict{HSType, S},
                 sd2::StateDict{HSType, S}) where {HSType, S}
  d = merge(+, sd1.amplitudes, sd2.amplitudes)
  filter!(p -> !isapprox(p.second, 0, atol = 1e-10), d)
  StateDict{HSType, S}(sd1.hs, d)
end

function Base.:-(sd1::StateDict{HSType, S},
                 sd2::StateDict{HSType, S}) where {HSType, S}
  d = merge(+, sd1.amplitudes, Dict([(i=>-a) for (i,a) in sd2.amplitudes]))
  filter!(p -> !isapprox(p.second, 0, atol = 1e-10), d)
  StateDict{HSType, S}(sd1.hs, d)
end

function Base.:*(sd::StateDict{HSType, S}, x::Number) where {HSType, S}
  if isapprox(x, 0, atol = 1e-10)
    StateDict{HSType, S}(sd.hs)
  else
    StateDict{HSType, S}(sd.hs, Dict([i => a*x for (i, a) in pairs(sd.amplitudes)]))
  end
end
Base.:*(x::Number, sd::StateDict{HSType, S}) where {HSType, S} = sd * x

Base.:/(sd::StateDict{HSType, S}, x::Number) where {HSType, S} = sd * (one(S)/x)

function dot(sd1::StateDict{HSType, S}, sd2::StateDict{HSType, S}) where {HSType, S}
  res = zero(S)
  for (i, a) in sd1.amplitudes
    res += conj(a) * get(sd2.amplitudes, i, 0)
  end
  res
end

function Base.show(io::IO, sd::StateDict{HSType, S}) where {HSType, S}
  something_written = false
  for i in sort(collect(keys(sd.amplitudes)))
    a = sd.amplitudes[i]
    if !isapprox(a, 0, atol = 100*eps(S))
      print(io, " +($a)|" * repr(Int(sd.hs[i])) * ">")
      something_written = true
    end
  end
  if !something_written print(io, "0") end
end

Base.eltype(sd::StateDict) = typeof(sv.amplitudes)

"""Project a state from one Hilbert space to another Hilbert space/subspace"""
function project(sd::StateDict{HSType, S},
                 target_space::TargetHSType) where {HSType, S, TargetHSType}
  proj_sd = StateVector{TargetHSType, S}(target_space)
  for (i, a) in pairs(sd.amplitudes)
    f = sd.hs[i]
    if f in target_space
      proj_sd[getstateindex(target_space, f)] = a
    end
  end
  proj_sd
end

##############################
# State: Iteration interface #
##############################

Base.length(st::State) = length(st.amplitudes)
Base.isempty(st::State) = isempty(st.amplitudes)

Base.size(st::State) = (length(st),)
Base.size(st::State, dim) = dim == 1 ? length(st) : 1

Base.iterate(st::State) = iterate(st.amplitudes)
Base.iterate(st::State, it) = iterate(st.amplitudes, it)

Base.keys(st::State) = keys(st.amplitudes)
Base.values(st::State) = values(st.amplitudes)
Base.pairs(st::State) = pairs(st.amplitudes)

############
# Operator #
############

# Fock state convention:
# |0,...,k> = C^+_0 ... C^+_k |0>
# Operator monomial convention:
# C^+_0 ... C^+_i ... C_j  ... C_0

struct OperatorTerm{ScalarType <: Number}
  coeff::ScalarType
  # Bit masks used to change bits
  annihilation_mask::FockState
  creation_mask::FockState
  # Bit masks for particle counting
  annihilation_count_mask::FockState
  creation_count_mask::FockState
end

"""Quantum-mechanical operator acting on states in a Hilbert space"""
struct Operator{HSType <: HilbertSpace, ScalarType <: Number}
  terms::Vector{OperatorTerm{ScalarType}}
end

function Operator{HSType, S}(op_expr::OperatorExpr{S},
                             soi::SetOfIndices) where {HSType, S}
  compute_count_mask = (d::Vector{Int}) -> begin
    mask::FockState = 0
    is_on = (length(d) % 2) == 1
    for i = 1:64
      if i in d
        is_on = !is_on
      else
        if is_on
          mask |= (one(FockState) << (i-1))
        end
      end
    end
    mask
  end

  creation_ind = Int[]   # Linear indices of creation operators in a monomial
  annihilation_ind = Int[]  # Linear indices of annihilation operators in a monomial
  terms = OperatorTerm{S}[]
  for (monomial, coeff) in op_expr
    empty!(creation_ind)
    empty!(annihilation_ind)
    annihilation_mask::FockState = 0
    creation_mask::FockState = 0
    for c_op in monomial.ops
      if c_op.dagger
        push!(creation_ind, soi[c_op.indices])
        creation_mask |= (one(FockState) << (soi[c_op.indices]-1))
      else
        push!(annihilation_ind, soi[c_op.indices])
        annihilation_mask |= (one(FockState) << (soi[c_op.indices]-1))
      end
    end
    push!(terms, OperatorTerm(coeff,
                              annihilation_mask,
                              creation_mask,
                              compute_count_mask(annihilation_ind),
                              compute_count_mask(creation_ind)))
  end
  Operator{HSType, S}(terms)
end

function parity_number_of_bits(v::FockState)
  x = copy(v)
  # http://graphics.stanford.edu/~seander/bithacks.html#CountBitsSetNaive
  x ⊻= (x >> 16)
  x ⊻= (x >> 8)
  x ⊻= (x >> 4)
  x ⊻= (x >> 2)
  x ⊻= (x >> 1)
  x & 0x01
end

"""Act on a state and return a new state"""
function Base.:*(op::Operator, st::StateType) where {StateType <: State}
  target_st = similar(st)
  for term in op.terms
    for (i, a) in pairs(st)
      f2 = st.hs[i]
      (f2 & term.annihilation_mask) != term.annihilation_mask && continue
      f2 &= ~term.annihilation_mask
      ((f2 ⊻ term.creation_mask) & term.creation_mask) !=
        term.creation_mask && continue
      f3 = ~(~f2 & ~term.creation_mask)
      sign = parity_number_of_bits((f2 & term.annihilation_count_mask) ⊻
                                   (f3 & term.creation_count_mask)) == 0 ? 1 : -1
      ind = getstateindex(target_st.hs, f3)
      target_st[ind] += a * term.coeff * sign
    end
  end
  target_st
end

##################
# SpacePartition #
##################

# Detailed description of the algorithm:
# Computer Physics Communications 200, March 2016, 274-284 (section 4.2)
# https://doi.org/10.1016/j.cpc.2015.10.023

"""
  Partition of a Hilbert space into a set of disjoint subspaces invariant under
  action of a given Hermitian operator (Hamiltonian).
"""
struct SpacePartition{HSType <: HilbertSpace, ScalarType <: Number}
  # Complete Hilbert space
  hs::HSType
  # Disjoint set of subspaces
  subspaces::IntDisjointSets
  # Map root index to subspace index
  root_to_index::Dict{Int, Int}
  # Matrix elements of the Hamiltonian
  matrix_elements::SparseMatrixCSC{ScalarType, Int}
end

"""Perform Phase I of the automatic partitioning algorithm"""
function SpacePartition{HSType, S}(hs::HSType,
                        H::OperatorType,
                        store_matrix_elements::Bool = true
                        ) where {HSType <: HilbertSpace,
                                 S <: Number,
                                 OperatorType <: Operator}
  subspaces = IntDisjointSets(length(hs))
  root_to_index = Dict{Int,Int}()
  matrix_elements = spzeros(S, length(hs), length(hs))

  init_state = StateDict{HSType, S}(hs)
  for i=1:length(hs)
    init_state[i] = one(S)

    final_state = H * init_state

    for (f, a) in pairs(final_state)
      isapprox(a, 0, atol = 1e-10) && continue
      i_subspace = find_root(subspaces, i)
      f_subspace = find_root(subspaces, f)
      i_subspace != f_subspace && root_union!(subspaces, i_subspace, f_subspace)
      if store_matrix_elements
        matrix_elements[i, f] = a
      end
    end

    init_state[i] = zero(S)
  end

  for i=1:length(hs)
    root = find_root(subspaces, i)
    if !(root in keys(root_to_index))
      root_to_index[root] = length(root_to_index) + 1
    end
  end

  SpacePartition{HSType, S}(hs, subspaces, root_to_index, matrix_elements)
end

"""Return the number of subspaces in space partition"""
numsubspaces(sp::SpacePartition) = length(sp.root_to_index)

"""Find what invariant subspace state with a given index belongs to"""
function Base.getindex(sp::SpacePartition, index)
  sp.root_to_index[find_root(sp.subspaces, index)]
end

"""
  Perform Phase II of the automatic partition algorithm

  Merge some of the invariant subspaces to ensure that a given operator `Cd`
  and its Hermitian conjugate `C` generate only one-to-one connections between
  the subspaces.
"""
function merge_subspaces!(sp::SpacePartition{HSType, S},
                          Cd::OperatorType,
                          C::OperatorType,
                          store_matrix_elements::Bool = true) where {
                           HSType <: HilbertSpace,
                           S <: Number,
                           OperatorType <: Operator}
  Cd_elements = spzeros(S, length(sp), length(sp))
  C_elements = spzeros(S, length(sp), length(sp))

  Cd_connections = SortedMultiDict{Int,Int}()
  C_connections = SortedMultiDict{Int,Int}()

  # Fill connection multidicts
  init_state = StateDict{HSType, S}(sp.hs)
  for i=1:length(sp)
    i_subspace = find_root(sp.subspaces, i)
    init_state[i] = one(S)

    fill_conn = (op, conn, matrix_elements) -> begin
      final_state = op * init_state
      for (f, a) in pairs(final_state)
        isapprox(a, 0, atol = 1e-10) && continue
        insert!(conn, i_subspace, find_root(sp.subspaces, f))
        if store_matrix_elements
          matrix_elements[i, f] = a
        end
      end
    end

    fill_conn(Cd, Cd_connections, Cd_elements)
    fill_conn(C, C_connections, C_elements)

    init_state[i] = zero(S)
  end

  # 'Zigzag' traversal algorithm
  while !isempty(Cd_connections)
    # Take one C^† - connection
    # C^†|lower_subspace> = |upper_subspace>
    lower_subspace, upper_subspace = first(Cd_connections)

    # The following lambda-function
    #
    # - reveals all subspaces reachable from lower_subspace by application of
    #   a 'zigzag' product C† C C† C C† ... of any length;
    # - removes all visited connections from Cd_connections/C_connections;
    # - merges lower_subspace with all subspaces generated from lower_subspace
    #   by application of (C C†)^(2*n);
    # - merges upper_subspace with all subspaces generated from upper_subspace
    #   by application of (C† C)^(2*n).
    zigzag_traversal = (i_subspace, upwards) -> begin
      conn = upwards ? Cd_connections : C_connections
      while (tok = searchequalrange(conn, i_subspace)[1]) != pastendsemitoken(conn)
        f_subspace = deref_value((conn, tok))
        delete!((conn, tok))

        if (upwards)
          union!(sp.subspaces, f_subspace, upper_subspace)
        else
          union!(sp.subspaces, f_subspace, lower_subspace)
        end

        # Recursively apply to all found f_subspace's with the 'flipped' direction
        zigzag_traversal(f_subspace, !upwards)
      end
    end

    # Apply to all C† connections starting from lower_subspace
    zigzag_traversal(lower_subspace, true)
  end

  # Rebuild sp.root_to_index
  empty!(sp.root_to_index)
  for i=1:length(sp)
    root = find_root(sp.subspaces, i)
    if !(root in keys(sp.root_to_index))
      sp.root_to_index[root] = length(sp.root_to_index) + 1
    end
  end

  return (Cd_elements, C_elements)
end

#######################################
# SpacePartition: Iteration interface #
#######################################
Base.eltype(sd::SpacePartition) = Pair{Int, Int}

Base.length(sp::SpacePartition) = length(sp.subspaces)
Base.isempty(sp::SpacePartition) = isempty(sp.subspaces)

Base.size(sp::SpacePartition) = (length(sp),)
Base.size(sp::SpacePartition, dim) = dim == 1 ? length(sp) : 1

Base.iterate(sp::SpacePartition) = (1 => sp[1], 1)
function Base.iterate(sp::SpacePartition, it)
  if it < length(sp)
    (it+1 => sp[it+1], it+1)
  else
    nothing
  end
end

Base.keys(sp::SpacePartition) = LinearIndices(1:length(sp))
Base.values(sp::SpacePartition) = [sp[i] for i=1:length(sp)]
Base.pairs(sp::SpacePartition) = collect(Iterators.Pairs(values(sp), keys(sp)))

end # module Hilbert