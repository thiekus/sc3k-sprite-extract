program sc3k_sprextract;

//
// SimCity 3000 GZBuffer Image and Sprite extraction CLI
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
// Note: This program uses port of minilzo, which is licensed under GPL v2
//

{$mode objfpc}{$H+}

uses
  {$IFDEF UNIX}
  cthreads,
  {$ENDIF}
  Classes,
  SysUtils,
  dbixf,
  gzbufferimg;

type
  TEntryType = (
    etUndefined,
    etImageBuffer,
    etSpriteBuffer
  );

procedure ShowHelp;
begin
  Writeln('Usage: sc3k_sprextract [-h,-bn,-b32,-o=<output dir>] <sprite archive.dat>');
  Writeln('');
  Writeln('-h   : Show this help.');
  Writeln('-bn  : Extract sprite to bitmap as their native bit format.');
  Writeln('-b32 : Extract sprite to bitmap and convert into BGRA32 format.');
  Writeln('-o   : Specify output directory of extracted sprites.');
  Writeln('       Default as <archive name>_extracted on current directory.');
end;

const
  PATH_SLASH = {$IF DEFINED (windows)} '\' {$ELSE} '/' {$ENDIF};

var
  parCount, parIdx, parLen, i, imgCount, sprCount: Integer;
  param, inPath, outPath, outFile, typeName: String;
  nativeColor: Boolean;
  ixf: TIxfDB;
  curType: TEntryType;
  entry: TIxfEntry;
  fs: TFileStream;
  imgInfo: TGZBufferImageInfo;
  sprInfo: TGZBufferSpriteInfo;

begin
  Writeln('SimCity 3000 Sprite Extractor');
  Writeln('Copyright (C) Thiekus 2025');
  Writeln('Visit my website https://thiekus.com for info and updates');
  Writeln('');

  if ParamCount < 1 then begin
    Writeln('No arguments found, use -h for help');
    Exit;
  end;

  nativeColor := True;
  inPath := '';
  outPath := '';

  // Now collecting command line params
  parCount := ParamCount;
  for parIdx := 1 to parCount do begin
    param := ParamStr(parIdx);
    parLen := Length(param);
    if parLen > 1 then
      if param[1] = '-' then begin
        if param = '-h' then begin
          ShowHelp;
          Exit;
        end
        else if param = '-bn' then
          nativeColor := True // No convert, color format as is
        else if param = '-b32' then
          nativeColor := False // Convert to 32-bit BGRA
        else if parLen > 3 then
          if (param[2] = 'o') and (param[3] = '=') then begin // -o= param
            outPath := Copy(param, 4, parLen - 3);
          end;
        continue;
      end;
    inPath := param;
  end;

  // Check input and output
  if inPath = '' then begin
    Writeln('Input file not specified, aborting!');
    Exit;
  end;
  if not FileExists(inPath) then begin
    Writeln('Input file ', inPath, ' not exists, aborting!');
    Exit;
  end;
  if outPath = '' then
    outPath := GetCurrentDir + PATH_SLASH + ExtractFileName(inPath) + '_extracted';

  // Now begin to read sprite.dat archive and extract them
  ixf := TIxfDB.Create;
  try
    ixf.LoadIxfFromFile(inPath);
    Writeln('IXF entries: ', ixf.Count);
    imgCount := 0;
    sprCount := 0;
    imgInfo := Default(TGZBufferImageInfo);
    sprInfo := Default(TGZBufferSpriteInfo);
    if not DirectoryExists(outPath) then
      CreateDir(outPath);
    for i := 0 to ixf.Count - 1 do begin
      entry := ixf.Entries[i];
      case entry.ResourceType of
        $62B9DA24: curType := etImageBuffer;
        $00000000: curType := etSpriteBuffer;
        else
          Continue; // Skip this type
      end;
      if curType = etSpriteBuffer then
        typeName := 'sprite'
      else
        typeName := 'image';
      outFile := outPath + PATH_SLASH + Format('%s_%.8x_%.8x.bmp',
        [typeName, entry.GroupID, entry.Instance]);
      fs := TFileStream.Create(outFile, fmCreate);
      try
        fs.Position := 0;
        if curType = etImageBuffer then begin
          if DetectGZBufferImageType(entry.RawData) = itBitmap then begin
            // Just ordinary BMP file, usually on first release of SC3K
            fs.Write(entry.RawData^, entry.RawLength);
            Writeln(
              Format('* Image Group=%.8x Instance=%.8x Format=Uncompressed BMP',
              [entry.GroupID, entry.Instance]));
          end
          else begin
            // SC3U has buffer compressed by RefPack
            if nativeColor then
              DecompressGZBufferImageToBmpNativeStreamEx(entry.RawData,
                entry.RawLength, fs, imgInfo)
            else
              DecompressGZBufferImageToBmp32StreamEx(entry.RawData,
                entry.RawLength, fs, imgInfo);
            Writeln(
              Format('* Image Group=%.8x Instance=%.8x Format=%s Compression=RefPack Size=%dx%d',
              [entry.GroupID, entry.Instance,
              GZBufferColorTypeToString(imgInfo.ColorType),
              imgInfo.Width, imgInfo.Height]));
          end;
          Inc(imgCount);
        end
        else begin
          // All sprites always compressed
          if nativeColor then
            DecompressGZBufferSpriteToBmpNativeStreamEx(entry.RawData,
              entry.RawLength, fs, sprInfo)
          else
            DecompressGZBufferSpriteToBmp32StreamEx(entry.RawData,
              entry.RawLength, fs, sprInfo);
          Writeln(
            Format('* Sprite Group=%.8x Instance=%.8x Format=%s Compression=%s Size=%dx%d',
            [entry.GroupID, entry.Instance,
            GZBufferColorTypeToString(sprInfo.ColorType),
            GZBufferSpriteCompressionTypeToString(sprInfo.CompressionType),
            sprInfo.Width, sprInfo.Height]));
          Inc(sprCount);
        end;
      finally
        fs.Free;
      end;
    end;
    Writeln(Format('Done, %d sprites and %d images extracted', [sprCount, imgCount]));
  finally
    ixf.Free;
  end;

end.

