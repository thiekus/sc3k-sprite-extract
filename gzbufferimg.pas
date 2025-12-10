unit gzbufferimg;

//
// SimCity 3000 GZBuffer Image and Sprite converter for Free Pascal
// Coded by Thiekus (https://thiekus.com/)
//
// Copyright (C) 2025 Thiekus
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in
// all copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
// SOFTWARE.
//
// Note that while this part of code is licensed under MIT license, resulting
// of built program as whole would be GPL v2 since it depends of MiniLZO GPL v2
// or later license. Unless GPL components were stripped out.
//

{$mode ObjFPC}{$H+}

interface

uses
  SysUtils, Classes, refpack, rzminilzo;

const
  GZBUFFER_TRANSPARENT_COLOR16 = $F81F; // Default transparent color in sprites
  GZBUFFER_TRANSPARENT_COLOR32 = $00FF00FF; // Same but ARGB32

type
  // cGZBufferColorType::eColorType
  TGZBufferColorType = (
    ctColorInvalid = 0,
    ctColorNative,
    ctColorPal4,
    ctColorPal8, // = 3, mostly used by disaster sprites for opacity alpha
    ctColorRGB16,
    ctColorRGB555, // = 5, most used by SC3K
    ctColorRGB655,
    ctColorRGB565, // = 7, most used by SC3U
    ctColorRGB556,
    ctColorRGBA5551,
    ctColorARGB1555,
    ctColorRGBA4444,
    ctColorARGB4444,
    ctColorRGB24,
    ctColorARGB32,
    ctColorBGRA32 // Not defined by SC3K, use for 16-bit to 32-bit
  );

  // For Image Buffer (Type ID $62B9DA24), where's SC3K use as uncompressed
  // bitmap file, while later SC3U uses their custom header as defined on
  // TGZBufferCompressedImageHeader below.
  TGZBufferImageType = (
    itUnknown = 0, // Not known
    itBitmap, // Ordinary BMP file which has 'BM' header
    itRefPack // RefPack compressed 16-bit color buffer processed by this unit
  );

  TGZBufferSpriteCompressionType = (
    sctUnknown = 0,
    sctMiniLZO, // Used in SC3K, known as gnulzo in part of RZFastCompression
    sctRefPack // Used in SC3U, RZFastCompression3
  );

  TGZBufferSpriteType = (
    stUnknown = 0, // Not known
    stSpriteBuffer, // Usual sprite buffer
    stSpriteMask // Sprite opacity mask
  );

  PGZBufferCompressedImageHeader = ^TGZBufferCompressedImageHeader;
  TGZBufferCompressedImageHeader = packed record
    BytesPerPixel: Uint32; // In SC3U always 2 = 16 bit colors
    CompressedSize: Uint32;
    Width: Uint32;
    Height: Uint32;
    ColorType: UInt32; // TGZBufferColorType
  end;

  PGZBufferCompressedSpriteHeader = ^TGZBufferCompressedSpriteHeader;
  TGZBufferCompressedSpriteHeader = packed record
    // Follows TGZBufferColorType
    ColorType: UInt8;
    // If not zero, in decompressed data there's another header
    // of TGZBufferRawSpriteHeader and strides information of each line
    HasDecompressedHeader: UInt8;
    // Always 0, padding?
    Unk1: UInt16;
    // Taken from libSimSpr.so at
    // cSC3DBSegmentSprite::ConvertSpriteBmpBufferFromSegmentData() and more
    // exact cSC3DBSegmentSprite::ConvertSpriteBmpBufferToSegmentData()
    // In SC3U most of time is 0x00080000 (DecompressAlpha8LZ2)
    CompressionMethod: Uint32;
    Width: Uint32;
    Height: Uint32;
  end;

  PGZBufferRawSpriteHeader = ^TGZBufferRawSpriteHeader;
  TGZBufferRawSpriteHeader = packed record
    DataLength: Uint32; // Whole raw data including this header and strides
    Width: UInt16;
    Height: UInt16;
    Unk1: UInt16; // Always 4
    ColorType: UInt16; // Supposed to be TGZBufferColorType but in UInt16
    TransparentColor: UInt16; // Usually fuchsia in RGB 565 ($F81F)
    Unk2: UInt16; // Always 0, padding?
  end;

  // Strides counts always equal of height
  PGZBufferSpriteStrideInfo = ^TGZBufferSpriteStrideInfo;
  TGZBufferSpriteStrideInfo = packed record
    CurrentIndex: UInt32; // Current index position of stride
    // First index of stride to start write data
    StrideBegin: UInt16;
    // How much stride counts
    // Sometimes, it has $8000 prefix, which just substract with 32768
    StrideWidth: UInt16;
  end;

  // Returned from DecompressGZBufferImageToBmp*() functions for image info
  PGZBufferImageInfo = ^TGZBufferImageInfo;
  TGZBufferImageInfo = record
    DecompressedLength: Integer;
    CompressionRatio: Single;
    Width: Integer;
    Height: Integer;
    ColorType: TGZBufferColorType;
  end;

  // Returned from DecompressGZBufferSpriteToBmp*() functions for sprite info
  PGZBufferSpriteInfo = ^TGZBufferSpriteInfo;
  TGZBufferSpriteInfo = record
    DecompressedLength: Integer;
    CompressionRatio: Single;
    Width: Integer;
    Height: Integer;
    ColorType: TGZBufferColorType;
    CompressionType: TGZBufferSpriteCompressionType;
    SpriteType: TGZBufferSpriteType;
    TransparentColor16: UInt16; // Ignored on stSpriteMask
  end;

  EGZBufferException = class(Exception);
  EGZBufferImageException = class(EGZBufferException);
  EGZBufferSpriteException = class(EGZBufferException);
  EGZBufferBitmapException = class(EGZBufferException);

  function ReadGZBufferCompressedImageHeader(const HeaderPtr: Pointer):
    TGZBufferCompressedImageHeader; inline;
  function ReadGZBufferCompressedSpriteHeader(const HeaderPtr: Pointer):
    TGZBufferCompressedSpriteHeader; inline;

  function DetectGZBufferImageType(const HeaderPtr: Pointer): TGZBufferImageType;
  function DetectGZBufferSpriteCompressionType(const Source: Pointer;
    const SourceLength: Integer): TGZBufferSpriteCompressionType;
  function DetectGZBufferImageIsActuallySprite(const Source: Pointer): Boolean;

  function DecompressGZBufferImageToRaw(const Source: Pointer;
    const SourceLength: Integer; var ImageInfo: TGZBufferImageInfo): PByte;

  function DecompressGZBufferImageToBmpNativeStreamEx(const Source: Pointer;
    const SourceLength: Integer; DestStream: TStream;
    var ImageInfo: TGZBufferImageInfo): Boolean;
  function DecompressGZBufferImageToBmpNativeStream(const Source: Pointer;
    const SourceLength: Integer; DestStream: TStream): Boolean; inline;

  function DecompressGZBufferImageToBmp32StreamEx(const Source: Pointer;
    const SourceLength: Integer; DestStream: TStream;
    var ImageInfo: TGZBufferImageInfo): Boolean;
  function DecompressGZBufferImageToBmp32Stream(const Source: Pointer;
    const SourceLength: Integer; DestStream: TStream): Boolean; inline;

  function DecompressGZBufferSpriteToRaw(const Source: Pointer;
    const SourceLength: Integer; var SpriteInfo: TGZBufferSpriteInfo): PByte;

  function DecompressGZBufferSpriteToBmpNativeStreamEx(const Source: Pointer;
    const SourceLength: Integer; DestStream: TStream;
    var SpriteInfo: TGZBufferSpriteInfo): Boolean;
  function DecompressGZBufferSpriteToBmpNativeStream(const Source: Pointer;
    const SourceLength: Integer; DestStream: TStream): Boolean; inline;

  function DecompressGZBufferSpriteToBmp32StreamEx(const Source: Pointer;
    const SourceLength: Integer; DestStream: TStream;
    var SpriteInfo: TGZBufferSpriteInfo): Boolean;
  function DecompressGZBufferSpriteToBmp32Stream(const Source: Pointer;
    const SourceLength: Integer; DestStream: TStream): Boolean; inline;

  function GZBufferColorTypeToString(ColorType: TGZBufferColorType): String;
  function GZBufferImageTypeToString(ImageType: TGZBufferImageType): String;
  function GZBufferSpriteCompressionTypeToString(CompressionType:
    TGZBufferSpriteCompressionType): String;

