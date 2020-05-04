function unwrap!(wrapped::AbstractArray; individual=false, keyargs...)
    if individual return unwrap_individual!(wrapped; keyargs...) end
    nbins = 256
    sz = size(wrapped)
    @assert ndims(wrapped) <= 3 "This is 3D (4D) unwrapping! data is $(ndims(wrapped))D"
    if ndims(wrapped) <= 2 # algorithm requires 3D input
        wrapped = reshape(wrapped, size(wrapped)..., ones(Int, 3-ndims(wrapped))...)
    end

    weights = calculateweights(wrapped, nbins; keyargs...)
    @assert sum(weights) != 0 "Unwrap-weights are all zero!"

    seed = findseed(wrapped, weights)
    if haskey(keyargs, :phase2) && haskey(keyargs, :TEs) # requires multiecho
        seedcorrection!(wrapped, seed, keyargs[:phase2], keyargs[:TEs])
    end

    growRegionUnwrap!(wrapped, weights, seed, nbins)

    if haskey(keyargs, :correctglobal) && keyargs[:correctglobal]
        mask = if haskey(keyargs, :mask)
            keyargs[:mask]
        else
            trues(size(wrapped))
        end
        wrapped .-= (2π * median(round.(filter(isfinite, wrapped[mask]) ./ 2π)))
    end
    return reshape(wrapped, sz)
end

"""
    unwrap(wrapped::AbstractArray; keyargs...)

ROMEO unwrapping.

###  Optional keyword arguments:

- `weights`: Options are [`:romeo`] | `:romeo2` | `:romeo3` | `:bestpath`.
- `individual`: If `true` perform individual unwrapping of echos.
- `mag`: Additional mag weights are used.
- `mask`: Unwrapping is only performed inside the mask.
- `phase2`: A second reference phase image (possibly with different echo time).
   It is used for calculating the phasecoherence weight.
- `TEs`: The echo times of the phase and the phase2 images as a tuple (eg. (5, 10) or [5, 10]).
- `correctglobal`: If `true` corrects for global n2π offsets.

"""
unwrap(wrapped; keyargs...) = unwrap!(copy(wrapped); keyargs...)

function unwrap!(wrapped::AbstractArray{T,4}; TEs, template=2, p2ref=1, keyargs...) where T
    args = Dict{Symbol, Any}(keyargs)
    args[:phase2] = wrapped[:,:,:,p2ref]
    args[:TEs] = TEs[[template, p2ref]]
    if haskey(args, :mag)
        args[:mag] = args[:mag][:,:,:,template]
    end
    @time weights = calculateweights(view(wrapped,:,:,:,template); args...)
    @time unwrap!(view(wrapped,:,:,:,template); weights=weights, args...) # TODO check if weights is already in args...
    quality = similar(wrapped)
    V = falses(size(wrapped))
    @time for ieco in [(template-1):-1:1; (template+1):length(TEs)]
        iref = if (ieco < template) ieco+1 else ieco-1 end
        refvalue = wrapped[:,:,:,iref] .* (TEs[ieco] / TEs[iref])
        w = view(wrapped,:,:,:,ieco)
        w .= unwrapvoxel.(w, refvalue)
        quality[:,:,:,ieco] .= getquality.(w, refvalue)
        visited = quality[:,:,:,ieco] .< π/2
        mask = if haskey(keyargs, :mask)
            keyargs[:mask]
        else
            dropdims(sum(weights; dims=1); dims=1) .< 100
        end
        @show sum(.!visited)
        #visited[.!mask] .= true
        @show sum(.!visited)
        V[:,:,:,ieco] = visited
        if any(visited) && !all(visited)
            edges = getseededges(visited)
            edges = filter(e -> weights[e] != 0, edges)
            growRegionUnwrap!(w, weights, edges, 256, visited)
        end
    end
    return wrapped, quality, weights, V
end

function getquality(vox, ref)
    return abs(vox - ref)
end

function getseededges(visited::BitArray)
    stridelist = strides(visited)
    edges = Int64[]
    for dim in 1:3, I in LinearIndices(visited)
        J = I + stridelist[dim]
        if checkbounds(Bool, visited, J) # borders should be no problem due to invalid weights
            if visited[I] + visited[J] == 1 # one visited and one not visited
                push!(edges, getedgeindex(I, dim))
            end
        end
    end
    return edges
end

unwrap_individual(wrapped; keyargs...) = unwrap_individual!(copy(wrapped); keyargs...)
function unwrap_individual!(wrapped::AbstractArray{T,4}; TEs, keyargs...) where T
    for i in 1:length(TEs)
        e2 = if (i == 1) 2 else i-1 end
        echoes = [i, e2]
        args = Dict()
        if haskey(keyargs, :mag) args[:mag] = keyargs[:mag][:,:,:,i] end
        unwrap!(view(wrapped,:,:,:,i); phase2=wrapped[:,:,:,e2], TEs=TEs[echoes], args...)
    end
    return wrapped
end
