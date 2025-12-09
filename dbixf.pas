unit dbixf;

//
// SimCity 3000 Indexed File Format Database functions
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

{$mode ObjFPC}{$H+}

interface

uses
  SysUtils, Classes, fgl;

const
  IXF_HEADER_SIGNATURE = $80C381D7; // Header that identify SC3K IXF file

type
  TIxfEntryKind = (
    ekUnknown = 0,
    ekString,
    ekImageBuffer,
    ekSpriteBuffer
  );

  // SimCity 3000 DBPF TGI's aka cGZResourceKey
  TIxfResourceKey = packed record
    GroupID: Uint32;
    Instance: Uint32;
    ResourceType: Uint32;
  end;
  PIxfResourceKey = ^TIxfResourceKey;

  // aka cGZDBSegmentIndexedFile::RecordInfo
  TIxfRecordInfo = packed record
    Offset: Uint32;
    Length: Uint32;
  end;
  PIxfRecordInfo = ^TIxfRecordInfo;

  TIxfRecord = packed record
    ResKey: TIxfResourceKey;
    RecInfo: TIxfRecordInfo;
  end;
  PIxfRecord = ^TIxfRecord;

  EIxfException = class(Exception);

  { TIxfEntry }

  TIxfEntry = class(TObject)
  private
    function GetGroupID: Uint32;
    function GetHexViewText: String;
    function GetInstance: Uint32;
    function GetIsEmpty: Boolean;
    function GetRawData: Pointer;
    function GetResourceType: Uint32;
    function GetText: String;
    procedure SetGroupID(AValue: Uint32);
    procedure SetInstance(AValue: Uint32);
    procedure SetResourceType(AValue: Uint32);

  protected
    FRecInfo: TIxfRecordInfo;
    FResKey: TIxfResourceKey;
    FKind: TIxfEntryKind;
    FData: Pointer;
    FDataSize: NativeInt;

    // Hideen by default because only needed on TIxfDB.LoadIxfFromStream
    property _RecInfo: TIxfRecordInfo read FRecInfo write FRecInfo;

  public
    constructor Create;
    destructor Destroy; override;

    property ResKey: TIxfResourceKey read FResKey write FResKey;
    property GroupID: Uint32 read GetGroupID write SetGroupID;
    property Instance: Uint32 read GetInstance write SetInstance;
    property ResourceType: Uint32 read GetResourceType write SetResourceType;
    property KindOf: TIxfEntryKind read FKind;
    property RawData: Pointer read GetRawData;
    property RawLength: NativeInt read FDataSize;
    property IsEmpty: Boolean read GetIsEmpty;
    property HexViewText: String read GetHexViewText;
    property Text: String read GetText;

    procedure SetRawData(const Data: Pointer; const DataSize: NativeInt);
    procedure FreeData;

  end;

  { TIxfEntryList }

  TIxfEntryList = specialize TFPGList<TIxfEntry>;

  { TIxfDB }

  TIxfDB = class(TObject)
  private
    function GetCount: Integer;

  protected
    FEntries: TIxfEntryList;

  public
    constructor Create;
    destructor Destroy; override;

    property Entries: TIxfEntryList read FEntries;
    property Count: Integer read GetCount;

    function LoadIxfFromStream(const Stream: TStream): Boolean;
    function LoadIxfFromFile(const FilePath: string): Boolean;
    function AddIxfEntry(const ResKey: TIxfResourceKey): TIxfEntry;
    procedure FreeEntries;

  end;

implementation

type
  // Special TIxfEntry used only this unit for keeping RecordInfo crossref
  TIxfEntryRec = class(TIxfEntry)
  public
    property _RecInfo: TIxfRecordInfo read FRecInfo write FRecInfo;
  end;

{ TIxfEntry }

function TIxfEntry.GetGroupID: Uint32;
begin
  Result := Self.FResKey.GroupID;
end;

function TIxfEntry.GetHexViewText: String;
const
  colSize: Integer = 65; // 3x16 hex + 16 chars + 1 null / CR byte
var
  sbuf: PAnsiChar;
  ch: Byte;
  hexRow, row, col, maxCol, lastRow, index, chIndex: Integer;
  hexVal: AnsiString;
  pb: PByte;