implementation

// As I prefer to make bitmap file from scratch that works cross-platform
// without Windows API bitmap definitions, here's subset of BMP headers used.
// This approach is also platform and library independent as doesn't need any
// Delphi like TGraphic and FPC/Lazarus TLazIntfImage and TRawImage.

const
  BMP_HEADER_SIGNATURE = $4D42; // BM header for little endian

type
  // BITMAPFILEHEADER
  PRawBitmapFileHeader = ^TRawBitmapFileHeader;
  TRawBitmapFileHeader = packed record
    BitmapType: UInt16; // BM
    FileSize: Int32;
    Reserved1: Int16;
    Reserved2: Int16;
    OffsetBits: UInt32;
  end;

  TRawBitmapCIEXYZ = packed record
    X: Int32;
    Y: Int32;
    Z: Int32;
  end;

  TRawBitmapCIEXYZTriple = packed record
    Red: TRawBitmapCIEXYZ;
    Green: TRawBitmapCIEXYZ;
    Blue: TRawBitmapCIEXYZ;
  end;

  // Based from BITMAPV4HEADER, although I prefer to forgotten BITMAPV3HEADER
  // because it's already support for 16-bit color, but some Linux DE didn't
  // support that.
  PRawBitmapImageHeader = ^TRawBitmapImageHeader;
  TRawBitmapImageHeader = packed record
    SizeHeader: UInt32;
    Width: UInt32;
    Height: UInt32;
    Planes: Int16;
    BitCount: Int16;
    Compression: UInt32;
    ImageSize: UInt32;
    PpmX: UInt32;
    PpmY: UInt32;
    ClrUsed: UInt32;
    ClrImportant: UInt32;
    RedMask: UInt32;
    GreenMask: UInt32;
    BlueMask: UInt32;
    AlphaMask: UInt32;
    CSType: UInt32;
    Endpints: TRawBitmapCIEXYZTriple;
    GammaRed: UInt32;
    GammaGreen: UInt32;
    GammaBlue: UInt32;
  end;

