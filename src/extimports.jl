
# -----------------------------------------------------------------------------
# modules external to our own eco-system, rigorously separate using and import

using Parameters: @with_kw

using Random: shuffle

import Base: ==, length

using LinearAlgebra: norm, dot 

using StaticArrays

# -----------------------------------------------------------------------------
# JuLIP, SHIPs, etc : just use import throughout, this avoids bugs

import JuLIP

import JuLIP: alloc_temp, alloc_temp_d,
              cutoff,
              evaluate, evaluate_d,
              evaluate!, evaluate_d!,
              SitePotential,
              z2i, i2z, numz,
              read_dict, write_dict

import JuLIP.MLIPs: IPBasis, alloc_B, alloc_dB, combine

import JuLIP.Potentials: ZList, SZList
import JuLIP: JVec, AtomicNumber