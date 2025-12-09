# SimCity 3000 Sprite Extractor
Extracts sprites and images from indexed file formats (`*.dat` or `*.ixf` extensions for sprites and images) of SimCity 3000 first edition and later Unlimited/World re-release. Able to extract sprites that compressed using MiniLZO (for SimCity 3000) or RefPack/Qfs (for SimCity 3000 Unlimited). Tested works on extracting `*.dat` and `*.ixf` sprites archive (`/Res/Sprites`), GUI elements (`/Res/UI/Shared`), BAT render (`/BARender`), and many downloadable landmarks. This is subset of my bigger GUI application projects which expected to finish on 2026.

Note this project still ongoing, many aspects were subject of changes.

## Usage
```
Usage: sc3k_sprextract [-h,-bn,-b32,-o=<output dir>] <sprite archive.dat>

-h   : Show this help.
-bn  : Extract sprite to bitmap as their native bit format.
-b32 : Extract sprite to bitmap and convert into BGRA32 format.
-o   : Specify output directory of extracted sprites.
       Default as <archive name>_extracted on current directory.
```

You can download prebuilt binaries from [release page](https://github.com/thiekus/sc3k-sprite-extract/releases/) or build yourself using [Lazarus and FPC](https://www.lazarus-ide.org/) by open `sc3k_sprextract.lpr` and build.

## License
This project is licensed under the terms of the MIT License, with exception is `minilzo.pas` which port of [minilzo](https://www.oberhumer.com/opensource/lzo/) to Pascal, licensed under GPL v2 or later.
