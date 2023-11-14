//
// Copyright 2023 The Khronos Group, Inc.
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//    http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.
//

import Foundation
import SceneKit
import simd

extension simd_float4 {
    var xyz: simd_float3 {
        return simd_float3(x, y, z)
    }
}

extension simd_float4x4 {
    var upperLeft3x3: simd_float3x3 {
        return simd_float3x3(columns.0.xyz, columns.1.xyz, columns.2.xyz)
    }

    init(_ upperLeft3x3: simd_float3x3) {
        self.init(simd_float4(upperLeft3x3.columns.0, 0.0),
                  simd_float4(upperLeft3x3.columns.1, 0.0),
                  simd_float4(upperLeft3x3.columns.2, 0.0),
                  simd_float4(   0.0,    0.0,    0.0, 1.0))
    }

    init(translation v: simd_float3) {
        self.init(simd_float4(1.0, 0.0, 0.0, 0.0),
                  simd_float4(0.0, 1.0, 0.0, 0.0),
                  simd_float4(0.0, 0.0, 1.0, 0.0),
                  simd_float4(      v,       1.0))
    }

    init(scale v: simd_float3) {
        self.init(simd_float4(v.x, 0.0, 0.0, 0.0),
                  simd_float4(0.0, v.y, 0.0, 0.0),
                  simd_float4(0.0, 0.0, v.z, 0.0),
                  simd_float4(0.0, 0.0, 0.0, 1.0))
    }

    init(uniformScale s: Float) {
        self.init(simd_float4(  s, 0.0, 0.0, 0.0),
                  simd_float4(0.0,   s, 0.0, 0.0),
                  simd_float4(0.0, 0.0,   s, 0.0),
                  simd_float4(0.0, 0.0, 0.0, 1.0))
    }

    init(rotationAbout axis: simd_float3, by angleRadians: Float) {
        let q = simd_quatf(angle: angleRadians, axis: axis)
        self.init(simd_matrix3x3(q))
    }

    // Transform this node's local AABB into a world-space AABB and return the result.
    // Adapted from "Transforming Axis-Aligned Bounding Boxes" in Graphics Gems I (Arvo, 1990)
    func transformAABB(_ points: (simd_float3, simd_float3)) -> (simd_float3, simd_float3) {
        let (localMin, localMax) = (points.0, points.1)
        let Amin = simd_float3(localMin)
        let Amax = simd_float3(localMax)
        let T = self.columns.3.xyz // Translational component of transform matrix
        let M = self.upperLeft3x3 // Scale-rotation component of transform matrix
        var Bmin = T, Bmax = T // Bounds are initially a zero-volume box at T
        for i in 0...2 {
            for j in 0...2 {
                let a = M[j, i] * Amin[j] // column-major indexing
                let b = M[j, i] * Amax[j]
                Bmin[i] += min(a, b)
                Bmax[i] += max(a, b)
            }
        }
        return (Bmin, Bmax)
    }
}

//extension SCNNode {
//    var worldBoundingBox: (SCNVector3, SCNVector3) {
//        let (localMin, localMax) = self.boundingBox
//        let localAABB = (simd_float3(localMin), simd_float3(localMax))
//        let (worldMin, worldMax) = self.simdWorldTransform.transformAABB(localAABB)
//        return (SCNVector3(worldMin), SCNVector3(worldMax))
//    }
//}