function ReadGZBufferCompressedImageHeader(const HeaderPtr: Pointer):
  TGZBufferCompressedImageHeader; inline;
begin
  Result := PGZBufferCompressedImageHeader(HeaderPtr)^;
end;

function ReadGZBufferCompressedSpriteHeader(const HeaderPtr: Pointer):
  TGZBufferCompressedSpriteHeader; inline;
begin
  Result := PGZBufferCompressedSpriteHeader(HeaderPtr)^;
end;

// This needed because there's difference between SC3K and SC3U.
// Both occupied type $62B9DA24 for image buffer, but SC3K use raw uncompressed
// bitmap, in contrast later SC3U use 16-bits color data compressed in RefPack
// and use header like TGZBufferCompressedImageHeader defined in this unit.
function DetectGZBufferImageType(const HeaderPtr: Pointer): TGZBufferImageType;
var
  hdr: TGZBufferCompressedImageHeader;
begin
  Result := itUnknown;
  // 'BM' signature
  if PUInt16(HeaderPtr)^ = BMP_HEADER_SIGNATURE then
    // Next entry is file size, which can't be null
    if PUInt32(HeaderPtr + SizeOf(UInt16))^ > 0 then
      Result := itBitmap;
  // Not detected as bitmap
  if Result <> itBitmap then begin
    hdr := ReadGZBufferCompressedImageHeader(HeaderPtr);
    with hdr do
      if (BytesPerPixel = 2) and (CompressedSize > 0) and
        (Width > 0) and (Height > 0) and (ColorType > 0) then
          Result := itRefPack;
  end;
end;

// Detect whether sprite uses MiniLZO (SC3K) or RefPack (later SC3U)
// This because both compression use sprite type $00000000 and
// TGZBufferCompressedSpriteHeader not tell you which actually used.
// RefPack is more obvious, as it always have $FB10 constant signature.
function DetectGZBufferSpriteCompressionType(const Source: Pointer;
  const SourceLength: Integer): TGZBufferSpriteCompressionType;
var
  pl: PUInt32;
  pw: PUInt16;
  ph: PRZCompressedLZOHeader;
begin
  Result := sctUnknown;
  // Detecting RefPack first
  pl := Pointer(Source + SizeOf(TGZBufferCompressedSpriteHeader));
  pw := Pointer(Source + SizeOf(TGZBufferCompressedSpriteHeader) +
    SizeOf(UInt32));
  if (pw^ = REFPACK_HEADER_SIGNATURE) and (pl^ = SourceLength -
    SizeOf(TGZBufferCompressedSpriteHeader)) then
    Result := sctRefPack
  else begin
    // Not RefPack, try to match if this probably MiniLZO
    ph := PRZCompressedLZOHeader(pl);
    if (ph^.CompressedLength = SourceLength -
      SizeOf(TGZBufferCompressedSpriteHeader))
      and (ph^.UncompressedLength > 0) then
      Result := sctMiniLZO;
  end;
end;

// This function exists because whoever programmer at Maxis put sprite data
// on resource type $62B9DA24 on *.sjs suitcase file which suppossed for
// image buffer, while sprites should be on designated type $00000000
function DetectGZBufferImageIsActuallySprite(const Source: Pointer): Boolean;
begin
  // On real image buffer, all 4 bytes is occupied and only contains 2 to
  // indicate bytes per pixel. Otherwise it would be $105, $107, or $03
  Result := PUInt32(Source)^ <> 2;
end;

// Convert RGB 565 to BGRA32 with Alpha always opaque
//function RGB565OpaqueToBGRA32(const Val: UInt16): UInt32; inline;
//var
//  r, g, b: Integer;
//begin
//  r := (Val shr 8) and $F8; // 11111000
//  g := (Val shr 3) and $FC; // 11111100
//  b := (Val shl 3) and $F8; // 11111000
//  // BBBBB000 GGGGGG00 RRRRR000 AAAAAAAA
//  Result := $FF000000 or (r shl 16) or (g shl 8) or b;
//end;

// Convert RGB 565 to BGRA32 with Alpha transparency if transparent color exists
function RGB565AlphaToBGRA32(const Val: UInt16;
  const AlphaColor: UInt16 = GZBUFFER_TRANSPARENT_COLOR16): UInt32; inline;
