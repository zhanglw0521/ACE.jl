
# --------------------------------------------------------------------------
# ACE.jl and SHIPs.jl: Julia implementation of the Atomic Cluster Expansion
# Copyright (c) 2019 Christoph Ortner <christophortner0@gmail.com>
# All rights reserved.
# --------------------------------------------------------------------------





const zklmTuple = NamedTuple{(:z, :k, :l, :m), Tuple{Int16, IntS, IntS, IntS}}

"""
`AList` : datastructure to help compute the A_zklm density projections

* `i2zklm` : list of all admissible `(z,k,l,m)` tuples
* `zklm2i` : dictionary with (z,k,l,m) keys to compute  the map `(z,k,l,m) -> i`
* `firstz` : `firstz[iz]` stores the first index in the A_zklm array for with
             z = zi. This can be used to iterate over all A entries for which
             z = zi. (they are sorted by z first)
"""
struct AList
   i2zklm::Vector{zklmTuple}
   zklm2i::Dict{zklmTuple, IntS}
   firstz::Vector{IntS}
end

Base.length(alist::AList) = length(alist.i2zklm)
Base.getindex(alist::AList, i::Integer) = alist.i2zklm[i]
Base.getindex(alist::AList, zklm::zklmTuple) = alist.zklm2i[zklm]

alloc_A(alist::AList, T=Float64) = zeros(Complex{T}, length(alist))

function AList(zklmlist::AbstractVector{zklmTuple})
   # sort the tuples - by z, then k, then l, then m
   i2zklm = sort(zklmlist)
   # create the inverse mapping
   zklm2i = Dict{zklmTuple, IntS}()
   for i = 1:length(i2zklm)
      zklm2i[i2zklm[i]] = IntS(i)
   end
   # find the first index for each z
   zmax = maximum( a.z for a in i2zklm )
   firstz = [ findfirst([a.z == iz for a in i2zklm])
              for iz = 1:zmax ]
   return AList( i2zklm, zklm2i, [firstz; length(i2zklm)+1] )
end



# ---------

const zzkkllmmTuple{N} = SVector{N, zklmTuple}

"""
`AAList` : datastructure to help compute the A_𝐳𝐤𝐥𝐦 = ∏ A_zklm

* `i2Aidx` : indices in AList of the zklms to avoid the Dict lookup
* `len`    : len[i] is the number of relevant entries of i2zklm[i,:]
             i.e. the body-order of this entry
* `zklm2i` : dictionary of all (z,k,l,m) tuples to compute  the
             map `(z,k,l,m) -> i`
* `firstz` : `firstz[iz]` stores the first index in the A_zklm array for with
             z = zi. This can be used to iterate over all A entries for which
             z = zi. (they are sorted by z first)
"""
struct AAList
   i2Aidx::Matrix{IntS}
   len::Vector{IntS}
   zklm2i::Dict{Any, IntS}
end

Base.length(aalist::AAList) = length(aalist.len)

Base.getindex(aalist::AAList, t::Tuple) = aalist.zklm2i[t]

alloc_AA(aalist::AAList, T = Float64) = zeros(Complex{T}, length(aalist))

function AAList(ZKLM_list, alist)
   BO = maximum(ν -> length(ν[1]), ZKLM_list)  # body-order -> size of iAidx

   # create arrays to construct AAList
   iAidx = IntS[]
   len = IntS[]
   zklm2i = Dict{Any, IntS}()

   idx = 0
   for (izz, kk, ll, mm) in ZKLM_list
      # store in the index of the current row in the reverse map
      idx += 1
      zklm2i[(izz, kk, ll, mm)] = idx
      # store the body-order of the current ∏A function
      push!(len, length(ll))

      # fill the row of the i2Aidx matrix
      for α = 1:length(ll)
         zklm = (z=izz[α], k=kk[α], l=ll[α], m=IntS(mm[α]))
         iA = alist[zklm]
         push!(iAidx, iA)
      end
      # fill up the iAidx vector with zeros up to the body-order
      # this will create 0 entries in the matrix after reshaping
      for α = (length(ll)+1):BO
         push!(iAidx, 0)
      end
   end
   return AAList( reshape(iAidx, (BO, idx))', len, zklm2i )
end




# --------------------------------------------------------

"""
convert the "old" `(NuZ, ZKL)` format into the simpler (zz, kk, ll, mm)
format, and at the same time extract the one-particle basis (z, k, l, m)
"""
function alists_from_bgrps(bgrps::Tuple)
   NZ = length(bgrps)
   zzkkllmm_list = [ Tuple[] for _=1:NZ ]
   zklm_set = [ Set() for _=1:NZ ]
   for iz0 = 1:NZ
      for (izz, kk, ll) in bgrps[iz0], mm in _mrange(ll)
         push!(zzkkllmm_list[iz0], (izz, kk, ll, IntS.(mm)))
         for α = 1:length(ll)
            zklm = (z=izz[α], k=kk[α], l=ll[α], m=IntS(mm[α]))
            push!(zklm_set[iz0], zklm)
         end
      end
   end

   alist =  ntuple(iz0 -> AList([ zklm for zklm in collect(zklm_set[iz0]) ]), NZ)
   aalist = ntuple(iz0 -> AAList(zzkkllmm_list[iz0], alist[iz0]), NZ)
   return alist, aalist
end


# --------------------------------------------------------

using SparseArrays: SparseMatrixCSC

function _my_mul!(C::AbstractVector, A::SparseMatrixCSC, B::AbstractVector)
   A.n == length(B) || throw(DimensionMismatch())
   A.m == length(C) || throw(DimensionMismatch())
   nzv = A.nzval
   rv = A.rowval
   fill!(C, zero(eltype(C)))
   @inbounds for col = 1:A.n
      b = B[col]
      for j = A.colptr[col]:(A.colptr[col + 1] - 1)
         C[rv[j]] += nzv[j] * b
      end
   end
   return C
end