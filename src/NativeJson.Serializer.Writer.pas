{
  SPDX-FileCopyrightText: 2026 Selahattin Erkoc
  SPDX-License-Identifier: MIT

  This file is part of NativeJson.
  See LICENSE and THIRD-PARTY-NOTICES.md in the repository root.
}
unit NativeJson.Serializer.Writer;

interface

{$I NativeJson.inc}

{$SCOPEDENUMS ON}

uses
  {$IFDEF FPC}
  SysUtils,
  Classes,
  streamex,
  Math,
  {$ELSE}
  System.SysUtils,
  System.Classes,
  System.Math,
  {$ENDIF}
  NativeJson.Compat,
  NativeJson.FloatText;

type
  EJsonWriterError = class(Exception);
  TJsonFormatting = (None, Indented);
  TJsonEnumHandling = (ByName, ByInteger);
  TJsonPreserveReferences = (None, Objects);
  TJsonTypeNameHandling = (None, Objects, Auto);
  TJsonWriteState = (Start, PropName, ObjectStart, ObjectValue, ArrayStart, ArrayValue, Closed, Error);

  TJsonByteOutput = class
  private
    FStream: TStream;
    FBuffer: TBytes;
    FIndex: Integer;
    FCapacity: Integer;
    FMaxChars: Integer;
  public
    constructor Create(AStream: TStream; BufferSize: Integer = 256 * 1024);
    destructor Destroy; override;
    procedure FlushBuffer;
    procedure Put(const S: string); overload;
    procedure Put(C: Char); overload;
  end;

  TJsonTextOutput = class
  private
    FBuffer: TArray<Char>;
    FLength: Integer;
    procedure Reserve(NumItems: Integer);
  public
    constructor Create;
    procedure Put(const S: string); overload;
    procedure Put(C: Char); overload;
    function AsText: string;
  end;

  TJsonWriter = class
  private
    FWriter: TTextWriter;
    FStream: TJsonByteOutput;
    FText: TJsonTextOutput;
    FFormatting: TJsonFormatting;
    FEnumHandling: TJsonEnumHandling;
    FPreserveReferences: TJsonPreserveReferences;
    FTypeNameHandling: TJsonTypeNameHandling;
    FWrapBytes: Boolean;
    FIndentChar: Char;
    FIndentCharCount: Integer;
    FQuoteChar: Char;
    FStateStack: TArray<TJsonWriteState>;
    FStateStackTop: Integer;
    FCurrentState: TJsonWriteState;
    procedure ResetState;
    procedure Emit(const S: string); overload;
    procedure Emit(C: Char); overload;
    procedure EmitLineBreak;
    procedure PushState(State: TJsonWriteState);
    procedure PopState;
    procedure ReplaceState(State: TJsonWriteState);
    procedure WriteIndent;
    procedure WriteStatePreamble;
    procedure WriteEscapedString(const S: string);
    procedure CompleteValue;
  public
    constructor Create; overload;
    constructor Create(Stream: TStream); overload;
    constructor Create(Writer: TTextWriter); overload;
    destructor Destroy; override;
    procedure WriteStartObject;
    procedure WriteEndObject;
    procedure WriteStartArray;
    procedure WriteEndArray;
    procedure WritePropertyName(const Name: string);
    procedure WriteValue(const Value: string); overload;
    procedure WriteValue(Value: Integer); overload;
    procedure WriteValue(Value: Int64); overload;
    procedure WriteValue(Value: Double); overload;
    procedure WriteValue(Value: Boolean); overload;
    procedure WriteNull;
    procedure WriteUndefined;
    procedure WriteRaw(const Json: string);
    procedure Flush;
    property Formatting: TJsonFormatting read FFormatting write FFormatting;
    property WrapBytes: Boolean read FWrapBytes write FWrapBytes;
    property EnumHandling: TJsonEnumHandling read FEnumHandling write FEnumHandling;
    property PreserveReferences: TJsonPreserveReferences read FPreserveReferences write FPreserveReferences;
    property TypeNameHandling: TJsonTypeNameHandling read FTypeNameHandling write FTypeNameHandling;
    property IndentChar: Char read FIndentChar write FIndentChar;
    property IndentCharCount: Integer read FIndentCharCount write FIndentCharCount;
    property QuoteChar: Char read FQuoteChar write FQuoteChar;
    function ToJson: string;
    function ToString: TJsonToStringResult; override;
  end;

