
using SparseArrays: SparseMatrixCSC, sparse
using LinearAlgebra: mul!
using Combinatorics: permutations
using LinearAlgebra: rank, svd, Diagonal




"""
`struct SymmetricBasis`

### Constructors

Option 1: pass a `OneParticleBasis`
```julia
SymmetricBasis(φ, symgrp, basis1p, Bsel)
SymmetricBasis(φ, basis1p, Bsel)   # uses default symgrp = O3()
```
will first construct a `PIBasis` from these inputs and then call the second
constructor.


Option 1: pass a `PIBasis`
```julia
SymmetricBasis(φ, symgrp, pibasis)
SymmetricBasis(φ, pibasis)
```
If the PIbasis is already available, this directly constructs a 
resulting SymmetricBasis; all possible permutation-invariant basis functions 
will be symmetrised and then reduced to a basis (rather than spanning set)
"""
struct SymmetricBasis{BOP, PROP, SYM, REAL, VPROP} <: ACEBasis
   pibasis::PIBasis{BOP}
   A2Bmap::SparseMatrixCSC{PROP, Int}
   symgrp::SYM
   real::REAL
   B_pool::VectorPool{VPROP}
end

Base.length(basis::SymmetricBasis{BOP, PROP}) where {BOP, PROP} =
      size(basis.A2Bmap, 1)

valtype(basis::SymmetricBasis{BOP, PROP}) where {BOP, PROP} = basis.real(PROP)

# TODO: this is not nice, there should be proper promotion 
valtype(basis::SymmetricBasis{BOP, PROP}, X::AbstractState) where {BOP, PROP} = 
      valtype(basis)

gradtype(basis::SymmetricBasis, X::AbstractState) = gradtype(basis, typeof(X))

function gradtype(basis::SymmetricBasis, cfgorX)
   φ = zero(eltype(basis.A2Bmap))
   dAA = zero(gradtype(basis.pibasis, cfgorX))
   # note up to 0.12.4, basis.real used to be replaced with _real1234 
   # a weird hacky thing. not sure why it now works with basis.real
   return typeof( basis.real( coco_o_daa(φ, dAA) ))
end


# -------- FIO

==(B1::SymmetricBasis, B2::SymmetricBasis) = 
      ( (B1.pibasis == B2.pibasis) && 
        (B1.A2Bmap == B2.A2Bmap) && 
        (B1.real == B2.real) )

write_dict(B::SymmetricBasis{BOP, PROP}) where {BOP, PROP} =
      Dict( "__id__" => "ACE_SymmetricBasis",
            "pibasis" => write_dict(B.pibasis),
            "A2Bmap" => write_dict(B.A2Bmap),
            "symgrp" => write_dict(B.symgrp), 
            "isreal" => (B.real == Base.real) )

read_dict(::Val{:ACE_SymmetricBasis}, D::Dict) =
      SymmetricBasis(read_dict(D["pibasis"]),
                     read_dict(D["A2Bmap"]),
                     read_dict(D["symgrp"]), 
                     (D["isreal"] ? Base.real : Base.identity) )
# --------

SymmetricBasis(φ::AbstractProperty, 
               basis1p::OneParticleBasis, 
               Bsel::AbstractBasisSelector; 
               kwargs...) =
      SymmetricBasis(φ, basis1p, O3(), Bsel; kwargs...)

SymmetricBasis(φ::AbstractProperty, pibasis; kwargs...) = 
      SymmetricBasis(φ, O3(), pibasis; kwargs...)


SymmetricBasis(φ::AbstractProperty, 
               basis1p::OneParticleBasis, 
               symgrp::SymmetryGroup, 
               Bsel::AbstractBasisSelector; 
               isreal=isrealB(φ), kwargs...) =
      SymmetricBasis(φ, symgrp, 
                     PIBasis(basis1p, symgrp, Bsel; 
                             isreal = isrealAA(φ), kwargs..., property = φ); 
                     isreal=isreal)

