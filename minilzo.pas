unit minilzo;

//
// Pascal port implementation of MiniLZO LZO1X-1 v2.10
//
// Copyright (C) 2025 Thiekus
// Copyright (C) 1996-2017 Markus Franz Xaver Johannes Oberhumer
// All Rights Reserved.
//
// The LZO library is free software; you can redistribute it and/or
// modify it under the terms of the GNU General Public License as
// published by the Free Software Foundation; either version 2 of
// the License, or (at your option) any later version.
//
// The LZO library is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with the LZO library; see the file COPYING.
// If not, write to the Free Software Foundation, Inc.,
// 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301, USA.
//
// Markus F.X.J. Oberhumer
// <markus@oberhumer.com>
// http://www.oberhumer.com/opensource/lzo/
//
// Pascal port by Thiekus (https://thiekus.com/)
//

{$mode ObjFPC}{$H+}

interface

// Pure Pascal implementation port from minilzo.c
// It's not the most optimized, but at least work and less hassle as you didn't
// require externally compile minilzo.c using GCC and link that per platform.
{$DEFINE MINILZO_PURE_PASCAL}

const
  LZO_E_OK                  =  0;
  LZO_E_ERROR               = -1;
  LZO_E_OUT_OF_MEMORY       = -2;    // [lzo_alloc_func_t failure]
  LZO_E_NOT_COMPRESSIBLE    = -3;    // [not used right now]
  LZO_E_INPUT_OVERRUN       = -4;
  LZO_E_OUTPUT_OVERRUN      = -5;
  LZO_E_LOOKBEHIND_OVERRUN  = -6;
  LZO_E_EOF_NOT_FOUND       = -7;
  LZO_E_INPUT_NOT_CONSUMED  = -8;
  LZO_E_NOT_YET_IMPLEMENTED = -9;    // [not used right now]
  LZO_E_INVALID_ARGUMENT    = -10;
  LZO_E_INVALID_ALIGNMENT   = -11;   // pointer argument is not properly aligned
  LZO_E_OUTPUT_NOT_CONSUMED = -12;
  LZO_E_INTERNAL_ERROR      = -99;

  {$IFDEF MINILZO_PURE_PASCAL}

  function lzo1x_1_compress(const src: PByte; src_len: LongWord; dst: PByte;
    dst_len: PLongWord; wrkmem: Pointer): Integer;

  function lzo1x_decompress(const src: PByte; src_len: LongWord; dst: PByte;
    dst_len: PLongWord; wrkmem: Pointer): Integer;

  {$ELSE}

  function lzo1x_1_compress(const src: PByte; src_len: LongWord; dst: PByte;
    dst_len: PLongWord; wrkmem: Pointer): Integer; cdecl;

  function lzo1x_decompress(const src: PByte; src_len: LongWord; dst: PByte;
    dst_len: PLongWord; wrkmem: Pointer): Integer; cdecl;

  function lzo1x_decompress_safe(const src: PByte; src_len: LongWord; dst: PByte;
  dst_len: PLongWord; wrkmem: Pointer): Integer; cdecl;

  {$ENDIF}

implementation

{$IFNDEF MINILZO_PURE_PASCAL} // Use C object compiled from C source

// Download and extract minilzo-2.10.tar.gz from:
// http://www.oberhumer.com/opensource/lzo/
//
// Compile minilzo.c from minilzo directory with:
//
// Default
// gcc -I. -s -Wall -O2 -fomit-frame-pointer -DLZO_CFG_FREESTANDING -c minilzo.c
// Cross compile 64-bit GCC to 32-bit
// gcc -I. -s -Wall -O2 -fomit-frame-pointer -DLZO_CFG_FREESTANDING -m32 -c minilzo.c
//
// Note that LZO_CFG_FREESTANDING is required because it prevents minilzo to
// use C standard lib functions such as memset, memmove, etc.

{$L minilzo/minilzo.o}

// MiniLZO functions
function lzo1x_1_compress(const src: PByte; src_len: LongWord; dst: PByte;
  dst_len: PLongWord; wrkmem: Pointer): Integer; cdecl;
  external name 'lzo1x_1_compress';

