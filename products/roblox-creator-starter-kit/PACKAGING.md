# Packaging (for the seller, not shipped to buyers)

```bash
cd survive2earn
./tools/setup_dev_tools.sh                         # one time, downloads free tools to .tools/
python3 products/roblox-creator-starter-kit/tools/build.py
```

Produces in `products/roblox-creator-starter-kit/dist/`:
- `RobloxCreatorStarterKit-v<VERSION>.rbxlx` – demo place (open in Studio)
- `RobloxCreatorStarterKit-v<VERSION>.zip` – the file you upload to the store; contains
  src, docs, examples, tests, demo place, LICENSE and `BUILD_CHECKS.txt`.

`build.py` refuses to package if any check fails. Bump `VERSION` and `CHANGELOG.md`
for every new upload. Do not upload until `docs/STUDIO_TEST_CHECKLIST.md` passes
(mission M001), or clearly label the listing as "not yet Studio-tested".
