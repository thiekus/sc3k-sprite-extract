unit refpack;

//
// RefPack/QFS Decompression Function for Pascal
// Ported by Thiekus (https://thiekus.com/) based from QfsCompression.cs of
// DBPFSharp by Null45 (https://github.com/0xC0000054/DBPFSharp)
//
// Copyright (C) 2025 Thiekus
// Copyright (C) 2023, 2025 Nicholas Hayes
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
// Note: this code didn't port Zlib portions that used for compression, which
// licensed under Zlib license.
//

{$mode ObjFPC}{$H+}

interface

uses
  SysUtils;

// There's many variants of RefPack compression, SC3K seems use the older one
{.$DEFINE REFPACK_HAS_FLAGS}

const
  REFPACK_HEADER_SIGNATURE = $FB10; // Little endian of $10FB

  function RefPackDecompress(const CompressedInput; const CompressedLength:
    Integer; var DecompressedLength: LongWord): Pointer;

implementation

{$IFDEF REFPACK_HAS_FLAGS}
const
  REFPACK_LARGE_SIZE_FIELDS = 128;
  REFPACK_COMPRESSED_SIZE_PRESENT = 1;
{$ENDIF}

function RefPackDecompress(const CompressedInput; const CompressedLength:
  Integer; var DecompressedLength: LongWord): Pointer;
var
  pc, pd: PByte; // compressed and decompressed
  cb1, cb2, cb3, cb4: Byte;
  index, outIndex: Integer;
  pHeadSig: PUint16;
  outLength: UInt32;
  plainCount, copyCount, copyOffset, length, srcIndex, i: Integer;
  {$IFDEF REFPACK_HAS_FLAGS}
  pHeadFlags: PByte;
  largeSizeFields, compressedSizePresent: Boolean;
  {$ENDIF}
begin
  pc := @CompressedInput;
  pHeadSig := PUInt16(pc);
  if pHeadSig^ <> REFPACK_HEADER_SIGNATURE then begin
    Result := nil;
    Exit;
  end;

  index := SizeOf(Uint16);

  {$IFDEF REFPACK_HAS_FLAGS}
  pHeadFlags := PByte(pc) + index;
  largeSizeFields := (pHeadFlags^ and REFPACK_LARGE_SIZE_FIELDS) <> 0;
  compressedSizePresent := (pHeadFlags^ and REFPACK_COMPRESSED_SIZE_PRESENT) <> 0;

  if compressedSizePresent then
    if largeSizeFields then
      Inc(index, 4)
    else
      Inc(index, 3);

  if largeSizeFields then begin
    outLength := UInt32((pc^[index] shl 24) or (pc^[index + 1] shl 16) or
      (pc^[index + 2] shl 8) or pc^[index + 3]);
    Inc(index, 4);
  end
  else begin
    outLength := UInt32((pc^[index] shl 16) or
      (pc^[index + 1] shl 8) or pc^[index + 2]);
    Inc(index, 3);
  end;

  {$ELSE}

  // Decompressed size info on older RefPack straight up after signature header
  outLength := UInt32((pc[index] shl 16) or (pc[index + 1] shl 8) or
    pc[index + 2]);
  Inc(index, 3);

  {$ENDIF}

  cb1 := 0;
  cb2 := 0;
  cb3 := 0;
  cb4 := 0;
  outIndex := 0;
  plainCount := 0;
  copyCount := 0;
  copyOffset := 0;
  length := CompressedLength;
  pd := nil;
  GetMem(pd, outLength);

  while (index < length) and (pc[index] < $FC) do begin
    cb1 := pc[index];
    Inc(index);

    if cb1 >= $E0 then begin // 1 byte literal op code 0xE0 - 0xFB
      plainCount := ((cb1 and $1F) shl 2) + 4;
      copyCount := 0;
      copyOffset := 0;
    end
    else if cb1 >= $C0 then begin // 4 byte op code 0xC0 - 0xDF
      cb2 := pc[index];
      Inc(index);
      cb3 := pc[index];
      Inc(index);
      cb4 := pc[index];
      Inc(index);

      plainCount := cb1 and 3;
      copyCount := ((cb1 and $0C) shl 6) + cb4 + 5;
      copyOffset := ((cb1 and $10) shl 12) + (cb2 shl 8) + cb3 + 1;
    end
    else if cb1 >= $80 then begin // 3 byte op code 0x80 - 0xBF
      cb2 := pc[index];
      Inc(index);
      cb3 := pc[index];
      Inc(index);

      plainCount := (cb2 and $C0) shr 6;
      copyCount := (cb1 and $3F) + 4;
      copyOffset := ((cb2 and $3F) shl 8) + cb3 + 1;
    end
    else begin // 2 byte op code 0x00 - 0x7F
      cb2 := pc[index];
      Inc(index);

      plainCount := cb1 and 3;
      copyCount := (Byte(cb1 and $1C) shr 2) + 3;
      copyOffset := (Byte(cb1 and $60) shl 3) + cb2 + 1;
    end;

    for i := 0 to plainCount-1 do begin
      pd[outIndex] := pc[index];
      Inc(index);
      Inc(outIndex);
    end;

    if copyCount > 0 then begin
      srcIndex := outIndex - copyOffset;
      for i := 0 to copyCount-1 do begin
        pd[outIndex] := pd[srcIndex];
        Inc(srcIndex);
        Inc(outIndex);
      end;
    end;
  end;

  // Write the trailing bytes
  if (index < length) and (outIndex < outLength) then begin
    // 1 byte EOF op code 0xFC - 0xFF
    plainCount := pc[index] and 3;
    Inc(index);

    for i := 0 to plainCount-1 do begin
      pd[outIndex] := pc[index];
      Inc(index);
      Inc(outIndex);
    end;
  end;

  DecompressedLength := outLength;
  Result := pd;
end;

end.

