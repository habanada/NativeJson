{
  SPDX-FileCopyrightText: 2026 Selahattin Erkoc
  SPDX-License-Identifier: MIT

  This file is part of NativeJson.
  See LICENSE and THIRD-PARTY-NOTICES.md in the repository root.
}
program CborInterop;

{$APPTYPE CONSOLE}
{$I NativeJson.inc}

uses
  SysUtils,
  NativeJson.Compat,
  NativeJson.Dom.Value,
  NativeJson.Cbor;

var
  Line, Flags: string;
  Options: TJsonCborOptions;
  Reply, Piece: string;
  Data: TBytes;
  Position: Integer;
  Item: TJsonValue;
begin
  SetTextCodePage(Output, 65001);
  SetTextCodePage(Input, 65001);
  Options := TJsonCborOptions.Create;
  try
    ReadLn(Flags);
    if Pos('int', Flags) > 0 then Options.KeyMode := ckmInteger;
    if Pos('wrap', Flags) > 0 then
    begin
      Options.BytesMode := cbmWrapped;
      Options.TagMode := ctmWrap;
    end;
    if Pos('det', Flags) > 0 then Options.Deterministic := True;
    if Pos('len', Flags) > 0 then Options.KeyOrder := ckoLengthFirst;
    if Pos('nodec', Flags) > 0 then Options.ExactDecimals := False;
    while not Eof do
    begin
      ReadLn(Line);
      if Line = '' then Continue;
      try
        if Line[1] = 'S' then
        begin
          Data := CborFromHex(Copy(Line, 3, MaxInt));
          Position := 0;
          Reply := 'OK [';
          while Position < Length(Data) do
          begin
            Item := CborToDomAt(Data, Position, Options);
            try
              Piece := Item.ToJson;
            finally
              Item.Free;
            end;
            if Reply <> 'OK [' then Reply := Reply + ',';
            Reply := Reply + Piece;
          end;
          Reply := Reply + ']';
        end
        else if Line[1] = 'D' then Reply := 'OK ' + CborToJson(CborFromHex(Copy(Line, 3, MaxInt)), Options)
        else Reply := 'OK ' + CborToHex(JsonToCbor(Copy(Line, 3, MaxInt), Options));
      except
        on E: Exception do Reply := 'ERR ' + E.ClassName + ': ' + E.Message;
      end;
      WriteLn(Reply);
      Flush(Output);
    end;
  finally
    Options.Free;
  end;
end.
