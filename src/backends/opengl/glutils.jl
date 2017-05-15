type VertexArray{Vertex, Face, IT}
    id::GLuint
    length::Int
    buffer::Vector
    indices::IT
    context::GLAbstraction.GLContext
    function (::Type{VertexArray{Vertex, Face}}){Vertex, Face, IT}(id, bufferlength, buffers, indices::IT)
        new{Vertex, Face, IT}(id, bufferlength, buffers, indices, GLAbstraction.current_context())
    end
end

gl_face_enum{V, IT}(::VertexArray{V, GLTriangle, IT}) = GL_TRIANGLES
gl_face_enum{V, IT, T <: Integer}(::VertexArray{V, T, IT}) = GL_POINTS
gl_face_enum{V, IT}(::VertexArray{V, Face{1, OffsetInteger{1, GLint}}, IT}) = GL_POINTS

function draw_vbo{V, T, IT <: GLBuffer}(vbo::VertexArray{V, T, IT})
    glDrawElements(
        gl_face_enum(vbo),
        length(vbo.indices) * GLAbstraction.cardinality(vbo.indices),
        GLAbstraction.julia2glenum(eltype(IT)), C_NULL
    )
end
function draw_vbo{V, T}(vbo::VertexArray{V, T, DataType})
    glDrawArrays(gl_face_enum(vbo), 0, length(vbo))
end


Base.eltype{T, IT, N}(::VertexArray{T, IT, N}) = T
Base.length(x::VertexArray) = x.length

function uvmesh(prim::GeometryPrimitive, resolution = (2, 2))
    uv = decompose(UV{Float32}, prim, resolution)
    positions = decompose(Point2f0, prim, resolution)
    faces = decompose(GLTriangle, prim, resolution)
    vertices = map(identity, zip(positions, uv))
    view(vertices, faces)
end
function normalmesh(prim)
    V = GeometryTypes.vertices(prim)
    N = GeometryTypes.normals(prim)
    F = decompose(GLTriangle, prim)
    verts = map((a, b)-> (a, b), V, N)
    Base.view(verts, F)
end

function VertexArray(buffer::AbstractArray, attrib_location = 0; face_type = GLTriangle)
    VertexArray(GLBuffer(buffer), face_type, attrib_location)
end
function VertexArray{T, AT <: AbstractArray, IT <: AbstractArray}(
        view::SubArray{T, 1, AT, Tuple{IT}, false}, attrib_location = 0
    )
    indexes = view.indexes[1]
    buffer = view.parent
    VertexArray(GLBuffer(buffer), GLAbstraction.indexbuffer(indexes), attrib_location)
end

is_struct{T}(::Type{T}) = !(sizeof(T) != 0 && nfields(T) == 0)
is_glsl_primitive{T <: StaticVector}(::Type{T}) = true
is_glsl_primitive{T <: Union{Float32, Int32}}(::Type{T}) = true
is_glsl_primitive(T) = false

_typeof{T}(::Type{T}) = Type{T}
_typeof{T}(::T) = T
function VertexArray{T}(buffer::GLBuffer{T}, indices, attrib_location)
    id = glGenVertexArrays()
    glBindVertexArray(id)
    face_type = if isa(indices, GLBuffer)
        GLAbstraction.bind(indices)
        eltype(indices)
    elseif isa(indices, DataType) && indices <: Face
        indices
    elseif isa(indices, Integer)
        Face{1, OffsetInteger{1, GLint}}
    else
        error("indices must be Int, GLBuffer or Face type")
    end
    GLAbstraction.bind(buffer)
    if !is_glsl_primitive(T)
        for i = 1:nfields(T)
            FT = fieldtype(T, i); ET = eltype(FT)
            glVertexAttribPointer(
                attrib_location,
                GLAbstraction.cardinality(FT), GLAbstraction.julia2glenum(ET),
                GL_FALSE, sizeof(T), Ptr{Void}(fieldoffset(T, i))
            )
            glEnableVertexAttribArray(attrib_location)
            attrib_location += 1
        end
    else
        FT = T; ET = eltype(FT)
        glVertexAttribPointer(
            attrib_location,
            GLAbstraction.cardinality(FT), GLAbstraction.julia2glenum(ET),
            GL_FALSE, 0, C_NULL
        )
        glEnableVertexAttribArray(attrib_location)
    end
    glBindVertexArray(0)
    obj = VertexArray{T, face_type}(id, length(buffer), [buffer], indices)
    #finalizer(obj, GLAbstraction.free)
    obj
end