function SymmetricBasis(φ::TP, symgrp::SymmetryGroup, pibasis; 
                        isreal=false) where {TP}

   # AA index -> AA spec
   AAspec = get_spec(pibasis)

   # construct the reverse mapping AA spec -> iAA and A spec -> iA
   invAAspec = Dict{Any, Int}()
   for (iAA, AA) in enumerate(AAspec)
      invAAspec[AA] = iAA
   end
   invAspec = Dict{Any, Int}()
   for (iA, A) in enumerate(get_spec(pibasis.basis1p))
      invAspec[A] = iA
   end

   # allocate the datastructure that computes and caches the
   # coupling coefficients
   # TODO: should this be stored with the basis?
   #       or maybe written to a file on disk? and then flushed every time
   #       we finish with a basis construction???
   rotc = Rot3DCoeffs(φ, real(valtype(pibasis)))
   # allocate triplet format
   Irow, Jcol, vals = Int[], Int[], TP[]
   # count the number of PI basis functions = number of rows
   idxB = 0

   # loop through AA basis, but skip most of them ...
   for (iAA, AA) in enumerate(AAspec)
      # determine whether we need to compute coupling coefficients for this 
      # basis function or whether it will be included in a different 
      # coco computation? 
      if !is_refbasisfcn(symgrp, AA)
         continue 
      end 
      # compute the cocos 
      U, AAcols = coupling_coeffs(symgrp, AA, rotc)

      # loop over the rows of U -> each specifies a basis function which we now 
      # need to incorporate into the basis
      for irow = 1:size(U, 1)
         idxB += 1
         # loop over the columns of U / over brows
         for (icol, bcol) in enumerate(AAcols)
            # put bcol into the correct order
            bcol_ordered = _get_ordered(bcol, invAspec)
            # this is a subtle step: bcol and bcol_ordered are equivalent
            # permutation-invariant basis functions. This means we will
            # add the same PI basis function several times, but in the call to
            # `sparse` the values will just be added.
            if !haskey(invAAspec, bcol_ordered)
               @show bcol_ordered
               @show degree(bcol_ordered, NaiveTotalDegree(), pibasis.basis1p)
            end
            idxAA = invAAspec[bcol_ordered]
            push!(Irow, idxB)
            push!(Jcol, idxAA)
            push!(vals, U[irow, icol])
         end
      end
   end
   # TODO: filter and throw out everything that hasn't been used!!
   # create CSC: [   triplet    ]  nrows   ncols
   A2Bmap = sparse(Irow, Jcol, vals, idxB, length(AAspec))
   return SymmetricBasis(pibasis, A2Bmap, symgrp, isreal ? Base.real : Base.identity)
end

function SymmetricBasis(pibasis, A2Bmap, symgrp, _real) 
   PROP = _real(eltype(A2Bmap))
   B_pool = VectorPool{PROP}() 
   return SymmetricBasis(pibasis, A2Bmap, symgrp, _real, B_pool)
end


"""
produce the ordered tuple defining the AA basis function uniquely.
"""
function _get_ordered(bb, invAspec)
   iAs = [invAspec[b] for b in bb]
   return bb[ sortperm(iAs, rev = true) ]
end


# ------------------- exporting the basis spec 

# this doesn't provide the "full" specification, just collects 
# the n and l but not the m or coupling coefficients. 

function get_spec(basis::SymmetricBasis)
   spec_AA = get_spec(basis.pibasis)
   spec_B = [] 
   for iB = 1:length(basis)
      iAA = findfirst(norm.(basis.A2Bmap[iB, :]) .!= 0)
      push!(spec_B, get_sym_spec(basis.symgrp, spec_AA[iAA]))
   end
   return identity.(spec_B)
end

# ---------------- A modified sparse matmul

# TODO: move this stuff all to aux? 

using SparseArrays: AbstractSparseMatrixCSC,
				        nonzeros, rowvals, nzrange

using LinearAlgebra: Transpose

function genmul!(C, A::AbstractSparseMatrixCSC, B, mulop)
    size(A, 2) == size(B, 1) || throw(DimensionMismatch())
    size(A, 1) == size(C, 1) || throw(DimensionMismatch())
    size(B, 2) == size(C, 2) || throw(DimensionMismatch())
    nzv = nonzeros(A)
    rv = rowvals(A)
    fill!(C, zero(eltype(C)))
    for k in 1:size(C, 2)
        @inbounds for col in 1:size(A, 2)
            αxj = B[col,k]
            for j in nzrange(A, col)
                C[rv[j], k] += mulop(nzv[j], αxj)
            end
        end
    end
    return C
end