var
  r, g, b: Integer;
begin
  r := (Val shr 8) and $F8; // 11111000
  g := (Val shr 3) and $FC; // 11111100
  b := (Val shl 3) and $F8; // 11111000
  // BBBBB000 GGGGGG00 RRRRR000 AAAAAAAA
  Result := ((Integer(Val <> AlphaColor) and 1) * $FF000000) or
    (r shl 16) or (g shl 8) or b;
end;

// Convert RGB 555 to BGRA32 with Alpha transparency if transparent color exists
function RGB555AlphaToBGRA32(const Val: UInt16;
  const AlphaColor: UInt16 = GZBUFFER_TRANSPARENT_COLOR16): UInt32; inline;
var
  r, g, b: Integer;
begin
  r := (Val shr 7) and $F8; // 11111000
  g := (Val shr 2) and $F8; // 11111000
  b := (Val shl 3) and $F8; // 11111000
  // BBBBB000 GGGGG000 RRRRR000 AAAAAAAA
  Result := ((Integer(Val <> AlphaColor) and 1) * $FF000000) or
    (r shl 16) or (g shl 8) or b;
end;

function PrepareRawBitmapFileHeader(ColorType: TGZBufferColorType;
  W, H: Integer; var HeaderLength: Integer): Pointer;
var
  pHdr: Pointer;
  hdrLength, fileSize, imgSize, bmpStrideLength: Integer;
  pBfh: PRawBitmapFileHeader;
  pBih: PRawBitmapImageHeader;
  bits, ppm: Integer;
  i, grad: Integer;
  palColor: PUInt32;
  aMask, rMask, gMask, bMask, palSize, compressMode: UInt32;
begin
  compressMode := 0; // BI_RGB
  palSize := 0;
  aMask := 0;
  rMask := 0;
  gMask := 0;
  bMask := 0;
  case ColorType of
    ctColorBGRA32:
      begin
        bits := 32;
      end;
    ctColorRGB565:
      begin
        bits := 16;
        rMask := $F800; // 11111000 00000000
        gMask := $7E0;  // 00000111 11100000
        bMask := $1F;   // 00000000 00011111
        compressMode := 3; // BI_BITFIELDS
      end;
    ctColorRGB555:
      begin
        bits := 16;
        rMask := $7C00; // 01111100 00000000
        gMask := $3E0;  // 00000011 11100000
        bMask := $1F;   // 00000000 00011111
        compressMode := 3; // BI_BITFIELDS
      end;
    ctColorPal8:
      begin
        bits := 8;
        palSize := SizeOf(UInt32) * 256;
      end;
    else
      // Unsupported color type
      Result := nil;
      raise EGZBufferBitmapException.Create('Unsupported bitmap color type');
      Exit;
  end;
  hdrLength := SizeOf(TRawBitmapFileHeader) +
    SizeOf(TRawBitmapImageHeader) + palSize;
  GetMem(pHdr, hdrLength);
  FillChar(pHdr^, hdrLength, 0);
  pBfh := pHdr;
  pBih := pHdr + SizeOf(TRawBitmapFileHeader);
  // https://learn.microsoft.com/en-us/previous-versions/ms969901(v=msdn.10)
  // See at biSizeImage
  bmpStrideLength := (((W * bits) + 31) and not 31) shr 3;
  imgSize := bmpStrideLength * H;
  fileSize := hdrLength + imgSize;
  ppm := 3780; // 96 {dpi} * 39.375
  pBfh^.BitmapType := BMP_HEADER_SIGNATURE;
  pBfh^.FileSize := fileSize;
  pBfh^.OffsetBits := hdrLength;
  with pBih^ do begin
    SizeHeader := SizeOf(TRawBitmapImageHeader);
    Width := W;
    Height := H;
    Planes := 1;
    BitCount := bits;
    Compression := compressMode;
    ImageSize := imgSize;
    PpmX := ppm;
    PpmY := ppm;
    // Only used in indexed color like 8-bit
    ClrUsed := palSize div SizeOf(UInt32);
    RedMask := rMask;
    GreenMask := gMask;
    BlueMask := bMask;
    AlphaMask := aMask;
  end;
  // For indexed mode like 8-bit ctColorPal8, bake gradient color palette here
  if palSize > 0 then begin
    palColor := pHdr + SizeOf(TRawBitmapFileHeader) +
      SizeOf(TRawBitmapImageHeader);
    for i := 0 to $FF do begin
      // Gradient from light to dark
      grad := (not i) and $FF;
      // Fill RGB on ARGB 32
      palColor[i] := (grad shl 16) or (grad shl 8) or grad;
    end;
  end;
  HeaderLength := hdrLength;
  Result := pHdr;
end;

