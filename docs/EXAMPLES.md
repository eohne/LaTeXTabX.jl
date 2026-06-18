# Examples

The worked examples (code + LaTeX output for every builder, with multiple
customization variants) now live in the **[Examples section of the main
README](../README.md#examples)**.

They are all produced by the runnable script in this folder:

```sh
julia --project=. docs/examples.jl
```

Backend-specific demos (FixedEffectModels, StagDiDModels, Regress) are in
[`../test/`](../test/).
