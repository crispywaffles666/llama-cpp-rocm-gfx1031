# Third-party components

The built container redistributes software from these upstream projects:

- [llama.cpp](https://github.com/ggml-org/llama.cpp), MIT licensed.
- [TheRock / ROCm](https://github.com/ROCm/TheRock), composed of multiple AMD
  and third-party components under their respective licenses.
- [Ubuntu](https://ubuntu.com/), with packages under their respective licenses.

ROCm license documents from the source distribution are retained under
`/opt/rocm/share/doc` in the runtime image. Building or redistributing the image
does not change the terms of any bundled component. Review upstream licenses
before redistributing the image outside this project's intended use.