// So why use TStream instead use TBitmap directly? Well, my first attempt is
// using TBitmap ScanLines as like I did in Delphi, but Lazarus/FPC isn't behave
// like Delphi as their PixelFormat=pf16bit won't correctly OOB, it keep give me
// 32-bit RGBA scanline. I'm also tried TLazIntfImage and TRawImage which have
// more greater control to image buffer. But in the end, I just prepare raw
// bitmap directly as Microsoft specifications since would use less memory and
// less data copy needed, also TBitmap would be accept this constructed bitmap
// just fine (with caveats, FPC/Lazarus seems has minor problems rendering
// from 16-bits color bitmaps which makes color banding much more noticeable,
// that's why there's direct to 32-bit bitmap conversion to circumvent this).
function RawGZBufferToBitmap(const BitsData: Pointer; W, H: Integer;
  ColorType: TGZBufferColorType; DestStream: TStream): Boolean;
var
  pBmpHdr: PRawBitmapFileHeader;
  bits, bpp, bmpHdrLength, strideLength, align, bmpStrideLength, y: Integer;
  pStride: PWord;
  nullPadding: NativeUInt;
begin
  case ColorType of
    ctColorBGRA32:
      begin
        bits := 32;
        bpp := SizeOf(UInt32);
      end;
    ctColorRGB565, ctColorRGB555:
      begin
        bits := 16;
        bpp := SizeOf(UInt16);
      end;
    ctColorPal8:
      begin
        bits := 8;
        bpp := SizeOf(UInt8);
      end;
    else
      // Unsupported color type
      Result := False;
      raise EGZBufferBitmapException.Create('Unsupported bitmap color type');
      Exit;
  end;
  bmpHdrLength := 0;
  pBmpHdr := PrepareRawBitmapFileHeader(ColorType, W, H, bmpHdrLength);
  try
    DestStream.Write(pBmpHdr^, bmpHdrLength);
  finally
    FreeMem(pBmpHdr);
  end;
  // As I mentioned before, this follows biSizeImage from MS documentation
  bmpStrideLength := (((W * bits) + 31) and not 31) shr 3;
  strideLength := W * bpp;
  align := bmpStrideLength - strideLength;
  nullPadding := 0;
  for y := 0 to H - 1 do begin
    // Bitmap stride vertical order is flipped, from bottom to top
    pStride := Pointer(BitsData + (H - y - 1) * W * bpp);
    // Just copy whole stride line
    DestStream.Write(pStride^, strideLength);
    // Bitmap data must have 4-bytes align per stride, else some will skew
    if align > 0 then
      DestStream.Write(nullPadding, align);
  end;
  Result := True
end;

function DecompressGZBufferImageToRaw(const Source: Pointer;
  const SourceLength: Integer; var ImageInfo: TGZBufferImageInfo): PByte;
var
  header: TGZBufferCompressedImageHeader;
  decLength: LongWord;
  w, h, expectedLength: Integer;
  pd: PByte;
  colorType: TGZBufferColorType;
begin
  FillChar(ImageInfo, SizeOf(TGZBufferImageInfo), 0);
  if SizeOf(TGZBufferCompressedImageHeader) > SourceLength then begin
    Result := nil;
    raise EGZBufferImageException.Create('Invalid Source length');
    Exit;
  end;
  header := ReadGZBufferCompressedImageHeader(Source);
  if header.BytesPerPixel <> 2 then begin
    Result := nil;
    raise EGZBufferImageException.Create('Unsupported graphics bits');
    Exit;
  end;
  colorType := TGZBufferColorType(header.ColorType);
  if colorType <> ctColorRGB565 then begin
    Result := nil;
    raise EGZBufferImageException.Create('Unsupported graphics color mode');
    Exit;
  end;
  w := header.Width;
  h := header.Height;
  // Skipping 4 bytes of length header and decompress now
  decLength := 0;
  // It's always use RefPack in SC3U since SC3K use raw BMP for image buffers
  pd := RefPackDecompress(
    Pointer(Source + SizeOf(TGZBufferCompressedImageHeader) + SizeOf(UInt32))^,
    SourceLength - SizeOf(TGZBufferCompressedImageHeader) - SizeOf(UInt32),
    decLength);
  if pd = nil then begin
    Result := nil;
    raise EGZBufferImageException.Create('Error when decompressing image buffer');
    Exit;
  end;
  expectedLength := w * h * SizeOf(Uint16);
  if decLength <> expectedLength then begin
    FreeMem(pd);
    Result := nil;
    raise EGZBufferImageException.Create('Decompressed image buffer size mismatch');
    Exit;
  end;
  ImageInfo.DecompressedLength := decLength;
  ImageInfo.CompressionRatio := (SourceLength / decLength) * 100;
  ImageInfo.Width := w;
  ImageInfo.Height := h;
  ImageInfo.ColorType := colorType;
  Result := pd;
end;

function DecompressGZBufferImageToBmpNativeStreamEx(const Source: Pointer;
  const SourceLength: Integer; DestStream: TStream;
  var ImageInfo: TGZBufferImageInfo): Boolean;
var
  pd: PByte;
  imgInfo: TGZBufferImageInfo;
