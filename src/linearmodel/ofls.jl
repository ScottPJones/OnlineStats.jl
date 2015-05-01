
# implements the online flexible least squares algorithm... modeled on Montana et al (2009):
#   "Flexible least squares for temporal data mining and statistical arbitrage"

# Our cost function: Cₜ(βₜ; μ) = (yₜ - xₜ'βₜ)² + μ Δβₜ
#   Below we use Vω = μ⁻¹Iₚ  along with a nicer to use relationship: μ = (1 - δ) / δ
#   We accept 0 <= δ <= 1 as a constructor argument which controls the weighting of new observations
#   δ close to 0 corresponds to large μ, which means the parameter vector β changes slowly
#   δ close to 1 corresponds to small μ, which means the parameter vector β changes quickly


# TODO: allow for time-varying Vω???
#  to accomplish... lets represent Vω as a vector of Var's (i.e. the diagonal of Vω)

# TODO: track Var of y/x's, and normalize/denormalize before update

#-------------------------------------------------------# Type and Constructors

type OnlineFLS <: OnlineStat
	p::Int  		# number of independent vars
	Vω::MatF    # pxp (const) covariance matrix of Δβₜ
	# Vω::Vector{Var}
	Vε::Var     # variance of error term... use exponential weighting with δ as the weight param
	yvar::Var   # used for normalization
	xvars::Vector{Var}  # used for normalization

	n::Int
	β::VecF 		# the current estimate in: yₜ = Xₜβₜ + εₜ

	# these are needed to update β
	R::MatF     # pxp matrix
	q::Float64  # called Q in paper
	K::VecF     # px1 vector (equivalent to Kalman gain)

	yhat::Float64  #most recent estimate of y

	function OnlineFLS(p::Int, δ::Float64, wgt::Weighting = default(Weighting))

		# calculate the covariance matrix Vω from the smoothing parameter δ
		@assert δ > 0. && δ <= 1.
		μ = (1. - δ) / δ
		Vω = eye(p) / μ
		println("μ = ", μ)
		println("Vω:\n", Vω)

		# wgt = ExponentialWeighting(δ)
		Vε = Var(wgt)
		yvar = Var(wgt)
		xvars = Var[Var(wgt) for i in 1:p]
		
		# create and init the object
		o = new(p, Vω, Vε, yvar, xvars)
		empty!(o)
		o
	end
end


function OnlineFLS(y::Float64, x::VecF, δ::Float64, wgt::Weighting = default(Weighting))
	p = length(x)
	o = OnlineFLS(p, δ, wgt)
	update!(o, y, x)
	o
end

function OnlineFLS(y::VecF, X::MatF, δ::Float64, wgt::Weighting = default(Weighting))
	p = size(X,2)
	o = OnlineFLS(p, δ, wgt)
	update!(o, y, X)
	o
end

#-----------------------------------------------------------------------# state

statenames(o::OnlineFLS) = [:β, :σy, :σx, :σε, :yhat, :nobs]
state(o::OnlineFLS) = Any[β(o), sqrt(var(o.yvar)), sqrt(map(var,o.xvars)), sqrt(var(o.Vε)), o.yhat, nobs(o)]

β(o::OnlineFLS) = o.β
Base.beta(o::OnlineFLS) = o.β

#---------------------------------------------------------------------# update!

if0then1(x::Float64) = (x == 0. ? 1. : x)

normalize_y(o::OnlineFLS, y::Float64) = (y - mean(o.yvar)) / if0then1(var(o.yvar))
normalize_x(o::OnlineFLS, x::VecF) = (x - map(mean, o.xvars)) ./ map(x->if0then1(var(x)), o.xvars)
denormalize_y(o::OnlineFLS, y::Float64) = y * var(o.yvar) + mean(o.yvar)
denormalize_x(o::OnlineFLS, x::VecF) = x .* map(var, o.xvars) + map(mean, o.xvars)


# NOTE: assumes X mat is (T x p), where T is the number of observations
# TODO: optimize
function update!(o::OnlineFLS, y::VecF, X::MatF)
	@assert length(y) == size(X,1)
	for i in length(y)
		update!(o, y[i], vec(X[i,:]))
	end
end

function update!(o::OnlineFLS, y::Float64, x::VecF)

	# update x/y vars and normalize
	# @LOG y x
	# @LOG o.yvar o.xvars
	update!(o.yvar, y)
	for (i,xi) in enumerate(x)
		update!(o.xvars[i], xi)
	end
	# @LOG o.yvar o.xvars

	y = normalize_y(o, y)
	x = normalize_x(o, x)
	# @LOG y x

	# calc error and update error variance
	yhat = dot(x, o.β)
	ε = y - yhat
	update!(o.Vε, ε)
	
	# update sufficient stats to get the Kalman gain
	o.R += o.Vω - (o.q * o.K) * o.K'
	Rx = o.R * x
	o.q = dot(x, Rx) + var(o.Vε)
	o.K = Rx / if0then1(o.q)

	# @LOG ε var(o.Vε)
	# @LOG diag(o.R)
	# @LOG Rx
	# @LOG o.q
	# @LOG o.K

	# update β
	o.β += o.K * ε

	@LOG o.β

	# finish
	o.yhat = denormalize_y(o, yhat)
	o.n += 1
	return

end

# NOTE: keeps consistent p... just resets state
function Base.empty!(o::OnlineFLS)
	p = o.p
	empty!(o.Vε)
	o.n = 0
	o.β = zeros(p)

	# since Rₜ = Pₜ₋₁ + Vω, and P₀⁻¹ ≃ 0ₚ, lets initialize R with a big number along the diagonals
	# o.R = zeros(p,p)
	# o.R = eye(p)
	o.R = copy(o.Vω)
	
	o.q = 0.
	o.K = zeros(p)
	o.yhat = 0.
end

function Base.merge!(o1::OnlineFLS, o2::OnlineFLS)
	# TODO
end


function StatsBase.coef(o::OnlineFLS)
	# TODO
end

function StatsBase.coeftable(o::OnlineFLS)
	# TODO
end

function StatsBase.confint(o::OnlineFLS, level::Float64 = 0.95)
	# TODO
end

# predicts yₜ for a given xₜ
function StatsBase.predict(o::OnlineFLS, x::VecF)
	yhat = denormalize_y(o, dot(o.β, normalize_x(o, x)))
end

# NOTE: uses most recent estimate of βₜ to predict the whole matrix
function StatsBase.predict(o::OnlineFLS, X::MatF)
	n = size(X,1)
	pred = zeros(n)
	for i in 1:n
		pred[i] = StatsBase.predict(o, vec(X[i,:]))
	end
	pred
end



