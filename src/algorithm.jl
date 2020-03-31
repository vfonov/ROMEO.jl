function growRegionUnwrap!(wrapped, weights, nbins, getnewseed!, max_seeds=100)
    stridelist = strides(wrapped)
    visited = zeros(UInt8, size(wrapped))
    notvisited(i) = checkbounds(Bool, visited, i) && (visited[i] == 0)
    pqueue = PQueue{Int}(nbins)
    seeds = Int[]
    weight_thresh = addseed!(seeds, pqueue, visited, weights, nbins, getnewseed!)

    while !isempty(pqueue)
        if length(seeds) < max_seeds && pqueue.min > weight_thresh
            weight_thresh = addseed!(seeds, pqueue, visited, weights, nbins, getnewseed!)
        end
        edge = pop!(pqueue)
        oldvox, newvox = getvoxelsfromedge(edge, visited, stridelist)
        if visited[newvox] == 0
            unwrapedge!(wrapped, oldvox, newvox)
            visited[newvox] = visited[oldvox]
            for i in 1:6 # 6 directions
                e = getnewedge(newvox, notvisited, stridelist, i)
                if e != 0 && weights[e] > 0
                    push!(pqueue, e, weights[e])
                end
            end
        end
    end
    return wrapped
end

function addseed!(seeds, pqueue, visited, weights, nbins, getnewseed!)
    seed = getnewseed!(visited)
    push!(seeds, seed)
    push!(pqueue, seed, 1)
    visited[getfirstvoxfromedge(seed)] = length(seeds)
    weight_thresh = nbins - div(nbins - weights[seed], 2)
    return weight_thresh
end

function getvoxelsfromedge(edge, visited, stridelist)
    dim = getdimfromedge(edge)
    vox = getfirstvoxfromedge(edge)
    neighbor = vox + stridelist[dim] # direct neigbor in dim
    if visited[neighbor] == 0
        return vox, neighbor
    else
        return neighbor, vox
    end
end

# edge calculations
getdimfromedge(edge) = (edge - 1) % 3 + 1
getfirstvoxfromedge(edge) = div(edge - 1, 3) + 1
getedgeindex(leftvoxel, dim) = dim + 3(leftvoxel-1)

function unwrapedge!(wrapped, oldvox, newvox)
    wrapped[newvox] = unwrapvoxel(wrapped[newvox], wrapped[oldvox])
end
unwrapvoxel(new, old) = new - 2pi * round((new - old) / 2pi)

function getnewedge(v, notvisited, stridelist, i)
    iDim = div(i+1,2)
    n = stridelist[iDim] # neigbor-offset in dimension iDim
    if iseven(i)
        if notvisited(v+n) getedgeindex(v, iDim) else 0 end
    else
        if notvisited(v-n) getedgeindex(v-n, iDim) else 0 end
    end
end