begin
  if Self.IsEmpty then begin
    Result := '';
    Exit;
  end;
  hexRow := Self.FDataSize div 16 + (Integer(Self.FDataSize mod 16 > 0) and 1);
  // Avoid dynamic allocation for each string concat every row
  sbuf := nil;
  GetMem(sbuf, hexRow * colSize);
  try
    pb := Self.FData;
    index := 0;
    chIndex := 0;
    lastRow := hexRow-1;
    for row := 0 to lastRow do begin
      FillChar(sbuf[chIndex], 3 * 16, ' '); // Space padding for hex values
      FillChar(sbuf[chIndex + 3 * 16], 17, 0); // 16 data chars + 1 terminator
      if Self.FDataSize - index > 16 then
        maxCol := 16
      else
        maxCol := Self.FDataSize - index;
      // Left Hex representation
      for col := 0 to maxCol-1 do begin
        hexVal := IntToHex(pb[index+col], 2);
        Move(PAnsiChar(hexVal)^, sbuf[chIndex], 2);
        Inc(chIndex, 3);
      end;
      if maxCol < 16 then
        Inc(chIndex, 3 * (16 - maxCol)); // Skip forwards to data
      // Right data representation
      for col := 0 to maxCol-1 do begin
        ch := pb[index+col];
        // Printables ASCII and ANSI
        if (ch >= 32) and (ch <= 126) then
          sbuf[chIndex] := Chr(ch)
        else
          sbuf[chIndex] := '.'; // Not printable, fallback to dot
        Inc(chIndex);
      end;
      // Not the end, give it as new line
      if row < lastRow then begin
        sbuf[chIndex] := #13;
        Inc(chIndex);
      end;
      Inc(index, maxCol);
    end;
    // Copy as result
    Result := AnsiString(sbuf);
  finally
    FreeMem(sbuf);
  end;
end;

function TIxfEntry.GetInstance: Uint32;
begin
  Result := Self.FResKey.Instance;
end;

function TIxfEntry.GetIsEmpty: Boolean;
begin
  Result := Self.FData = nil;
end;

function TIxfEntry.GetRawData: Pointer;
begin
  Result := Self.FData;
end;

function TIxfEntry.GetResourceType: Uint32;
begin
  Result := Self.FResKey.ResourceType;
end;

function TIxfEntry.GetText: String;
var
  pTxStr: PAnsiChar;
begin
  if Self.IsEmpty then begin
    Result := '';
    Exit;
  end;
  pTxStr := Self.FData + SizeOf(Uint32);
  Result := pTxStr;
end;

procedure TIxfEntry.SetGroupID(AValue: Uint32);
begin
  Self.FResKey.GroupID := AValue;
end;

procedure TIxfEntry.SetInstance(AValue: Uint32);
begin
  Self.FResKey.Instance := AValue;
end;

procedure TIxfEntry.SetResourceType(AValue: Uint32);
begin
  Self.FResKey.ResourceType := AValue;
end;

constructor TIxfEntry.Create;
begin
  inherited Create;
  //FillChar(Self.FRecord, SizeOf(TIxfRecord), 0);
  Self.FResKey := Default(TIxfResourceKey);
  Self.FData := nil;
  Self.FDataSize := 0;
end;

destructor TIxfEntry.Destroy;
begin
  Self.FreeData;
  inherited;
end;

procedure TIxfEntry.SetRawData(const Data: Pointer; const DataSize: NativeInt);
var
  newData: Pointer;
  pNull: PByte;
begin
  // Free previous if exists
  Self.FreeData;
  // Set as empty entry
  if (Data = nil) or (DataSize = 0) then begin
    Self.FData := nil;
    Self.FDataSize := 0;
    Exit;
  end;
  // Allocate and do memcpy, +1 is intentional
  newData := nil;
  GetMem(newData, DataSize + 1);
  // Put safe null byte terminator since IXF string hasn't
  pNull := newData + DataSize;
  Move(Data^, newData^, DataSize);
  pNull^ := 0;
  Self.FData := newData;
  Self.FDataSize := DataSize;
end;

procedure TIxfEntry.FreeData;
begin
  if Self.FData <> nil then
    FreeMem(Self.FData);
  Self.FData := nil;
  Self.FDataSize := 0;
end;

{ TIxfDB }

function TIxfDB.GetCount: Integer;
begin
  Result := Self.FEntries.Count;
end;

constructor TIxfDB.Create;
begin
  Self.FEntries := TIxfEntryList.Create;
end;

destructor TIxfDB.Destroy;
begin
  Self.FreeEntries;
  Self.FEntries.Free;
  inherited Destroy;
end;

function TIxfDB.LoadIxfFromStream(const Stream: TStream): Boolean;
var
  sig: Uint32;
  rec: TIxfRecord;
  entry: TIxfEntry;
  readRec, readData: NativeInt;
  isEmptyRec, isSkippedRec: Boolean;
  buf, nBuf: Pointer;
  bufSize, dataLen, diff: LongInt;
  i: Integer;
  pStrLenCheck: PUint32;
