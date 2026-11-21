import simd

/// Maps an ArcFace-aligned face onto the 112×112 template with scale, rotation, and translation.
struct FaceSimilarityTransform: Equatable, Sendable {
    var a: Float
    var b: Float
    var tx: Float
    var ty: Float

    /// Least-squares similarity. `u = a x - b y + tx`, `v = b x + a y + ty`.
    static func estimate(from source: [SIMD2<Float>], to destination: [SIMD2<Float>]) -> FaceSimilarityTransform? {
        guard source.count == destination.count, source.count >= 2 else { return nil }
        var normal = [[Float]](repeating: [Float](repeating: 0, count: 4), count: 4)
        var rhs = [Float](repeating: 0, count: 4)
        for index in source.indices {
            let x = source[index].x
            let y = source[index].y
            accumulate([x, -y, 1, 0], destination[index].x, into: &normal, rhs: &rhs)
            accumulate([y, x, 0, 1], destination[index].y, into: &normal, rhs: &rhs)
        }
        guard let solution = solve(normal, rhs) else { return nil }
        let scaleSquared = solution[0] * solution[0] + solution[1] * solution[1]
        guard scaleSquared > 1e-8 else { return nil }
        return FaceSimilarityTransform(a: solution[0], b: solution[1], tx: solution[2], ty: solution[3])
    }

    /// Average distance, in template pixels, after applying the fit.
    func meanError(from source: [SIMD2<Float>], to destination: [SIMD2<Float>]) -> Float {
        guard source.count == destination.count, !source.isEmpty else { return .greatestFiniteMagnitude }
        var total: Float = 0
        for index in source.indices {
            let x = source[index].x
            let y = source[index].y
            let predicted = SIMD2(a * x - b * y + tx, b * x + a * y + ty)
            total += hypot(predicted.x - destination[index].x, predicted.y - destination[index].y)
        }
        return total / Float(source.count)
    }

    /// Template pixel → source pixel.
    func sourcePoint(forTemplate point: SIMD2<Float>) -> SIMD2<Float> {
        let scaleSquared = a * a + b * b
        let dx = point.x - tx
        let dy = point.y - ty
        return SIMD2(
            (a * dx + b * dy) / scaleSquared,
            (-b * dx + a * dy) / scaleSquared
        )
    }

    private static func accumulate(_ row: [Float], _ target: Float, into normal: inout [[Float]], rhs: inout [Float]) {
        for i in 0 ..< 4 {
            rhs[i] += row[i] * target
            for j in 0 ..< 4 {
                normal[i][j] += row[i] * row[j]
            }
        }
    }

    private static func solve(_ matrix: [[Float]], _ values: [Float]) -> [Float]? {
        var m = matrix
        var rhs = values
        let n = 4
        for column in 0 ..< n {
            var pivot = column
            var best = abs(m[column][column])
            for row in (column + 1) ..< n where abs(m[row][column]) > best {
                best = abs(m[row][column])
                pivot = row
            }
            guard best > 1e-6 else { return nil }
            if pivot != column {
                m.swapAt(pivot, column)
                rhs.swapAt(pivot, column)
            }
            let divisor = m[column][column]
            for index in column ..< n {
                m[column][index] /= divisor
            }
            rhs[column] /= divisor
            for row in 0 ..< n where row != column {
                let factor = m[row][column]
                guard factor != 0 else { continue }
                for index in column ..< n {
                    m[row][index] -= factor * m[column][index]
                }
                rhs[row] -= factor * rhs[column]
            }
        }
        return rhs
    }
}
