# MCPackPacker

Scripts to compress and pack Minecraft datapacks and resource packs.

## Example Usage

```yaml
include:
  - project: 'BrainStone/MCPackPacker'
    ref: compiled/v1
    file: 'pack_packer.yml'

create_resource_pack:
	stage: build
	extends:
		- .pack_pack
	variables:
		folder: resources
		output: Dummy.resources.zip

```