begin
  sig := 0;
  Stream.Read(sig, SizeOf(Uint32));
  if sig <> IXF_HEADER_SIGNATURE then begin
    Result := false;
    raise EIxfException.Create('Invalid IXF file signature');
    Exit;
  end;
  Self.FreeEntries;
  // Assume buffer is uninitialized
  bufSize := 0;
  // 1st pass for reading header entries
  while true do begin
    //FillChar(rec, SizeOf(TIxfRecord), 0);
    rec := Default(TIxfRecord);
    // Read and check if actually we did?
    readRec := Stream.Read(rec, SizeOf(TIxfRecord));
    if readRec < SizeOf(TIxfRecord) then
      break;
    with rec.ResKey do
      with rec.RecInfo do
        isEmptyRec := (GroupID = 0) and (Instance = 0) and (ResourceType = 0)
          and (Offset = 0) and (Length = 0);
    // End of entries
    if isEmptyRec then
      break;
    // There's also seems like deleted entry that marked by all $FFFFFFFF
    // Such as found at German language of Frankfurfest.IXF
    with rec.ResKey do
      with rec.RecInfo do
        isSkippedRec := (GroupID = $FFFFFFFF) and (Instance = $FFFFFFFF) and
          (ResourceType = $FFFFFFFF) and (Offset = $FFFFFFFF) and
          (Length = $FFFFFFFF);
    if isSkippedRec then
      continue;
    // Set the biggest buffer length you'll need
    if rec.RecInfo.Length > bufSize then
      // Accomodate string length bug below
      bufSize := rec.RecInfo.Length + SizeOf(Uint32);
    // Add to entry
    entry := Self.AddIxfEntry(rec.ResKey);
    TIxfEntryRec(entry)._RecInfo := rec.RecInfo;
  end;
  // 2nd pass to actually read entries data
  buf := nil;
  GetMem(buf, bufSize);
  try
    i := 0;
    pStrLenCheck := buf; // For checking text length
    for entry in Self.FEntries do begin
      pStrLenCheck^ := 0;
      with TIxfEntryRec(entry)._RecInfo do begin
        // Read data of current record
        Stream.Position := Offset;
        dataLen := Length;
        readData := Stream.Read(buf^, dataLen);
        if readData <> dataLen then begin
          Result := False;
          raise EIxfException.Create('Entry data read mismatch');
          Exit
        end;
      end;
      // Bugged text (Type $2026960B) which sometimes has wrong length
      // For no reason, some language IXF file has set length = length of string
      // In reality, text type has Pascal style string which has 4 bytes header
      // which causes last 4-bytes of text to be truncated.
      if pStrLenCheck^ = dataLen then begin
        // Not last entry
        if i+1 < Self.Count then
          diff := TIxfEntryRec(Self.FEntries[i+1])._RecInfo.Offset -
            TIxfEntryRec(entry)._RecInfo.Offset
        // Last entry
        else
          diff := Stream.Size - TIxfEntryRec(entry)._RecInfo.Offset;
        if diff > dataLen then begin
          nBuf := buf + dataLen;
          readData := Stream.Read(nBuf^, SizeOf(UInt32));
          if readData <> SizeOf(UInt32) then begin
            Result := False;
            Exit
          end;
          dataLen := dataLen + SizeOf(UInt32);
        end;
      end;
      // Add data
      entry.SetRawData(buf, dataLen);
      // We don't need record info anymore
      TIxfEntryRec(entry)._RecInfo := Default(TIxfRecordInfo);
      Inc(i);
    end;
  finally
    FreeMem(buf);
  end;
  Result := true;
end;

function TIxfDB.LoadIxfFromFile(const FilePath: string): Boolean;
var
  fs: TFileStream;
begin
  Result := False;
  fs := TFileStream.Create(FilePath, fmOpenRead);
  try
    fs.Position := 0;
    Result := Self.LoadIxfFromStream(fs);
  finally
    fs.Free;
  end;
end;

function TIxfDB.AddIxfEntry(const ResKey: TIxfResourceKey): TIxfEntry;
var
  ixf: TIxfEntry;
begin
  //ixf := TIxfEntry.Create;
  ixf := TIxfEntryRec.Create; // We need store RecInfo temporarily
  ixf.ResKey := ResKey;
  Self.FEntries.Add(ixf);
  Result := ixf;
end;

procedure TIxfDB.FreeEntries;
var
  entry: TIxfEntry;
begin
  for entry in Self.FEntries do
    TIxfEntryRec(entry).Free;
  Self.FEntries.Clear;
end;

end.

