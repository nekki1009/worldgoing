#version 450

// One 3D MultiMesh slot is twelve row-major transform floats and four custom floats.
layout(local_size_x = 64, local_size_y = 1, local_size_z = 1) in;
layout(set = 0, binding = 0, std430) buffer Instances { float data[]; } instances;
layout(set = 0, binding = 1, std430) readonly buffer Descriptors { vec4 custom[]; } descriptors;
layout(set = 0, binding = 2, std430) buffer IndirectCommand { uint data[]; } draw_command;

layout(push_constant, std430) uniform FormationCommand {
    vec4 center_spacing;
    vec4 right_axis;
    vec4 forward_axis;
    uvec4 shape; // columns, rows, valid slot span, allocated capacity
} command;

void main() {
    uint slot = gl_GlobalInvocationID.x;
    if (slot == 0u) {
        // Godot owns the remaining four indirect arguments for the one mesh surface.
        draw_command.data[1] = min(command.shape.z, command.shape.w);
    }
    if (slot >= command.shape.z || slot >= command.shape.w) {
        return;
    }

    uint column = slot % command.shape.x;
    uint row = slot / command.shape.x;
    float x = (float(column) - float(command.shape.x - 1u) * 0.5) * command.center_spacing.w;
    float z = (float(row) - float(command.shape.y - 1u) * 0.5) * command.center_spacing.w;
    vec3 p = command.center_spacing.xyz + command.right_axis.xyz * x + command.forward_axis.xyz * z;
    uint at = slot * 16u;
    instances.data[at + 0u] = command.right_axis.x;
    instances.data[at + 1u] = 0.0;
    instances.data[at + 2u] = command.forward_axis.x;
    instances.data[at + 3u] = p.x;
    instances.data[at + 4u] = command.right_axis.y;
    instances.data[at + 5u] = 1.0;
    instances.data[at + 6u] = command.forward_axis.y;
    instances.data[at + 7u] = p.y;
    instances.data[at + 8u] = command.right_axis.z;
    instances.data[at + 9u] = 0.0;
    instances.data[at + 10u] = command.forward_axis.z;
    instances.data[at + 11u] = p.z;
    vec4 custom = descriptors.custom[slot];
    instances.data[at + 12u] = custom.x;
    instances.data[at + 13u] = custom.y;
    instances.data[at + 14u] = custom.z;
    instances.data[at + 15u] = custom.w;
}