function CurrencyToJson(const InputValue: Currency): string;
function SingleToJson(const InputValue: Single): string;
function DoubleToJson(const InputValue: Double): string;

implementation

function CurrencyToJson(const InputValue: Currency): string;
var
  Raw, IntegerPart, FractionPart: Int64;
  Sign, FractionDigits: string;
begin
  // Currency is an Int64 scaled by 10000. Going through Double or
  // Extended loses precision beyond 16 significant digits, and by a
  // different amount on Win32 and Win64. Hence directly from the raw bits.
  Raw := PInt64(@InputValue)^;
  if Raw = Low(Int64) then Exit('-922337203685477.5808');
  if Raw < 0 then
  begin
    Sign := '-';
    Raw := -Raw;
  end
  else
    Sign := '';
  IntegerPart := Raw div 10000;
  FractionPart := Raw mod 10000;
  Result := Sign + IntToStr(IntegerPart);
  if FractionPart <> 0 then
  begin
    FractionDigits := Format('%.4d', [FractionPart]);
    while (Length(FractionDigits) > 1) and (FractionDigits[Length(FractionDigits)] = '0') do
      SetLength(FractionDigits, Length(FractionDigits) - 1);
    Result := Result + '.' + FractionDigits;
  end;
end;

function SingleToJson(const InputValue: Single): string;
var
  RoundTrip: Single;
begin
  // FloatToStr only knows Extended and Currency. So a Single is
  // widened and printed with 15 digits - 0.1 becomes
  // 0.100000001490116, digits the value never had.
  // Seven digits are the documented precision of a Single;
  // where they are not enough, nine are always sufficient.
  // The Double writer checks this, the Single path bypassed it via
  // WriteRaw. FloatToStrF would otherwise output NAN or INF - not JSON numbers.
  if IsNan(InputValue) or IsInfinite(InputValue) then
    raise EJsonWriterError.Create('JSON does not support NaN or Infinity');
  Result := FloatToStrF(InputValue, ffGeneral, 7, 0, TFormatSettings.Invariant);
  if TryStrToFloat(Result, RoundTrip, TFormatSettings.Invariant) and (RoundTrip = InputValue) then Exit;
  Result := FloatToStrF(InputValue, ffGeneral, 9, 0, TFormatSettings.Invariant);
end;

function DoubleToJson(const InputValue: Double): string;
begin
  if IsNan(InputValue) or IsInfinite(InputValue) then
    raise EJsonWriterError.Create('JSON does not support NaN or Infinity');
  Result := JsonDoubleToText(InputValue);
end;

constructor TJsonByteOutput.Create(AStream: TStream; BufferSize: Integer);
begin
  inherited Create;
  if AStream = nil then raise EArgumentNilException.Create('Strom');
  FStream := AStream;
  if BufferSize < 4096 then BufferSize := 4096;
  FCapacity := BufferSize;
  SetLength(FBuffer, FCapacity);
  FIndex := 0;
  FMaxChars := FCapacity div 3;
end;

destructor TJsonByteOutput.Destroy;
begin
  FlushBuffer;
  inherited;
end;

procedure TJsonByteOutput.FlushBuffer;
begin
  if FIndex > 0 then
  begin
    FStream.WriteBuffer(FBuffer[0], FIndex);
    FIndex := 0;
  end;
end;

procedure TJsonByteOutput.Put(C: Char);
begin
  if Ord(C) < $80 then
  begin
    if FIndex >= FCapacity then FlushBuffer;
    FBuffer[FIndex] := Byte(Ord(C));
    Inc(FIndex);
  end
  else
    Put(string(C));
end;

