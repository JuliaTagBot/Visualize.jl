using GeometryTypes
using ModernGL
import GLAbstraction, GLWindow, ColorVectorSpace
import Transpiler: gli
using StaticArrays
include("rasterizer.jl")
import Transpiler: mix, smoothstep

function aastep{T}(threshold1::T, value)
    return smoothstep(threshold1 - T(0.001), threshold1 + T(0.001), value)
end

type Uniforms{F}
    strokecolor::Vec4f0
    glowcolor::Vec4f0
    distance_func::F
    projection::Mat4f0
end

immutable Vertex{N, T}
    position::Vec{N, T}
    uvrect::Vec4f0
    color::Vec4f0
    scale::Vec2f0
end

immutable Vertex2Geom
    uvrect::Vec4f0
    color::Vec4f0
    rect::Vec4f0
end

getuvrect(x) = x.uvrect
getcolor(x) = x.color
getstrokecolor(x) = x.strokecolor
getglowcolor(x) = x.glowcolor
getscale(x) = x.scale
getposition(x) = x.position

function vertex_main(vertex, uniforms)
    p = getposition(vertex)
    scale = getscale(vertex)

    geom = Vertex2Geom(
        getuvrect(vertex),
        getcolor(vertex),
        Vec4f0(p[1], p[2], scale[1], scale[2])
    )
    geom
end

"""
Emits a vertex with
"""
function emit_vertex(emit!, vertex, uv, offsetted_uv, arg, pos, uniforms)
    datapoint = uniforms.projection * Vec4f0(pos[1], pos[2], 0, 1)
    final_position = uniforms.projection * Vec4f0(vertex[1], vertex[2], 0, 0)
    frag_out = (uv, offsetted_uv, arg.color)
    emit!(datapoint .+ final_position, frag_out)
    return
end

function geometry_main(emit!, geom_in, uniforms)
    # get arguments from first face
    # (there is only one in there anywas, since primitive type is point)
    # (position, vertex_out)
    arg = geom_in[1]
    # emit quad as triangle strip
    # v3. ____ . v4
    #    |\   |
    #    | \  |
    #    |  \ |
    #    |___\|
    # v1*      * v2
    pos_scale = arg.rect
    pos = pos_scale[Vec(1, 2)]
    scale = pos_scale[Vec(3, 4)]
    quad = Vec4f0(0f0, 0f0, scale[1], scale[2])
    uv = arg.uvrect
    uvnormed = Vec4f0(-0.5f0, -0.5f0, 0.5f0, 0.5f0)
    emit_vertex(emit!, quad[Vec(1, 2)], uvnormed[Vec(1, 4)], uv[Vec(1, 4)], arg, pos, uniforms)
    emit_vertex(emit!, quad[Vec(1, 4)], uvnormed[Vec(1, 2)], uv[Vec(1, 2)], arg, pos, uniforms)
    emit_vertex(emit!, quad[Vec(3, 2)], uvnormed[Vec(3, 4)], uv[Vec(3, 4)], arg, pos, uniforms)
    emit_vertex(emit!, quad[Vec(3, 4)], uvnormed[Vec(3, 2)], uv[Vec(3, 2)], arg, pos, uniforms)
    return
end
function fragment_main(fragment_in, uniforms)
    uv = fragment_in[1]; uv_offset = fragment_in[2]; color = fragment_in[3];
    signed_distance = uniforms.distance_func(uv)
    inside = aastep(0f0, signed_distance)
    bg = Vec4f0(0f0, 0f0, 0f0, 0f0)
    (mix(bg, color, inside),)
end
circle{T}(uv::Vec{2, T}) = T(0.5) - norm(uv)

proj = orthographicprojection(SimpleRectangle(0, 0, 500, 500), -10_000f0, 10_000f0)

uniforms = Uniforms(
    Vec4f0(1, 0, 0, 1),
    Vec4f0(1, 0, 1, 1),
    circle,
    proj
)
N = 20
vertices = [(Vertex(
    Vec2f0(sin(2pi * (i / N)) * 200 , cos(2pi * (i / N)) * 200) + 200f0,
    Vec4f0(0, 0, 0, 0), Vec4f0(1, i/N, 0, 1), Vec2f0(40, 40)
),) for i = 1:N]

framebuffer = fill(RGBA{Float32}(1, 1, 1, 0), 500, 500)
depthbuffer = ones(Float32, size(framebuffer))
rasterize!(
    depthbuffer, (framebuffer,),
    vertices, uniforms,
    vertex_main, fragment_main, geometry_main, 4
)

save("test.png", framebuffer)
