using FieldTraits, GeometryTypes, Visualize, FileIO
import FieldTraits: default
using GLAbstraction: to_worldspace
import Quaternions
const Q = Quaternions

@enum ProjectionEnum Perspective Orthographic

@field RotationSpeed = 1f0
@field TranslationSpeed = 1f0
@field EyePosition = Vec3f0(3)
@field LookAt = Vec3f0(0)
@field UpVector = Vec3f0(0, 0, 1)
@field Fov = 45f0
@field Near = 0.01f0
@field Far = 100f0
@field ProjectionType = Perspective

@composed type PerspectiveCamera <: ReactiveComposable
    <: Camera
    ProjectionType
    Translation
    Rotation
    RotationSpeed
    TranslationSpeed
    EyePosition
    LookAt
    UpVector
    Fov
    Near
    Far
end

FieldTraits.default(::Type{PerspectiveCamera}, ::Type{Rotation}) = Vec3f0(0, 0, 0)

function Visualize.add!(cam, ::Type{Translation}, canvas, key, button)
    local last_mousepos::Vec2f0 = Vec2f0(0, 0)
    on(canvas, Mouse.Drag) do drag
        if ispressed(canvas, key) && ispressed(canvas, button)
            if drag == Mouse.down
                #just started pressing, nothing to do yet
                last_mousepos = Vec2f0(canvas[Mouse.Position])
            elseif drag == Mouse.pressed
                 # we need the difference, although I'm wondering if absolute wouldn't be better.
                 # TODO FIND OUT! Definitely would have more precision problems
                mousepos = Vec2f0(canvas[Mouse.Position])
                diff = (last_mousepos - mousepos) * cam[TranslationSpeed]
                last_mousepos = mousepos
                cam[Translation] = Vec3f0(0f0, diff[1], - diff[2])
            end
        end
        return
    end
    on(canvas, Mouse.Scroll) do scroll
        if ispressed(canvas, button)
            cam[Translation] = Vec3f0(scroll[2], 0f0, 0f0)
        end
        return
    end
end
function Visualize.add!(cam, ::Type{Rotation}, canvas, key, button)
    local last_mousepos::Vec2f0 = Vec2f0(0, 0)
    on(canvas, Mouse.Drag) do drag
        if ispressed(canvas, key) && ispressed(canvas, button)
            if drag == Mouse.down
                last_mousepos = Vec2f0(canvas[Mouse.Position])
            elseif drag == Mouse.pressed
                mousepos = Vec2f0(canvas[Mouse.Position])
                mp = (last_mousepos - mousepos) * cam[RotationSpeed]
                last_mousepos = mousepos
                cam[Rotation] = Vec3f0(mp[1], -mp[2], 0f0)
            end
        end
        return
    end
end
function Visualize.add!(cam, ::Type{EyePosition}, ::Type{LookAt})
    on(cam, Translation) do translation
        translation == Vec3f0(0) && return

        lookat = cam[LookAt]; eyepos = cam[EyePosition]; up = cam[UpVector]
        projview = cam[ProjectionView]; area = cam[Area]; prjt = cam[ProjectionType]

        dir = eyepos - lookat
        dir_len = norm(dir)
        cam_res = Vec2f0(widths(area))
        zoom, x, y = translation
        zoom *= 0.1f0 * dir_len

        if prjt != Perspective
            x, y = to_worldspace(Vec2f0(x, y), projview, cam_res)
        else
            x, y = (Vec2f0(x, y) ./ cam_res) .* dir_len
        end
        dir_norm = normalize(dir)
        right = normalize(cross(dir_norm, up))
        zoom_trans = dir_norm * zoom

        side_trans = right * (-x) + normalize(up) * y
        newpos = eyepos + side_trans + zoom_trans
        cam[EyePosition] = newpos
        cam[LookAt] = lookat + side_trans
        return
    end
    on(cam, Rotation) do theta_v
        theta_v == Vec3f0(0) && return #nothing to do!
        eyepos_v = cam[EyePosition]; lookat_v = cam[LookAt]; up_v = cam[UpVector]

        dir = normalize(eyepos_v - lookat_v)
        right_v = normalize(cross(up_v, dir))
        up_v  = normalize(cross(dir, right_v))
        rotation = rotate_cam(theta_v, right_v, Vec3f0(0, 0, 1), dir)
        r_eyepos = lookat_v + rotation * (eyepos_v - lookat_v)
        r_up = normalize(rotation * up_v)
        cam[EyePosition] = r_eyepos
        cam[UpVector] = r_up
        return
    end
end
function projection_switch{T <: Real}(
        wh::SimpleRectangle,
        fov::T, near::T, far::T,
        projection::ProjectionEnum, zoom::T
    )
    aspect = T(wh.w / wh.h)
    h = T(tan(fov / 360.0 * pi) * near)
    w = T(h * aspect)
    projection == Perspective && return frustum(-w, w, -h, h, near, far)
    h, w = h * zoom, w * zoom
    orthographicprojection(-w, w, -h, h, near, far)
end

function rotate_cam{T}(
        theta::Vec{3, T},
        cam_right::Vec{3, T}, cam_up::Vec{3, T}, cam_dir::Vec{3, T}
    )
    rotation = one(Q.Quaternion{T})
    # first the rotation around up axis, since the other rotation should be relative to that rotation
    if theta[1] != 0
        rotation *= Q.qrotation(cam_up, theta[1])
    end
    # then right rotation
    if theta[2] != 0
        rotation *= Q.qrotation(cam_right, theta[2])
    end
    # last rotation around camera axis
    if theta[3] != 0
        rotation *= Q.qrotation(cam_dir, theta[3])
    end
    rotation
end

function Visualize.add!(cam, ::Type{Projection}, ::Type{View})
    on(cam, Area, Fov, Near, ProjectionType, LookAt, EyePosition, UpVector) do area, fov, near, projectiontype, lookatv, eyeposition, upvector
        zoom = norm(lookatv - eyeposition)
        # TODO this means you can't set FarClip... SAD!
        far = max(zoom * 5f0, 30f0)
        proj = projection_switch(area, fov, near, far, projectiontype, zoom)
        view = lookat(eyeposition, lookatv, upvector)
        cam[Projection] = proj
        cam[View] = view
        cam[ProjectionView] = proj * view
    end
end




# function PerspectiveCamera(events)
#     cam = PerspectiveCamera()
#     add!(cam, Translation, events,
#         Mouse.right, Set([Keyboard.left_control])
#     )
#     add!(cam, Rotation, events,
#         Mouse.left, Set([Keyboard.left_control])
#     )
#     add!(cam, Projection, View)
#     add!(cam, EyePosition, LookAt)
#     cam
# end