function compile_program(shaders...)
    program = GLAbstraction.createprogram()
    glUseProgram(program)
    #attach new ones
    foreach(shaders) do shader
        glAttachShader(program, shader.id)
    end
    #link program
    glLinkProgram(program)
    if !GLAbstraction.islinked(program)
        error(
            "program $program not linked. Error in: \n",
            join(map(x-> string(x.name), shaders), " or "), "\n", GLAbstraction.getinfolog(program)
        )
    end
    program
end

const max_batch_size = 1024

"""
Statically sized uniform buffer.
Supports push!, but with fixed memory, so it will error after reaching
it's preallocated length.
"""
type UniformBuffer{T, N}
    buffer::GLBuffer{T}
    offsets::NTuple{N, Int}
    elementsize::Int
    length::Int
end
const GLSLScalarTypes = Union{Float32, Int32, UInt32}
Base.eltype{T, N}(::UniformBuffer{T, N}) = T


function glsl_sizeof(T)
    T <: Bool && return sizeof(Int32)
    T <: GLSLScalarTypes && return sizeof(T)
    # TODO Propper translation and sizes!
    T <: Function && return sizeof(Vec4f0) # sizeof(EmptyStruct) padded to Vec4f0
    ET = eltype(T)
    if T <: Mat
        return sizeof(ET) * 4 * size(T, 2)
    end
    # must be vector like #TODO assert without restricting things too much
    N = length(T)
    @assert N <= 4
    N <= 2 && return 2 * sizeof(ET)
    return 4 * sizeof(ET)
end

function std140_offsets{T}(::Type{T})
    elementsize = 0
    offsets = if T <: GLSLScalarTypes
        elementsize = sizeof(T)
        (0,)
    else
        offset = 0
        offsets = ntuple(nfields(T)) do i
            ft = fieldtype(T, i)
            sz = glsl_sizeof(ft)
            of = offset
            offset += sz
            of
        end
        elementsize = offset
        offsets
    end
    offsets, elementsize
end

"""
    Pre allocates an empty buffer with `max_batch_size` size
    which can be used to store multiple uniform blocks of type T
"""
function UniformBuffer{T}(::Type{T}, max_batch_size = 1024, mode = GL_STATIC_DRAW)
    offsets, elementsize = std140_offsets(T)
    buffer = GLBuffer{T}(
        max_batch_size,
        elementsize * max_batch_size,
        GL_UNIFORM_BUFFER, mode
    )
    UniformBuffer(buffer, offsets, elementsize, 0)
end

"""
    Creates an Uniform buffer with the contents of `data`
"""
function UniformBuffer{T}(data::T, mode = GL_STATIC_DRAW)
    buffer = UniformBuffer(T, 1, mode)
    push!(buffer, data)
    buffer
end

function assert_blocksize(buffer::UniformBuffer, program, blockname::String)
    block_index = glGetUniformBlockIndex(program, blockname)
    blocksize_ref = Ref{GLint}(0)
    glGetActiveUniformBlockiv(
        program, block_index,
        GL_UNIFORM_BLOCK_DATA_SIZE, blocksize_ref
    )
    blocksize = blocksize_ref[]
    @assert buffer.elementsize * length(buffer.buffer) == blocksize
end

_getfield(x::GLSLScalarTypes, i) = x
_getfield(x, i) = getfield(x, i)
function iterate_fields{T, N}(buffer::UniformBuffer{T, N}, x, index)
    offset = buffer.elementsize * (index - 1)
    x_ref = isimmutable(x) ? Ref(x) : x
    base_ptr = pointer_from_objref(x_ref)
    ntuple(Val{N}) do i
        offset + buffer.offsets[i], base_ptr + fieldoffset(T, i), sizeof(fieldtype(T, i))
    end
end
function Base.setindex!{T, N}(buffer::UniformBuffer{T, N}, element::T, idx::Integer)
    if idx > length(buffer.buffer)
        throw(BoundsError(buffer, idx))
    end
    GLAbstraction.bind(buffer.buffer)
    for (offset, ptr, size) in iterate_fields(buffer, element, idx)
        glBufferSubData(GL_UNIFORM_BUFFER, offset, size, ptr)
    end
    GLAbstraction.bind(buffer.buffer, 0)
    element
end
function Base.push!{T, N}(buffer::UniformBuffer{T, N}, element::T)
    buffer.length += 1
    buffer[buffer.length] = element
    buffer
end

immutable Command
    vertexCount::GLuint
    instanceCount::GLuint
    firstIndex::GLuint
    baseVertex::GLuint
    baseInstance::GLuint
end

export Command