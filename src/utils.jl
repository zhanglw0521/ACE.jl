
# --------------------------------------------------------------------------
# ACE.jl and SHIPs.jl: Julia implementation of the Atomic Cluster Expansion
# Copyright (c) 2019 Christoph Ortner <christophortner0@gmail.com>
# All rights reserved.
# --------------------------------------------------------------------------


module Utils

# import ACE.RPI: RnYlm1pBasis, SparsePSHDegree, RPIBasis, get_maxn
import ACE: PolyTransform, transformed_jacobi, RnYlm1pBasis,
            SparsePSHDegree, get_maxn
# import ACE.PairPotentials: PolyPairBasis

# - simple ways to construct a radial basis
# - construct a descriptor
# - simple wrappers to generate RPI basis functions (ACE + relatives)

# export rpi_basis, descriptor, pair_basis, ace_basis

radial_basis(; r0 = 2.5,
               trans = PolyTransform(2, r0),
               maxn = 10,
               rcut = 5.0,
               rin = 0.5 * r0,
               pcut = 2,
               pin = 0 ) =
      transformed_jacobi(maxn, trans, rcut, rin;
                                  pcut=pcut, pin=pin)

RnYlm_basis(; species = :X, D = SparsePSHDegree(), maxdeg = 8, kwargs...)  =
      RnYlm1pBasis(
            radial_basis(maxn = get_maxn(D, maxdeg, species), kwargs...);
            species = species, D = D )



# function rpi_basis(; species = :X, N = 3,
#       # transform parameters
#       r0 = 2.5,
#       trans = PolyTransform(2, r0),
#       # degree parameters
#       D = SparsePSHDegree(),
#       maxdeg = 8,
#       # radial basis parameters
#       rcut = 5.0,
#       rin = 0.5 * r0,
#       pcut = 2,
#       pin = 0,
#       constants = false,
#       rbasis = transformed_jacobi(get_maxn(D, maxdeg, species), trans, rcut, rin;
#                                   pcut=pcut, pin=pin),
#       # one-particle basis
#       Basis1p = RnYlm1pBasis,
#       basis1p = Basis1p(rbasis; species = species, D = D) )
#
#    return RPIBasis(basis1p, N, D, maxdeg, constants)
# end
#
# descriptor = rpi_basis
# ace_basis = rpi_basis
#
# function pair_basis(; species = :X,
#       # transform parameters
#       r0 = 2.5,
#       trans = PolyTransform(2, r0),
#       # degree parameters
#       maxdeg = 8,
#       # radial basis parameters
#       rcut = 5.0,
#       rin = 0.5 * r0,
#       pcut = 2,
#       pin = 0,
#       rbasis = transformed_jacobi(maxdeg, trans, rcut, rin; pcut=pcut, pin=pin))
#
#    return PolyPairBasis(rbasis, species)
# end




end
