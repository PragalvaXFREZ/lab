# schematics

[Image Factory](https://www.talos.dev/latest/learn-more/image-factory/) schematics: the declarative description of what goes into a Talos boot image, including system extensions and kernel arguments. The schematic is the source; the resulting image ID and installer reference are derived from it.

The active NetBird schematics target Talos v1.12.11. NetBird is absent from the v1.11.5 extension catalog, so do not combine these schematic IDs with the older Talos release. Image Factory resolves every extension to the build matching the Talos version in the installer reference.
