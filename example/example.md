<!--
@license
Copyright (c) ggsuite

Use of this source code is governed by terms that can be
found in the LICENSE file in the root of this package.
-->

# Example

Create a Dart package in the ocean of a gg workspace:

```bash
gg do create repo -n gg_foo -l dart -g ggsuite -d "Does foo" --dna dna_ggsuite
```

Create a TypeScript package outside of a workspace:

```bash
dart pub global activate gg_create_repo
gg_create_repo -n my-lib -l ts -g tssuite -d "A library" --dna @tssuite/dna-tssuite
```