function lzo1x_decompress(const src: PByte; src_len: LongWord; dst: PByte;
  dst_len: PLongWord; wrkmem: Pointer): Integer; cdecl;
  external name 'lzo1x_decompress';

function lzo1x_decompress_safe(const src: PByte; src_len: LongWord; dst: PByte;
  dst_len: PLongWord; wrkmem: Pointer): Integer; cdecl;
  external name 'lzo1x_decompress_safe';

{$ELSE} // Pure Pascal implementation begins here

const
  M1_MAX_OFFSET = $0400;
  M2_MAX_OFFSET = $0800;
  M3_MAX_OFFSET = $4000;

// TODO: implements compressor, and more testing for decompressor

procedure UA_COPY4(pOut, pIn: Pointer); inline;
begin
  Move(pIn^, pOut^, 4);
end;

procedure UA_COPY8(pOut, pIn: Pointer); inline;
begin
  Move(pIn^, pOut^, 8);
end;

function do_compress(const src: PByte; src_len: LongWord; dst: PByte;
  dst_len: PLongWord; ti: LongWord; wrkmem: Pointer): LongWord;
var
  ip, op: PByte;
begin
  Result := 0;
end;

function lzo1x_1_compress(const src: PByte; src_len: LongWord; dst: PByte;
  dst_len: PLongWord; wrkmem: Pointer): Integer;
begin
  Result := LZO_E_INTERNAL_ERROR; // Not yet implemented
end;

function lzo1x_decompress(const src: PByte; src_len: LongWord; dst: PByte;
  dst_len: PLongWord; wrkmem: Pointer): Integer;
label
  first_literal_run, match, match_next, copy_match, match_done, eof_found;
