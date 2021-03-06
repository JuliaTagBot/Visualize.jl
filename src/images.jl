@field SpatialOrder = (1, 2) # default value for SpatialOrder (xy)

"""
Do a custom convert for SpatialOrder. Partial is left untyped, since this should apply
to all SpatialOrders in all parent composables.
If you need to overwrite behaviour if SpatialOrder is part of another composable, you just need to type parent
"""
function convertfor(Partial, ::Type{SpatialOrder}, data, value)
    @needs data: image = ImageData
    N = ndims(image)
    if isa(value, Tuple) &&
        if eltype(value) == Int || length(value) != N
            throw(UsageError(SpatialOrder, value))
        end
        return value
    end
    str = if isa(value, Symbol)
        string(value)
    elseif isa(value, String)
        value
    else
        throw(UsageError(SpatialOrder, value))
    end
    if length(str) != N
        throw(UsageError(SpatialOrder, value))
    end
    ntuple(length(str)) do i
        idx = findfirst(('x', 'y', 'z', 't'), str[i])
        if idx == 0
            throw(UsageError(SpatialOrder, value))
        end
        idx
    end
end

"""
Determines what the order of the dimensions is.
Can be a symbol or string like: xyz, yx, etc,
or a tuple with the indices of the dimensions, exactly like how you would pass it
to permutedims.
"""
SpatialOrder

@field ImageData
@field Ranges

"""
Ranges indicate, on what an otherwise dimensionless visualization should be mapped.
E.g. use Ranges to indicate that an image should be mapped to a certain range.
"""
Ranges

function default(Partial, ::Type{Ranges}, data)
    @needs data: image = ImageData
    s = get(data, SpatialOrder) # if SpatialOrder in x, gets that, if not gets default(x, SpatialOrder)
    (0:size(image, s[1]), 0:size(image, s[2]))
end

@composed type Image
    ImageData
    Ranges
    SpatialOrder::NTuple{2, Int}
end