begin
  imgInfo := Default(TGZBufferImageInfo);
  pd := DecompressGZBufferImageToRaw(Source, SourceLength, imgInfo);
  if pd = nil then begin
    Result := False;
    Exit;
  end;
  try
    ImageInfo := imgInfo;
    Result := RawGZBufferToBitmap(pd, imgInfo.Width, imgInfo.Height,
      imgInfo.ColorType, DestStream);
  finally
    FreeMem(pd);
  end;
end;

function DecompressGZBufferImageToBmpNativeStream(const Source: Pointer;
  const SourceLength: Integer; DestStream: TStream): Boolean; inline;
var
  imgInfo: TGZBufferImageInfo;
begin
  imgInfo := Default(TGZBufferImageInfo);
  Result := DecompressGZBufferImageToBmpNativeStreamEx(Source, SourceLength,
    DestStream, imgInfo);
end;

function DecompressGZBufferImageToBmp32StreamEx(const Source: Pointer;
  const SourceLength: Integer; DestStream: TStream;
  var ImageInfo: TGZBufferImageInfo): Boolean;
var
  pd: PByte;
  imgInfo: TGZBufferImageInfo;
  newColorType: TGZBufferColorType;
  newBuf: Pointer;
  pw: PUInt32;
  pr: PUInt16;
  argbBufLength, w, h, x, y: Integer;
begin
  imgInfo := Default(TGZBufferImageInfo);
  pd := DecompressGZBufferImageToRaw(Source, SourceLength, imgInfo);
  if pd = nil then begin
    Result := False;
    Exit;
  end;
  try
    w := imgInfo.Width;
    h := imgInfo.Height;
    newColorType := ctColorBGRA32;
    argbBufLength := w * h * SizeOf(UInt32);
    GetMem(newBuf, argbBufLength);
    try
      for y := 0 to h - 1 do begin
        pw := PUInt32(newBuf + y * w * SizeOf(UInt32));
        pr := PUInt16(pd + y * w * SizeOf(UInt16));
        for x := 0 to w -1 do
          pw[x] := RGB565AlphaToBGRA32(pr[x]);
      end;
      ImageInfo := imgInfo;
      Result := RawGZBufferToBitmap(newBuf, w, h, newColorType, DestStream);
    finally
      FreeMem(newBuf);
    end;
  finally
    FreeMem(pd);
  end;
end;

function DecompressGZBufferImageToBmp32Stream(const Source: Pointer;
  const SourceLength: Integer; DestStream: TStream): Boolean; inline;
var
  imgInfo: TGZBufferImageInfo;
begin
  imgInfo := Default(TGZBufferImageInfo);
  Result := DecompressGZBufferImageToBmp32StreamEx(Source, SourceLength,
    DestStream, imgInfo);
end;

function DecompressGZBufferSpriteToRaw(const Source: Pointer;
  const SourceLength: Integer; var SpriteInfo: TGZBufferSpriteInfo): PByte;
var
  cmpHeader: TGZBufferCompressedSpriteHeader;
  decHeader: PGZBufferRawSpriteHeader;
  psi: PGZBufferSpriteStrideInfo;
  decLength: LongWord;
  compressType: TGZBufferSpriteCompressionType;
  w, h, x, y, rawWH, rawLength, wIdx, rIdx, remain: Integer;
  stWidth, stBegin: Integer;
  pd: PByte;
  pw, pr: PWord;
  done, hasDecHeader: Boolean;
  dataPos: Pointer;
  dataLength: NativeInt;
  colorType: TGZBufferColorType;
  transColor: UInt16;
