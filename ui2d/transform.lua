local Transform = {}

function Transform.identity()
    return {a = 1, b = 0, c = 0, d = 1, tx = 0, ty = 0}
end

function Transform.multiply(left, right)
    return {
        a = left.a * right.a + left.c * right.b,
        b = left.b * right.a + left.d * right.b,
        c = left.a * right.c + left.c * right.d,
        d = left.b * right.c + left.d * right.d,
        tx = left.a * right.tx + left.c * right.ty + left.tx,
        ty = left.b * right.tx + left.d * right.ty + left.ty,
    }
end

function Transform.translation(x, y)
    return {a = 1, b = 0, c = 0, d = 1, tx = x or 0, ty = y or 0}
end

function Transform.scale(x, y)
    return {a = x, b = 0, c = 0, d = y, tx = 0, ty = 0}
end

function Transform.rotation(radians)
    local cosine, sine = math.cos(radians), math.sin(radians)
    return {a = cosine, b = sine, c = -sine, d = cosine, tx = 0, ty = 0}
end

function Transform.compose(spec)
    local result = Transform.translation(spec.translate_x, spec.translate_y)
    result = Transform.multiply(result, Transform.translation(spec.origin_x, spec.origin_y))
    result = Transform.multiply(result, Transform.rotation(spec.rotation))
    result = Transform.multiply(result, Transform.scale(spec.scale_x, spec.scale_y))
    return Transform.multiply(result, Transform.translation(-spec.origin_x, -spec.origin_y))
end

function Transform.apply(matrix, x, y)
    return matrix.a * x + matrix.c * y + matrix.tx,
        matrix.b * x + matrix.d * y + matrix.ty
end

function Transform.inverse(matrix)
    local determinant = matrix.a * matrix.d - matrix.b * matrix.c
    if math.abs(determinant) < 0.0000001 then return nil end
    local a, b = matrix.d / determinant, -matrix.b / determinant
    local c, d = -matrix.c / determinant, matrix.a / determinant
    return {
        a = a,
        b = b,
        c = c,
        d = d,
        tx = -(a * matrix.tx + c * matrix.ty),
        ty = -(b * matrix.tx + d * matrix.ty),
    }
end

function Transform.unapply(matrix, x, y)
    local inverse = Transform.inverse(matrix)
    if not inverse then return nil end
    return Transform.apply(inverse, x, y)
end

function Transform.contains(matrix, rect, x, y)
    local local_x, local_y = Transform.unapply(matrix, x, y)
    return local_x ~= nil
        and local_x >= rect.x and local_x <= rect.x + rect.w
        and local_y >= rect.y and local_y <= rect.y + rect.h
end

function Transform.bounds(matrix, rect)
    local x1, y1 = Transform.apply(matrix, rect.x, rect.y)
    local x2, y2 = Transform.apply(matrix, rect.x + rect.w, rect.y)
    local x3, y3 = Transform.apply(matrix, rect.x, rect.y + rect.h)
    local x4, y4 = Transform.apply(matrix, rect.x + rect.w, rect.y + rect.h)
    local left, right = math.min(x1, x2, x3, x4), math.max(x1, x2, x3, x4)
    local top, bottom = math.min(y1, y2, y3, y4), math.max(y1, y2, y3, y4)
    return {x = left, y = top, w = right - left, h = bottom - top}
end

return Transform
