# Godot-Dev-Utils-Addons
A collection of lightweight, production-oriented tools built with GDScript to streamline environment creation and asset workflow in Godot.

---

## Features

### Scene Painter
Quickly place scenes directly onto meshes with a click-based workflow.

- Paint scenes directly in the 3D viewport  
- Supports placement rules (alignment, rotation, scaling, etc.)  
- Ideal for scattering props, rocks, foliage, and set dressing  


### Chunked MultiMesh Painter (GPU Instancing)
High-performance object painting using `MultiMeshInstance3D`.

- GPU instancing for massive object counts  
- Chunked system for efficient culling and updates  
- Designed for large-scale environments (foliage, grass, debris)  
- Minimizes CPU overhead  


### Vertex Color Painter
A simple and efficient vertex color painting tool.

- Paint vertex colors directly in the editor  
- Useful for blending materials, masks, and stylized effects  
- Lightweight and easy to integrate into existing workflows  

---

## Goals

- Improve level design speed  
- Reduce manual placement work  
- Enable scalable environment rendering  
- Provide simple but powerful tools for production  

---

## Built With

- Godot Engine (4.x)  
- GDScript

---

## Notes

This addon is actively used in the development of a game, so features are added and refined based on real production needs.
Most of the feature were implemented with the help of **IA**.

---

## License

[MIT](LICENSE)