begin
  FillChar(SpriteInfo, SizeOf(TGZBufferSpriteInfo), 0);
  done := False;
  if SizeOf(TGZBufferCompressedSpriteHeader) > SourceLength then begin
    Result := nil;
    raise EGZBufferSpriteException.Create('Invalid Source length');
    Exit;
  end;
  cmpHeader := ReadGZBufferCompressedSpriteHeader(Source);
  w := cmpHeader.Width;
  h := cmpHeader.Height;
  pd := nil;
  decLength := 0;
  compressType := DetectGZBufferSpriteCompressionType(Source, SourceLength);
  // Compressed data
  case compressType of
    sctMiniLZO:
      begin
        dataPos := Pointer(Source + SizeOf(TGZBufferCompressedSpriteHeader));
        dataLength := SourceLength - SizeOf(TGZBufferCompressedSpriteHeader);
        pd := RZMiniLZODecompress(dataPos^, dataLength, decLength);
      end;
    sctRefPack:
      begin
        dataPos := Pointer(Source + SizeOf(TGZBufferCompressedSpriteHeader) +
          SizeOf(UInt32));
        dataLength := SourceLength - SizeOf(TGZBufferCompressedSpriteHeader) -
          SizeOf(UInt32);
        pd := RefPackDecompress(dataPos^, dataLength, decLength);
      end;
    else
      Result := nil;
      raise EGZBufferSpriteException.Create('Cannot determine sprite compression');
      Exit;
  end;
  if pd = nil then begin
    Result := nil;
    Exit;
  end;
  pw := nil; // Set to nil, to remind pd not be used by default
  try
    hasDecHeader := cmpHeader.HasDecompressedHeader <> 0;
    colorType := TGZBufferColorType(cmpHeader.ColorType);
    // Has header, likely variable length stride
    if hasDecHeader then begin
      // Only RGB 565 and RGB 555 were supported
      if (colorType <> ctColorRGB565) and (colorType <> ctColorRGB555) then
        begin
        Result := nil;
        raise EGZBufferSpriteException.Create('Unsupported color type');
        Exit;
      end;
      decHeader := PGZBufferRawSpriteHeader(pd);
      if decHeader^.DataLength <> decLength then begin
        Result := nil;
        raise EGZBufferSpriteException.Create('Mismatch decompressed data');
        Exit;
      end;
      with decHeader^ do
        if (Width <> w) or (Height <> h) then begin
          Result := nil;
          raise EGZBufferSpriteException.Create('Mismatch size between compressed and decompressed');
          Exit;
        end;
      transColor := decHeader^.TransparentColor;
      psi := PGZBufferSpriteStrideInfo(pd + SizeOf(TGZBufferRawSpriteHeader));
      rawWH := w * h;
      rawLength := rawWH * SizeOf(UInt16);
      GetMem(pw, rawLength);
      try
        // Fill strides
        pr := PWord(pd + SizeOf(TGZBufferRawSpriteHeader) +
          (SizeOf(TGZBufferSpriteStrideInfo) * h));
        wIdx := 0;
        rIdx := 0;
        for y := 0 to h-1 do begin
          with psi[y] do begin
            // TODO: Examine this, dunno why they did this?
            stBegin := StrideBegin;
            stWidth := StrideWidth and (not $8000);
            //if StrideWidth >= $8000 then
            //  stWidth := StrideWidth - $8000
            //else
            //  stWidth := StrideWidth;
            //if testMask then begin
            //  for x := 0 to w - 1 do
            //    pw[wIdx + x] := transColor;
            //  Inc(wIdx, w);
            //  Inc(rIdx, stWidth);
            //  continue;
            //end;
          end;
          // Fill transparent pixels before non-transparent
          for x := 0 to stBegin - 1 do
            pw[wIdx + x] := transColor;
          Inc(wIdx, stBegin);
          // Fill actual non-transparent pixels
          // Stride's CurrentIndex can't be always trusted,
          // sometimes it just gives 0 on large sprites!
          //rIdx := CurrentIndex;
          for x := 0 to stWidth - 1 do begin
            pw[wIdx + x] := pr[rIdx];
            Inc(rIdx);
          end;
          Inc(wIdx, stWidth);
          // Fill remaining transparent pixels
          remain := w  - (stBegin + stWidth);
          for x := 0 to remain - 1 do
            pw[wIdx + x] := decHeader^.TransparentColor;
          Inc(wIdx, remain);
        end;
        SpriteInfo.DecompressedLength := decLength;
        SpriteInfo.CompressionRatio := (SourceLength / decLength) * 100;
        SpriteInfo.Width := w;
        SpriteInfo.Height := h;
        SpriteInfo.ColorType := colorType;
        SpriteInfo.CompressionType := compressType;
        SpriteInfo.SpriteType := stSpriteBuffer;
        SpriteInfo.TransparentColor16 := transColor;
        Result := PByte(pw);
        done := True;
      finally
        if not done then begin
          FreeMem(pw);
          pw := nil;
        end;
      end;
    end
    else begin
      // It's just sprite mask which raw 8 bit monochrome without header
      if colorType = ctColorPal8 then begin
        SpriteInfo.DecompressedLength := decLength;
        SpriteInfo.CompressionRatio := (SourceLength / decLength) * 100;
        SpriteInfo.Width := w;
        SpriteInfo.Height := h;
        SpriteInfo.ColorType := colorType;
        SpriteInfo.CompressionType := compressType;
        SpriteInfo.SpriteType := stSpriteMask;
        SpriteInfo.TransparentColor16 := transColor;
        Result := pd;
        done := True;
      end
      else begin
        Result := nil;
        Exit;
      end;
    end;
  finally
    if (pw <> nil) or (not done) then
      FreeMem(pd);
  end;
end;

function DecompressGZBufferSpriteToBmpNativeStreamEx(const Source: Pointer;
  const SourceLength: Integer; DestStream: TStream;
  var SpriteInfo: TGZBufferSpriteInfo): Boolean;
var
  pd: PByte;
  sprInfo: TGZBufferSpriteInfo;
begin
  sprInfo := Default(TGZBufferSpriteInfo);
  pd := DecompressGZBufferSpriteToRaw(Source, SourceLength, sprInfo);
  if pd = nil then begin
    Result := False;
    Exit;
  end;
  try
    SpriteInfo := sprInfo;
    Result := RawGZBufferToBitmap(pd, sprInfo.Width, sprInfo.Height,
      sprInfo.ColorType, DestStream);
  finally
    FreeMem(pd);
  end;
