unit rzminilzo;

//
// MiniLZO function helper based from SC3K cRZFasCompression
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
// or later license.
//

{$mode ObjFPC}{$H+}

interface

uses
  SysUtils, minilzo;

type
  // SimCity 3000 implementation has header info attached on compressed data
  PRZCompressedLZOHeader = ^TRZCompressedLZOHeader;
  TRZCompressedLZOHeader = packed record
    UncompressedLength: LongWord;
    CompressedLength: LongWord;
  end;

  function RZMiniLZOCompress(const Source; Length: LongWord;
    var CompressedLength: LongWord): Pointer;

  function RZMiniLZODecompress(const Source; Length: LongWord;
    var DecompressedLength: LongWord): Pointer;

implementation

// TODO: compressing not yet tested
function RZMiniLZOCompress(const Source; Length: LongWord;
  var CompressedLength: LongWord): Pointer;
var
  // LZO1X_MEM_COMPRESS+16 (16384 + SizeOf(PtrInt = 8 in 64 bit) + 16)
  workMem: array[0..$4018-1] of Byte;
  predCompressLength: NativeUInt;
  compressLength: LongWord;
  pd: Pointer;
  ok: Boolean;
  pHdr: PRZCompressedLZOHeader;
begin
  // Guessed of cRZFastCompression::GetMaxLengthRequiredForCompressedData
  predCompressLength := Length + Length div 64 + 16 + 3 +
    SizeOf(TRZCompressedLZOHeader);
  GetMem(pd, predCompressLength);
  ok := False;
  try
    ok := lzo1x_1_compress(@Source, Length,
      Pointer(pd + SizeOf(TRZCompressedLZOHeader)), @compressLength,
      @workMem) = LZO_E_OK;
    if ok then begin
      pHdr := pd;
      pHdr^.UncompressedLength := Length;
      pHdr^.CompressedLength := compressLength;
      CompressedLength := compressLength;
      Result := pd;
    end;
  finally
    if not ok then begin
      FreeMem(pd);
      Result := nil;
    end;
  end;
end;

function RZMiniLZODecompress(const Source; Length: LongWord;
  var DecompressedLength: LongWord): Pointer;
var
  pHdr: PRZCompressedLZOHeader;
  pd: Pointer;
  ok: Boolean;
  decLength: LongWord;
begin
  pHdr := @Source;
  if pHdr^.CompressedLength <> Length then begin
    // Invalid compressed length
    Result := nil;
    Exit;
  end;
  decLength := pHdr^.UncompressedLength;
  GetMem(pd, decLength);
  ok := False;
  try
    ok := lzo1x_decompress(Pointer(@Source + SizeOf(TRZCompressedLZOHeader)),
      Length - SizeOf(TRZCompressedLZOHeader), pd,
      @decLength, nil) = LZO_E_OK;
    if ok then begin
      DecompressedLength := decLength;
      Result := pd;
    end;
  finally
    if not ok then begin
      FreeMem(pd);
      Result := nil;
    end;
  end;
end;

end.

