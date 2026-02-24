import type { ResultType } from 'poly-extrude/dist/type';
import type { MeshLayer } from '../../types/index.js';

/**
 * Konverter poly-extrude output til MeshLayer.
 * poly-extrude bruger Z-up (x, y, z) mens Godot bruger Y-up,
 * så akserne omarrangeres: (x, z, y) → (x, y, z).
 */
export function polyExtrudeToMeshLayer(result: ResultType): MeshLayer {
    const { position, normal, indices } = result;
    const vertCount = position.length / 3;

    const vertices: number[] = new Array(vertCount * 3);
    const normals: number[] = new Array(vertCount * 3);

    for (let i = 0; i < vertCount; i++) {
        const base = i * 3;
        vertices[base] = position[base];         // x forbliver x
        vertices[base + 1] = position[base + 2]; // z til y (højde)
        vertices[base + 2] = position[base + 1]; // y til z (dybde)

        normals[base] = normal[base];
        normals[base + 1] = normal[base + 2];
        normals[base + 2] = normal[base + 1];
    }

    return {
        vertices,
        indices: Array.from(indices),
        normals
    };
}

/**
 * Kombiner flere MeshLayers til en ved at samle vertices/indices/normals.
 */
export function mergeMeshLayers(layers: MeshLayer[]): MeshLayer {
    const allVertices: number[] = [];
    const allIndices: number[] = [];
    const allNormals: number[] = [];
    let vertexOffset = 0;

    for (const layer of layers) {
        allVertices.push(...layer.vertices);
        allNormals.push(...layer.normals);
        for (const idx of layer.indices) {
            allIndices.push(idx + vertexOffset);
        }
        vertexOffset += layer.vertices.length / 3;
    }

    return { vertices: allVertices, indices: allIndices, normals: allNormals };
}

/**
 * Sæt alle vertices til en fast Y-højde og normaler til (0, 1, 0).
 * Muterer layeren in-place.
 */
export function flattenLayer(layer: MeshLayer, y: number): void {
    const vertCount = layer.vertices.length / 3;
    for (let i = 0; i < vertCount; i++) {
        const base = i * 3;
        layer.vertices[base + 1] = y;
        layer.normals[base] = 0;
        layer.normals[base + 1] = 1;
        layer.normals[base + 2] = 0;
    }
}
