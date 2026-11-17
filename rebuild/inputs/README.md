# Rebuild the ISCAS’85 input files

Run these commands from the artifact root with Python 3, curl, Yosys and
yosys-abc installed. Choose new cache and output directories outside the
distributed copy. Only the fetch command contacts the source repositories.

```sh
python3 -B rebuild/inputs/inputs.py fetch --cache ../iscas-cache
python3 -B rebuild/inputs/inputs.py check --cache ../iscas-cache
python3 -B rebuild/inputs/inputs.py build --cache ../iscas-cache --output ../iscas-inputs
```

To use an existing local cache, place the eleven Verilog files in its `v/`
directory as `<host>.v` and the nine independent golden BENCH files in
`sld/` as `<host>.bench`. Start with the check command. Both check and build
verify each original's size, SHA-256 and Git blob ID. All required source
names and digests are in [pins.json](pins.json). Fetch obtains those files
from the [Verilog mirror at the reviewed commit](https://github.com/santoshsmalagi/Benchmarks/tree/8a0b4d2ca0e85e9d2425a96212605e5327a22c61/ISCAS85)
and the [sld benchmark distribution at the frozen commit](https://github.com/descyphy/Modified_SAT_Attack_on_Logic_Locking/tree/ea169e5643d62b88da13f840a211e27c10590190/benchmarks/original).

The output's `experiments/data/` subtree holds the six literal-generator
inputs, eleven normalized circuits, six configured two-input LUT circuits,
nine golden netlists, eleven correspondence records and 25 selected-output
port maps. Keep the hydrated working copy separate from the distribution.
The multiplier port convention is reconstructed from ordered declarations and
the documented high-product-bit ordering. The c17 multi-output conventions
and the historical diagnostic description are populated from the downloaded
RTL and the rebuilt normalized declarations. The source/output selectors in
file names identify the published measurements.

The build checks each generated BENCH body against its digest, including
gate order, whitespace and line endings. It records the whole fresh digest
and ABC comment in `inputs-receipt.json`. It then reattaches the public
archive's single identifying ABC comment and checks the restored file's
complete SHA-256. The historical comment identifies the previously
archived representation. It can contain a release path marker. New
generation times and tool identities belong to the local receipt. The
`verified` and tool-version fields reconstructed in archival JSON reproduce
the previous records. Build verifies their hashes; it performs format
conversion and input regeneration.

The June Yosys 0.66 with its bundled ABC and the August Yosys 0.68+post
with its bundled ABC reproduced these input bodies in local tests. Other
builds must pass the same digest checks. A source mismatch, mapping mismatch
or external tool failure stops the operation before it publishes the output
directory. A successful run leaves its input cache intact.