var
  op, ip, ip_end, m_pos: PByte;
  t: LongWord;
{$PUSH}{$WARN 5024 OFF} // Disable hints for unused parameter wrkmem
begin
  ip_end := src + src_len;
  dst_len^ := 0;
  op := dst;
  ip := src;

  // NEED_IP(1);
  if (ip^ > 17) then begin
    t := ip^ - 17;
    Inc(ip);

    if t < 4 then
      goto match_next;
    Assert(t > 0);
    // NEED_OP(t);
    // NEED_IP(t+3);
    repeat
      op^ := ip^;
      Inc(op);
      Inc(ip);
      Dec(t);
    until t = 0;
    goto first_literal_run;

  end;

  while True do begin
    // NEED_IP(3);
    t := ip^;
    Inc(ip);
    if t >= 16 then
      goto match;
    if t = 0 then begin
      while ip^ = 0 do begin
        Inc(t, 255);
        Inc(ip);
        // TEST_IV(t);
        // NEED_IP(1);
      end;
      Inc(t, 15 + ip^);
      Inc(ip);
    end;

    Assert(t > 0);
    // NEED_OP(t+3);
    // NEED_IP(t+6);
    t := t + 3;
    if t >= 8 then begin
      repeat
        UA_COPY8(op, ip);
        Inc(op, 8);
        Inc(ip, 8);
        Dec(t, 8);
      until t < 8;
    end;

    if t >= 4 then begin
      UA_COPY4(op, ip);
      Inc(op, 4);
      Inc(ip, 4);
      Dec(t, 4);
    end;

    if t > 0 then begin
      op^ := ip^;
      Inc(op);
      Inc(ip);
      if t > 1 then begin
        op^ := ip^;
        Inc(op);
        Inc(ip);
        if t > 2 then begin
          op^ := ip^;
          Inc(op);
          Inc(ip);
        end;
      end;
    end;

    first_literal_run:

    t := ip^;
    Inc(ip);
    if t >= 16 then
      goto match;

    m_pos := op - (1 + M2_MAX_OFFSET);
    Dec(m_pos, t shr 2);
    Dec(m_pos, ip^ shl 2);
    Inc(ip);

    // TEST_LB(m_pos);
    // NEED_OP(3);
    op^ := m_pos^;
    Inc(op);
    Inc(m_pos);
    op^ := m_pos^;
    Inc(op);
    Inc(m_pos);
    op^ := m_pos^;
    Inc(op);
    Inc(m_pos);
    goto match_done;

    while True do begin

      match:

      if t >= 64 then begin
        m_pos := op - 1;
        Dec(m_pos, (t shr 2) and 7);
        Dec(m_pos, ip^ shl 3);
        Inc(ip);
        t := (t shr 5) - 1;
        // TEST_LB(m_pos);
        Assert(t > 0);
        // NEED_OP(t+3-1);
        goto copy_match;
      end
      else if t >= 32 then begin
        t := t and 31;
        if t = 0 then begin
          while ip^ = 0 do begin
            Inc(t, 255);
            Inc(ip);
            // TEST_OV(t);
            // NEED_IP(1);
          end;
          Inc(t, 31 + ip^);
          Inc(ip);
          // NEED_IP(2);
        end;
        {$IFDEF ENDIAN_LITTLE}
        m_pos := op - 1;
        Dec(m_pos, PWord(ip)^ shr 2);
        {$ELSE}
        m_pos := op - 1;
        Dec(m_pos, (ip[0] shr 2) + (ip[1] shl 6));
        {$ENDIF}
        ip := ip + 2;
      end
      else if t >= 16 then begin
        m_pos := op;
        Dec(m_pos, (t and 8) shl 11);
        t := t and 7;
        if t = 0 then begin
          while ip^ = 0 do begin
            Inc(t, 255);
            Inc(ip);
            // TEST_OV(t);
            // NEED_IP(1);
          end;
          Inc(t, 7 + ip^);
          Inc(ip);
          // NEED_IP(2);
        end;
        {$IFDEF ENDIAN_LITTLE}
        Dec(m_pos, PWord(ip)^ shr 2);
        {$ELSE}
        Dec(m_pos, (ip[0] shr 2) + (ip[1] shl 6));
        {$ENDIF}
        ip := ip + 2;
        if m_pos = op then
          goto eof_found;
        m_pos := m_pos - $4000;
      end
      else begin
        m_pos := op - 1;
        Dec(m_pos, t shr 2);
        Dec(m_pos, ip^ shl 2);
        Inc(ip);
        // TEST_LB(m_pos);
        // NEED_OP(2);
        op^ := m_pos^;
        Inc(op);
        Inc(m_pos);
        op^ := m_pos^;
        Inc(op);
        goto match_done;
      end;

      if (op - m_pos) >= 8 then begin
        Inc(t, 3 - 1);
        if t >= 8 then begin
          repeat
            UA_COPY8(op, m_pos);
            Inc(op, 8);
            Inc(m_pos, 8);
            Dec(t, 8);
          until t < 8;
        end;
        if t >= 4 then begin
          UA_COPY4(op, m_pos);
          Inc(op, 4);
          Inc(m_pos, 4);
          Dec(t, 4);
        end;
        if t > 0 then begin
          op^ := m_pos[0];
          Inc(op);
          if t > 1 then begin
            op^ := m_pos[1];
            Inc(op);
            if t > 2 then begin
              op^ := m_pos[2];
              Inc(op);
            end;
          end;
        end;
      end
      else begin

        copy_match:

        op^ := m_pos^;
        Inc(op);
        Inc(m_pos);
        op^ := m_pos^;
        Inc(op);
        Inc(m_pos);
        repeat
          op^ := m_pos^;
          Inc(op);
          Inc(m_pos);
          Dec(t);
        until t = 0;

      end;

      match_done:

      t := ip[-2] and 3;
      if t = 0 then
        break;

      match_next:

      Assert(t > 0);
      Assert(t < 4);
      // NEED_OP(t);
      // NEED_IP(t+3);
      op^ := ip^;
      Inc(op);
      Inc(ip);
      if t > 1 then begin
        op^ := ip^;
        Inc(op);
        Inc(ip);
        if t > 2 then begin
          op^ := ip^;
          Inc(op);
          Inc(ip);
        end;
      end;
      t := ip^;
      Inc(ip);

    end;

  end;

  eof_found:

  dst_len^ := op - dst;
  if ip = ip_end then
    Result := LZO_E_OK
  else if ip < ip_end then
    Result := LZO_E_INPUT_NOT_CONSUMED
  else
    Result := LZO_E_INPUT_OVERRUN;

end;
{$POP}

{$ENDIF}

end.

