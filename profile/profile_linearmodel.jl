

using ACE, ACEbase
using Printf, LinearAlgebra, ACE.Testing, Random
using ACE: evaluate, evaluate_d, SymmetricBasis, SimpleSparseBasis, PIBasis, 
           PositionState
using ACEbase.Testing: fdtest
using Profile, ProfileSVG, TimerOutputs, BenchmarkTools

##

# construct the 1p-basis
maxdeg = 14
ord = 4
wL = 1.5
Bsel = SparseBasis(; maxorder = ord, p = 1, default_maxdeg = maxdeg, 
                     weight = Dict(:n => 1.0, :l => wL))

B1p = ACE.Utils.RnYlm_1pbasis(maxdeg = maxdeg, maxL = ceil(Int, maxdeg/wL), 
                              Bsel = Bsel)

# generate a configuration
nX = 10
Xs = rand(PositionState{Float64}, B1p.bases[1], nX)
cfg = ACEConfig(Xs)

φ = ACE.Invariant()
basis = SymmetricBasis(φ, B1p, Bsel)
@show length(basis)

BB = evaluate(basis, cfg)
c = rand(length(BB)) .- 0.5

standard = ACE.LinearACEModel(basis, c, evaluator = :standard)

##

@info("Time evaluate incl allocation")
(@btime evaluate($standard, $cfg))

##

@info("Time grad_config with and without allocation")
@info("This looks like a factor 4.5 of evaluate, so probably more we can do")
g = ACE.acquire_grad_config!(standard, cfg)
(@btime ACE.grad_config($standard, $cfg))
(@btime ACE.grad_config!($g, $standard, $cfg))

# [ Info: Time grad_config with and without allocation
# [ Info: This looks like a factor 4.5 of evaluate, so probably more we can do
#   283.584 μs (6 allocations: 275.34 KiB)
#   283.458 μs (5 allocations: 275.05 KiB)

##

@info("Time grad_params with and without allocation")
@info("a little surprising we dont get closer to factor 1?")
g = ACE.acquire_grad_params!(standard, cfg)
(@btime ACE.grad_params($standard, $cfg))
(@btime ACE.grad_params!($g, $standard, $cfg))


##

function runn(N, f, args...)
   t = f(args...)
   for n = 2:N
     t = f(args...)
   end 
   t
end

##

Profile.clear()
@profile runn(20_000, ACE.grad_config, standard, cfg);
Profile.print()

##

ProfileSVG.view()


##

# # make sure to add suitable @timeit macros to the module
# @info("Detailed benchmarking of grad_config")
# reset_timer!()
# @timeit "grad_config" runn(10, ACE.grad_config, standard, cfg);
# print_timer()