function genmul!(C, xA::Transpose{<:Any,<:AbstractSparseMatrixCSC}, B, mulop)
   A = xA.parent
   size(A, 2) == size(C, 1) || throw(DimensionMismatch())
   size(A, 1) == size(B, 1) || throw(DimensionMismatch())
   size(B, 2) == size(C, 2) || throw(DimensionMismatch())
   nzv = nonzeros(A)
   rv = rowvals(A)
   fill!(C, zero(eltype(C)))
   for k in 1:size(C, 2)
       @inbounds for col in 1:size(A, 2)
           tmp = zero(eltype(C))
           for j in nzrange(A, col)
               tmp += mulop(nzv[j], B[rv[j],k])
           end
           C[col,k] += tmp
       end
   end
   return C
end

#dispatching for SVectors and B being a list of matrices rather than a single matrix
#the function below does the same, but return identical coppies for all properties
#only works on things that are parameter independent. 
function adjointgenmul!(C::AbstractVector{<: SVector}, A::AbstractSparseMatrixCSC, B, mulop)
   for prop in 1:length(C[1]) #TODO is it worth checking everything?
      size(A, 2) == size(B[prop], 1) || throw(DimensionMismatch())
      size(B[prop], 2) == size(C, 2) || throw(DimensionMismatch())
   end
   size(A, 1) == size(C, 1) || throw(DimensionMismatch())
   nzv = nonzeros(A)
   rv = rowvals(A)
   fill!(C, zero(eltype(C)))
   for k in 1:size(C, 2)
      for prop in 1:length(C[1]) #we add this loop over properties
         @inbounds for col in 1:size(A, 2)
            αxj = B[prop][col,k]
            for j in nzrange(A, col)
                  mop = mulop(nzv[j], αxj) #find the value we need
                  zerotmp = zeros(length(C[1])) #make an array of zeros
                  zerotmp[prop] = 1 #put a one only in the current position
                  tmp = SVector{length(C[1])}(zerotmp) #make it an SVector
                  C[rv[j], k] += mop * tmp #this should add only on the current property
            end
         end
      end
   end
   return C
end

#TODO, is this worth having? 
#dispatching for SVectors
#here we simply pass a coppy or a fill() or the mulop to every
#property on the SVector.
function genmul!(C::AbstractVector{<: SVector}, A::AbstractSparseMatrixCSC, B, mulop)
   size(A, 2) == size(B, 1) || throw(DimensionMismatch())
   size(A, 1) == size(C, 1) || throw(DimensionMismatch())
   size(B, 2) == size(C, 2) || throw(DimensionMismatch())
   nzv = nonzeros(A)
   rv = rowvals(A)
   fill!(C, zero(eltype(C)))
   for k in 1:size(C, 2)
       @inbounds for col in 1:size(A, 2)
           αxj = B[col,k]
           for j in nzrange(A, col)
               mop = mulop(nzv[j], αxj)
               C[rv[j], k] += mop * ones(SVector{length(C[1]),eltype(mop)})
           end
       end
   end
   return C
end

# ---------------- Evaluation code


function evaluate!(B, basis::SymmetricBasis, cfg::AbstractConfiguration)
   # compute AA
   AA = acquire_B!(basis.pibasis, cfg)
   evaluate!(AA, basis.pibasis, cfg)
   return evaluate!(B, basis, AA)
end

# this function allows us to attach multiple symmetric bases to a single
#     𝑨 basis
#  TODO: this is extremely inefficient for multiple species But it is simple
#        and clean and will do for now...
function evaluate!(B, basis::SymmetricBasis, AA::AbstractVector{<: Number})
   genmul!(B, basis.A2Bmap, AA, (a, b) -> basis.real(a * b))
end


# ---------------- gradients

function evaluate_d!(dB, basis::SymmetricBasis, cfg::AbstractConfiguration, 
                     args...)   # args... could be nothing or sym
   # compute AA
   AA = acquire_B!(basis.pibasis, cfg)
   dAA = acquire_dB!(basis.pibasis, cfg)
   evaluate_ed!(AA, dAA, basis.pibasis, cfg, args...)
   evaluate_d!(dB, basis, AA, dAA)
   return dB
end


function evaluate_d!(dB, basis::SymmetricBasis,
                     AA::AbstractVector{<: Number}, dAA)
   # note up to 0.12.4, basis.real used to be replaced with _real1234 
   # a weird hacky thing. not sure why it now works with basis.real
   genmul!(dB, basis.A2Bmap, dAA, 
           (a, b) -> basis.real( ACE.coco_o_daa(a, b) ) )
end

function scaling(basis::SymmetricBasis, p)
   wwpi = scaling(basis.pibasis, p)
   wwrpi = abs2.(norm.(basis.A2Bmap)) * abs2.(wwpi)
   return sqrt.(wwrpi)
end