end;

function DecompressGZBufferSpriteToBmpNativeStream(const Source: Pointer;
  const SourceLength: Integer; DestStream: TStream): Boolean; inline;
var
  sprInfo: TGZBufferSpriteInfo;
begin
  sprInfo := Default(TGZBufferSpriteInfo);
  Result := DecompressGZBufferSpriteToBmpNativeStreamEx(Source, SourceLength,
    DestStream, sprInfo);
end;

function DecompressGZBufferSpriteToBmp32StreamEx(const Source: Pointer;
  const SourceLength: Integer; DestStream: TStream;
  var SpriteInfo: TGZBufferSpriteInfo): Boolean;
var
  pd: PByte;
  sprInfo: TGZBufferSpriteInfo;
  oldColorType, newColorType: TGZBufferColorType;
  newBuf: Pointer;
  pw: PUInt32;
  pr: PUInt16;
  pb: PUInt8;
  argbBufLength, w, h, x, y: Integer;
  transColor: UInt16;
  grad: Integer;
begin
  sprInfo := Default(TGZBufferSpriteInfo);
  pd := DecompressGZBufferSpriteToRaw(Source, SourceLength, sprInfo);
  if pd = nil then begin
    Result := False;
    Exit;
  end;
  try
    w := sprInfo.Width;
    h := sprInfo.Height;
    oldColorType := sprInfo.ColorType;
    newColorType := ctColorBGRA32;
    transColor := sprInfo.TransparentColor16;
    argbBufLength := w * h * SizeOf(UInt32);
    GetMem(newBuf, argbBufLength);
    try
      for y := 0 to h - 1 do begin
        pw := PUInt32(newBuf + y * w * SizeOf(UInt32));
        case oldColorType of
          ctColorRGB565:
            begin
              pr := PUInt16(pd + y * w * SizeOf(UInt16));
              for x := 0 to w -1 do
                pw[x] := RGB565AlphaToBGRA32(pr[x], transColor);
            end;
          ctColorRGB555:
            begin
              pr := PUInt16(pd + y * w * SizeOf(UInt16));
              for x := 0 to w -1 do
                pw[x] := RGB555AlphaToBGRA32(pr[x], transColor);
            end;
          ctColorPal8:
            begin
              pb := PUInt8(pd + y * w * SizeOf(UInt8));
              for x := 0 to w -1 do begin
                grad := (not pb[x]) and $FF;
                pw[x] := $FF000000 or (grad shl 16) or (grad shl 8) or grad;
              end;
            end;
        end;
      end;
      SpriteInfo := sprInfo;
      Result := RawGZBufferToBitmap(newBuf, w, h, newColorType, DestStream);
    finally
      FreeMem(newBuf);
    end;
  finally
    FreeMem(pd);
  end;
end;

function DecompressGZBufferSpriteToBmp32Stream(const Source: Pointer;
  const SourceLength: Integer; DestStream: TStream): Boolean; inline;
var
  sprInfo: TGZBufferSpriteInfo;
begin
  sprInfo := Default(TGZBufferSpriteInfo);
  Result := DecompressGZBufferSpriteToBmp32StreamEx(Source, SourceLength,
    DestStream, sprInfo);
end;

function GZBufferColorTypeToString(ColorType: TGZBufferColorType): String;
begin
  case ColorType of
    ctColorNative  : Result := 'Native';
    ctColorPal4    : Result := 'Palette 4-bit';
    ctColorPal8    : Result := 'Palette 8-bit';
    ctColorRGB16   : Result := 'RGB 16-bit';
    ctColorRGB555  : Result := 'RGB 555';
    ctColorRGB655  : Result := 'RGB 655';
    ctColorRGB565  : Result := 'RGB 565';
    ctColorRGB556  : Result := 'RGB 556';
    ctColorRGBA5551: Result := 'RGBA 5551';
    ctColorARGB1555: Result := 'ARGB 1555';
    ctColorRGBA4444: Result := 'RGBA 4444';
    ctColorARGB4444: Result := 'ARGB 4444';
    ctColorRGB24   : Result := 'RGB 24';
    ctColorARGB32  : Result := 'ARGB 32';
    else
      Result := 'Invalid';
  end;
end;

function GZBufferImageTypeToString(ImageType: TGZBufferImageType): String;
begin
  case ImageType of
    itBitmap: Result := 'Bitmap';
    itRefPack: Result := 'RefPack';
    else
      Result := 'Unknown';
  end;
end;

function GZBufferSpriteCompressionTypeToString(CompressionType:
  TGZBufferSpriteCompressionType): String;
begin
  case CompressionType of
    sctMiniLZO: Result := 'MiniLZO';
    sctRefPack: Result := 'RefPack';
    else
      Result := 'Unknown';
  end;
end;

end.