procedure TJsonByteOutput.Put(const S: string);
var
  Von, Rest, Chunk: Integer;
begin
  Rest := Length(S);
  if Rest = 0 then Exit;
  Von := 1;
  while Rest > 0 do
  begin
    Chunk := Rest;
    if Chunk > FMaxChars then
    begin
      Chunk := FMaxChars;
      if (S[Von + Chunk - 1] >= #$D800) and (S[Von + Chunk - 1] <= #$DBFF) then Dec(Chunk);
    end;
    if FIndex + Chunk * 3 > FCapacity then FlushBuffer;
    Inc(FIndex, TEncoding.UTF8.GetBytes(S, Von, Chunk, FBuffer, FIndex));
    Inc(Von, Chunk);
    Dec(Rest, Chunk);
  end;
end;

constructor TJsonTextOutput.Create;
begin
  inherited Create;
  SetLength(FBuffer, 4096);
end;

procedure TJsonTextOutput.Reserve(NumItems: Integer);
var
  Required, Created: Int64;
begin
  Required := Int64(FLength) + NumItems;
  if Required <= Length(FBuffer) then Exit;
  if Required > MaxInt then raise EJsonWriterError.Create('JSON text exceeds the maximum string length');
  Created := Int64(Length(FBuffer)) * 2;
  if Created < Required then Created := Required;
  if Created > MaxInt then Created := MaxInt;
  SetLength(FBuffer, Created);
end;

procedure TJsonTextOutput.Put(const S: string);
var
  Len: Integer;
begin
  Len := Length(S);
  if Len = 0 then Exit;
  Reserve(Len);
  Move(Pointer(S)^, FBuffer[FLength], Len * SizeOf(Char));
  Inc(FLength, Len);
end;

procedure TJsonTextOutput.Put(C: Char);
begin
  if FLength >= Length(FBuffer) then Reserve(1);
  FBuffer[FLength] := C;
  Inc(FLength);
end;

function TJsonTextOutput.AsText: string;
begin
  SetString(Result, PChar(Pointer(FBuffer)), FLength);
end;

constructor TJsonWriter.Create;
begin
  inherited Create;
  FText := TJsonTextOutput.Create;
  ResetState;
end;

constructor TJsonWriter.Create(Stream: TStream);
begin
  if Stream = nil then raise EArgumentNilException.Create('Stream');
  inherited Create;
  FStream := TJsonByteOutput.Create(Stream);
  ResetState;
end;

constructor TJsonWriter.Create(Writer: TTextWriter);
begin
  if Writer = nil then raise EArgumentNilException.Create('Writer');
  inherited Create;
  FWriter := Writer;
  ResetState;
end;

procedure TJsonWriter.ResetState;
begin
  FFormatting := TJsonFormatting.None;
  FEnumHandling := TJsonEnumHandling.ByName;
  FPreserveReferences := TJsonPreserveReferences.None;
  FTypeNameHandling := TJsonTypeNameHandling.None;
  FIndentChar := ' ';
  FIndentCharCount := 2;
  FQuoteChar := '"';
  SetLength(FStateStack, 16);
  FStateStackTop := -1;
  PushState(TJsonWriteState.Start);
end;

destructor TJsonWriter.Destroy;
begin
  FStream.Free;
  FText.Free;
  inherited;
end;

procedure TJsonWriter.Flush;
begin
  if FStream <> nil then FStream.FlushBuffer else if FWriter <> nil then FWriter.Flush;
end;

procedure TJsonWriter.Emit(const S: string);
begin
  if FStream <> nil then FStream.Put(S)
  else if FText <> nil then FText.Put(S)
  else FWriter.Write(S);
end;

procedure TJsonWriter.Emit(C: Char);
begin
  if FStream <> nil then FStream.Put(C)
  else if FText <> nil then FText.Put(C)
  else FWriter.Write({$IFDEF FPC}string(C){$ELSE}C{$ENDIF});
end;

procedure TJsonWriter.EmitLineBreak;
begin
  if FStream <> nil then FStream.Put(sLineBreak)
  else if FText <> nil then FText.Put(sLineBreak)
  else FWriter.WriteLine;
end;

procedure TJsonWriter.PushState(State: TJsonWriteState);
begin
  Inc(FStateStackTop);
  if FStateStackTop >= Length(FStateStack) then SetLength(FStateStack, Length(FStateStack) * 2);
  FStateStack[FStateStackTop] := State;
  FCurrentState := State;
end;

procedure TJsonWriter.PopState;
begin
  if FStateStackTop <= 0 then
  begin
    FStateStackTop := 0;
    FCurrentState := TJsonWriteState.Closed;
    Exit;
  end;
  Dec(FStateStackTop);
  FCurrentState := FStateStack[FStateStackTop];
end;

procedure TJsonWriter.ReplaceState(State: TJsonWriteState);
begin
  FStateStack[FStateStackTop] := State;
  FCurrentState := State;
end;

procedure TJsonWriter.WriteIndent;
var
  I: Integer;
begin
  if FFormatting <> TJsonFormatting.Indented then Exit;
  EmitLineBreak;
  for I := 1 to FStateStackTop * FIndentCharCount do Emit(FIndentChar);
end;

procedure TJsonWriter.WriteStatePreamble;
begin
  case FCurrentState of
    TJsonWriteState.ObjectValue:
      begin
        Emit(',');
        ReplaceState(TJsonWriteState.ObjectStart);
      end;
    TJsonWriteState.ArrayValue: Emit(',');
    TJsonWriteState.PropName:
      if FFormatting = TJsonFormatting.Indented then Emit(': ') else Emit(':');
    TJsonWriteState.Closed: raise EJsonWriterError.Create('Writer is closed');
  end;
end;

procedure TJsonWriter.CompleteValue;
begin
  case FCurrentState of
    TJsonWriteState.PropName: ReplaceState(TJsonWriteState.ObjectValue);
    TJsonWriteState.ArrayStart: ReplaceState(TJsonWriteState.ArrayValue);
    TJsonWriteState.Start: ReplaceState(TJsonWriteState.Closed);
  end;
end;

procedure TJsonWriter.WriteEscapedString(const S: string);
const
  MaxChunk = 16384;
var
  I, RunStart, Len: Integer;
  C: Char;

  procedure FlushRun(UpTo: Integer);
  begin
    if UpTo >= RunStart then Emit(Copy(S, RunStart, UpTo - RunStart + 1));
    RunStart := UpTo + 1;
  end;

begin
  Emit(FQuoteChar);
  Len := Length(S);
  RunStart := 1;
  for I := 1 to Len do
  begin
    C := S[I];
    case C of
      '"', '\', #0..#31:
        begin
          FlushRun(I - 1);
          case C of
            '"': Emit('\"');
            '\': Emit('\\');
            #8: Emit('\b');
            #9: Emit('\t');
            #10: Emit('\n');
            #12: Emit('\f');
            #13: Emit('\r');
          else
            Emit('\u' + IntToHex(Ord(C), 4));
          end;
          RunStart := I + 1;
        end;
    else
      if (I - RunStart + 1 >= MaxChunk) and ((C < #$D800) or (C > #$DBFF)) then FlushRun(I);
    end;
  end;
  FlushRun(Len);
  Emit(FQuoteChar);
end;

procedure TJsonWriter.WriteStartObject;
var
  ParentState: TJsonWriteState;
begin
  ParentState := FCurrentState;
  WriteStatePreamble;
  if FCurrentState in [TJsonWriteState.ArrayStart, TJsonWriteState.ArrayValue] then WriteIndent;
  Emit('{');
  PushState(TJsonWriteState.ObjectStart);
  if ParentState = TJsonWriteState.Start then FStateStack[0] := TJsonWriteState.Closed;
end;

procedure TJsonWriter.WriteEndObject;
var
  HadValues: Boolean;
begin
  if not (FCurrentState in [TJsonWriteState.ObjectStart, TJsonWriteState.ObjectValue]) then raise EJsonWriterError.Create('Mismatching EndObject call');
  HadValues := FCurrentState = TJsonWriteState.ObjectValue;
  PopState;
  if HadValues then WriteIndent;
  Emit('}');
  CompleteValue;
end;

procedure TJsonWriter.WriteStartArray;
var
  ParentState: TJsonWriteState;
begin
  ParentState := FCurrentState;
  WriteStatePreamble;
  if FCurrentState in [TJsonWriteState.ArrayStart, TJsonWriteState.ArrayValue] then WriteIndent;
  Emit('[');
  PushState(TJsonWriteState.ArrayStart);
  if ParentState = TJsonWriteState.Start then FStateStack[0] := TJsonWriteState.Closed;
end;

procedure TJsonWriter.WriteEndArray;
var
  HadValues: Boolean;
begin
  if not (FCurrentState in [TJsonWriteState.ArrayStart, TJsonWriteState.ArrayValue]) then raise EJsonWriterError.Create('Mismatching EndArray call');
  HadValues := FCurrentState = TJsonWriteState.ArrayValue;
  PopState;
  if HadValues then WriteIndent;
  Emit(']');
  CompleteValue;
end;

procedure TJsonWriter.WritePropertyName(const Name: string);
begin
  if FCurrentState = TJsonWriteState.ObjectValue then WriteStatePreamble;
  if FCurrentState <> TJsonWriteState.ObjectStart then raise EJsonWriterError.Create('WritePropertyName called outside object or while a value is pending');
  WriteIndent;
  WriteEscapedString(Name);
  ReplaceState(TJsonWriteState.PropName);
end;

procedure TJsonWriter.WriteValue(const Value: string);
begin
  WriteStatePreamble;
  if FCurrentState in [TJsonWriteState.ArrayStart, TJsonWriteState.ArrayValue] then WriteIndent;
  WriteEscapedString(Value);
  CompleteValue;
end;

procedure TJsonWriter.WriteValue(Value: Integer);
begin
  WriteValue(Int64(Value));
end;

procedure TJsonWriter.WriteValue(Value: Int64);
begin
  WriteStatePreamble;
  if FCurrentState in [TJsonWriteState.ArrayStart, TJsonWriteState.ArrayValue] then WriteIndent;
  Emit(IntToStr(Value));
  CompleteValue;
end;

procedure TJsonWriter.WriteValue(Value: Double);
begin
  if IsNan(Value) or IsInfinite(Value) then raise EJsonWriterError.Create('JSON does not support NaN or Infinity');
  WriteStatePreamble;
  if FCurrentState in [TJsonWriteState.ArrayStart, TJsonWriteState.ArrayValue] then WriteIndent;
  Emit(DoubleToJson(Value));
  CompleteValue;
end;

procedure TJsonWriter.WriteValue(Value: Boolean);
begin
  WriteStatePreamble;
  if FCurrentState in [TJsonWriteState.ArrayStart, TJsonWriteState.ArrayValue] then WriteIndent;
  if Value then Emit('true') else Emit('false');
  CompleteValue;
end;

procedure TJsonWriter.WriteNull;
begin
  WriteStatePreamble;
  if FCurrentState in [TJsonWriteState.ArrayStart, TJsonWriteState.ArrayValue] then WriteIndent;
  Emit('null');
  CompleteValue;
end;

procedure TJsonWriter.WriteUndefined;
begin
  WriteNull;
end;

procedure TJsonWriter.WriteRaw(const Json: string);
begin
  WriteStatePreamble;
  if FCurrentState in [TJsonWriteState.ArrayStart, TJsonWriteState.ArrayValue] then WriteIndent;
  Emit(Json);
  CompleteValue;
end;

function TJsonWriter.ToJson: string;
begin
  if FText <> nil then Result := FText.AsText
  else if FWriter is TStringWriter then Result := TStringWriter(FWriter).ToString
  else Result := '';
end;

function TJsonWriter.ToString: TJsonToStringResult;
begin
  Result := ToJson;
end;

end.
