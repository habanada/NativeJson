{
  SPDX-FileCopyrightText: 2026 Selahattin Erkoc
  SPDX-License-Identifier: MIT

  This file is part of NativeJson.
  See LICENSE and THIRD-PARTY-NOTICES.md in the repository root.
}
program Demo13_EdgeCases;

{$I NativeJson.inc}

// DEMO 13 - HARDENING: probe for known and suspected weak spots
//
//   This is the only demo that is meant to be red.
//   Every failed line is an item on the hardening list,
//   not a regression. It asks the questions that cannot be answered
//   from the source code alone - the compiler and the runtime
//   answer them.
//
//   When an item is fixed, the line turns green and stays as a
//   regression test.

{$APPTYPE CONSOLE}

uses
  SysUtils,
  NativeJson.Compat,
  Classes,
  Rtti,
  TypInfo,
  Demo.Assert in 'Demo.Assert.pas',
  NativeJson.Main,
  NativeJson.Attributes,
  NativeJson.Dom.Value,
  NativeJson.Serializer.Writer;

type
  TNumbers = class
  private
    FLarge: UInt64;
    FSmall: Byte;
    FMedium: SmallInt;
    FUnsigned: Cardinal;
    FLong: Int64;
    FSimple: Single;
    FExact: Double;
  public
    property Large: UInt64 read FLarge write FLarge;
    property Small: Byte read FSmall write FSmall;
    property Medium: SmallInt read FMedium write FMedium;
    property Unsigned: Cardinal read FUnsigned write FUnsigned;
    property Long: Int64 read FLong write FLong;
    property Simple: Single read FSimple write FSimple;
    property Exact: Double read FExact write FExact;
  end;

  TPermission = (rtRead, rtWrite, rtExecute);
  TPermissions = set of TPermission;

  TWithSet = class
  private
    FPermissions: TPermissions;
  public
    property Permissions: TPermissions read FPermissions write FPermissions;
  end;

  IAnimal = interface
    ['{7B3A1C42-9E55-4B0D-9C61-2F8D4A6E1B30}']
    function CallIt: string;
  end;

  TDog = class(TInterfacedObject, IAnimal)
  private
    FName: string;
  public
    constructor Create(const AName: string);
    function CallIt: string;
    property Name: string read FName write FName;
  end;

  TWithInterface = class
  private
    FAnimal: IAnimal;
  public
    property Animal: IAnimal read FAnimal write FAnimal;
  end;

  TTexts = class
  private
    FShort: ShortString;
    FAnsi: AnsiString;
    FWide: WideString;
    FChars: Char;
  public
    property Short: ShortString read FShort write FShort;
    property Ansi: AnsiString read FAnsi write FAnsi;
    property Wide: WideString read FWide write FWide;
    property Chars: Char read FChars write FChars;
  end;

  // Not a TStream descendant, but with both methods - exactly the case
  // that duck typing is supposed to detect.
  TDrawing = class
  private
    FData: TBytes;
  public
    procedure SaveToStream(Strm: TStream);
    procedure LoadFromStream(Strm: TStream);
    property Data: TBytes read FData write FData;
  end;

  TFolder = class
  private
    FTitle: string;
    FImage: TDrawing;
  public
    constructor Create;
    destructor Destroy; override;
    property Title: string read FTitle write FTitle;
    property Image: TDrawing read FImage;
  end;

procedure TDrawing.SaveToStream(Strm: TStream);
begin
  if Length(FData) > 0 then Strm.WriteBuffer(FData[0], Length(FData));
end;

procedure TDrawing.LoadFromStream(Strm: TStream);
begin
  SetLength(FData, Strm.Size - Strm.Position);
  if Length(FData) > 0 then Strm.ReadBuffer(FData[0], Length(FData));
end;

constructor TFolder.Create;
begin
  inherited Create;
  FImage := TDrawing.Create;
end;

destructor TFolder.Destroy;
begin
  FImage.Free;
  inherited;
end;

constructor TDog.Create(const AName: string);
begin
  inherited Create;
  FName := AName;
end;

function TDog.CallIt: string;
begin
  Result := 'Woof';
end;

// ---------------------------------------------------------------------------

procedure CheckBehavior(const Name, Expected: string; Determine: TFunc<string>);
var
  ActualValue: string;
begin
  try
    ActualValue := Determine();
  except
    on E: Exception do
    begin
      // The plain text goes to the output, the comparison value stays short -
      // otherwise the check depends on the wording of the message.
      Writeln('       (', E.ClassName, ': ', E.Message, ')');
      ActualValue := 'EXCEPTION';
    end;
  end;
  Check(Name, Expected, ActualValue);
end;

function YesNo(Condition: Boolean): string;
begin
  if Condition then Result := 'yes' else Result := 'no';
end;

// ---------------------------------------------------------------------------

procedure Step1_UInt64;
var
  Z: TNumbers;
  Json: string;
begin
  Section('1. UInt64 above High(Int64)');
  Z := TNumbers.Create;
  try
    Z.Large := High(UInt64);
    Json := JsonConvert.SerializeObject(Z);
    Show('JSON', Json);
    Writeln('       High(UInt64) is 18446744073709551615.');
    Writeln('       But for tkInt64 the serializer uses Value.AsInt64 -');
    Writeln('       the same bits read as signed give -1.');

    CheckContains('Largest UInt64 is written correctly',
      '"Large":18446744073709551615', Json);

    CheckBehavior('Largest UInt64 comes back', 'yes',
      function: string
      var
        K: TNumbers;
      begin
        K := JsonConvert.DeserializeObject<TNumbers>(Json);
        try
          Result := YesNo(K.Large = High(UInt64));
        finally
          K.Free;
        end;
      end);
  finally
    Z.Free;
  end;
end;

procedure Step2_RangeCheckOnRead;
begin
  Section('2. Numbers too large for the target type');
  Writeln('       A clear message is expected each time. Silent');
  Writeln('       truncation would be the worst of all answers.');

  CheckBehavior('999 into a Byte is rejected', 'EXCEPTION',
    function: string
    var
      Z: TNumbers;
    begin
      Z := JsonConvert.DeserializeObject<TNumbers>('{"Small":999}');
      try
        Result := 'let through as ' + IntToStr(Z.Small);
      finally
        Z.Free;
      end;
    end);

  CheckBehavior('70000 into a SmallInt is rejected', 'EXCEPTION',
    function: string
    var
      Z: TNumbers;
    begin
      Z := JsonConvert.DeserializeObject<TNumbers>('{"Medium":70000}');
      try
        Result := 'let through as ' + IntToStr(Z.Medium);
      finally
        Z.Free;
      end;
    end);

  CheckBehavior('-1 into a Cardinal is rejected', 'EXCEPTION',
    function: string
    var
      Z: TNumbers;
    begin
      Z := JsonConvert.DeserializeObject<TNumbers>('{"Unsigned":-1}');
      try
        Result := 'let through as ' + UIntToStr(Z.Unsigned);
      finally
        Z.Free;
      end;
    end);
end;

procedure Step3_NumberLargerThanInt64;
begin
  Section('3. A JSON number that fits no integer type');
  CheckBehavior('Overlong number is reported', 'EXCEPTION',
    function: string
    var
      Z: TNumbers;
    begin
      Z := JsonConvert.DeserializeObject<TNumbers>('{"Long":99999999999999999999}');
      try
        Result := 'let through as ' + IntToStr(Z.Long);
      finally
        Z.Free;
      end;
    end);

  CheckBehavior('Int64 limits round-trip', 'yes',
    function: string
    var
      Z, K: TNumbers;
      Json: string;
    begin
      Z := TNumbers.Create;
      try
        Z.Long := High(Int64);
        Json := JsonConvert.SerializeObject(Z);
      finally
        Z.Free;
      end;
      K := JsonConvert.DeserializeObject<TNumbers>(Json);
      try
        Result := YesNo(K.Long = High(Int64));
      finally
        K.Free;
      end;
    end);
end;

procedure Step4_Sets;
var
  M: TWithSet;
  Json: string;
begin
  Section('4. Sets (set of) there and back');
  M := TWithSet.Create;
  try
    M.Permissions := [rtRead, rtExecute];
    Json := JsonConvert.SerializeObject(M);
    Show('JSON today', Json);

    CheckContains('Set is written as a JSON array',
      '"Permissions":["rtRead","rtExecute"]', Json);

    CheckBehavior('Set comes back', 'yes',
      function: string
      var
        K: TWithSet;
      begin
        K := JsonConvert.DeserializeObject<TWithSet>(Json);
        try
          Result := YesNo(K.Permissions = [rtRead, rtExecute]);
        finally
          K.Free;
        end;
      end);

    CheckBehavior('Empty set comes back', 'yes',
      function: string
      var
        K: TWithSet;
      begin
        K := JsonConvert.DeserializeObject<TWithSet>('{"Permissions":[]}');
        try
          Result := YesNo(K.Permissions = []);
        finally
          K.Free;
        end;
      end);
  finally
    M.Free;
  end;
end;

procedure Step5_Interfaces;
var
  Holder: TWithInterface;
  Json: string;
begin
  Section('5. An interface as a member');
  Holder := TWithInterface.Create;
  try
    Holder.Animal := TDog.Create('Bello');
    Json := JsonConvert.SerializeObject(Holder);
    Show('JSON today', Json);
    Writeln('       For tkInterface the serializer writes Value.ToString.');
    Writeln('       Expected would be the members of the object behind it.');

    CheckContains('The implementing object is written', '"Name":"Bello"', Json);
    // TInterfacedObject brings RefCount as a public property.
    // That is bookkeeping, not payload.
    CheckNotContains('RefCount does not end up in the JSON', 'RefCount', Json);

    // Nobody can derive TDog from IAnimal alone - that is what the factory is for.
    CheckBehavior('An interface can be read with a factory', 'yes',
      function: string
      var
        K: TWithInterface;
      begin
        K := JsonConvert.DeserializeObject<TWithInterface>('{"Animal":{"Name":"Bello"}}',
          procedure(S: TJsonSettings)
          begin
            S.RegisterFactory<IAnimal>(
              function(RType: TRttiType): TObject
              begin
                Result := TDog.Create('');
              end);
          end);
        try
          Result := YesNo((K.Animal <> nil) and (K.Animal.CallIt = 'Woof'));
        finally
          K.Free;
        end;
      end);

    CheckBehavior('Without a factory an explanatory message comes', 'EXCEPTION',
      function: string
      var
        K: TWithInterface;
      begin
        K := JsonConvert.DeserializeObject<TWithInterface>('{"Animal":{"Name":"Bello"}}');
        try
          Result := 'let through';
        finally
          K.Free;
        end;
      end);
  finally
    Holder.Free;
  end;
end;

procedure Step6_LegacyStringTypes;
var
  T, K: TTexts;
  Json: string;
begin
  Section('6. ShortString, AnsiString, WideString, Char');
  T := TTexts.Create;
  try
    T.Short := 'short';
    T.Ansi := 'ansi';
    T.Wide := 'wide';
    T.Chars := 'X';

    Json := JsonConvert.SerializeObject(T);
    Show('JSON', Json);

    CheckBehavior('All four come back', 'yes',
      function: string
      begin
        K := JsonConvert.DeserializeObject<TTexts>(Json);
        try
          Result := YesNo((string(K.Short) = 'short') and (string(K.Ansi) = 'ansi') and
                           (string(K.Wide) = 'wide') and (K.Chars = 'X'));
        finally
          K.Free;
        end;
      end);
  finally
    T.Free;
  end;
end;

procedure Step7_Single;
var
  Z, K: TNumbers;
  Json: string;
  A, B: Double;
begin
  Section('7. Single goes through Extended');
  Z := TNumbers.Create;
  try
    Z.Simple := 0.1;
    // A Double that does NOT come back exactly with 15 digits.
    // Writing 0.1 + 0.2 directly does not help - the
    // compiler evaluates constants as Extended and folds that into a clean
    // 0.3. Only the addition of TWO DOUBLE VARIABLES at runtime
    // produces 0.30000000000000004.
    A := 0.1;
    B := 0.2;
    Z.Exact := A + B;
    Json := JsonConvert.SerializeObject(Z);
    Show('JSON', Json);
    Writeln('       A Single has about 7 digits. If it is written via Extended,');
    Writeln('       digits appear that it never had.');

    CheckContains('Single is written readably', '"Simple":0.1,', Json);
    CheckContains('Double shows all needed digits',
      '"Exact":0.30000000000000004', Json);

    CheckBehavior('Double comes back bit-exact', 'yes',
      function: string
      begin
        K := JsonConvert.DeserializeObject<TNumbers>(Json);
        try
          Result := YesNo(K.Exact = Z.Exact);
        finally
          K.Free;
        end;
      end);

    CheckBehavior('Single comes back unchanged', 'yes',
      function: string
      begin
        K := JsonConvert.DeserializeObject<TNumbers>(Json);
        try
          Result := YesNo(K.Simple = Z.Simple);
        finally
          K.Free;
        end;
      end);
  finally
    Z.Free;
  end;
end;

procedure Step8_StrictTypes;
begin
  Section('8. StrictTypes: string instead of number');

  // The default is lenient - EDI partners like to send amounts as text.
  CheckBehavior('Without StrictTypes text is read as a number', '42',
    function: string
    var
      Z: TNumbers;
    begin
      Z := JsonConvert.DeserializeObject<TNumbers>('{"Small":"42"}');
      try
        Result := IntToStr(Z.Small);
      finally
        Z.Free;
      end;
    end);

  CheckBehavior('With StrictTypes the same text is rejected', 'EXCEPTION',
    function: string
    var
      Z: TNumbers;
    begin
      Z := JsonConvert.DeserializeObject<TNumbers>('{"Small":"42"}',
        procedure(S: TJsonSettings)
        begin
          S.StrictTypes := True;
        end);
      try
        Result := IntToStr(Z.Small);
      finally
        Z.Free;
      end;
    end);
end;

procedure Step9_Streamable;
var
  M: TFolder;
  Json: string;
begin
  Section('9. Classes with LoadFromStream and SaveToStream');
  M := TFolder.Create;
  try
    M.Title := 'Plan A';
    M.Image.Data := TEncoding.UTF8.GetBytes('Hello');
    Json := JsonConvert.SerializeObject(M);
    Show('JSON', Json);
    Writeln('       TDrawing does NOT descend from TStream, but has both');
    Writeln('       methods - that should come out as Base64.');

    CheckContains('Written as Base64', '"Image":"SGVsbG8="', Json);

    CheckBehavior('Comes back byte by byte', 'yes',
      function: string
      var
        K: TFolder;
      begin
        K := JsonConvert.DeserializeObject<TFolder>(Json);
        try
          Result := YesNo((K.Title = 'Plan A') and
            (TEncoding.UTF8.GetString(K.Image.Data) = 'Hello'));
        finally
          K.Free;
        end;
      end);
  finally
    M.Free;
  end;
end;

// ---------------------------------------------------------------------------

begin
  try
    Title('DEMO 13 - HARDENING: PROBE');
    Writeln;
    Writeln('  This demo may be red. Every red line is an open');
    Writeln('  item on the hardening list, not a regression.');

    Step1_UInt64;
    Step2_RangeCheckOnRead;
    Step3_NumberLargerThanInt64;
    Step4_Sets;
    Step5_Interfaces;
    Step6_LegacyStringTypes;
    Step7_Single;
    Step8_StrictTypes;
    Step9_Streamable;

    Writeln;
    Writeln('  Red lines above are the work list. Green lines are');
    Writeln('  regression tests from now on.');
    Summary;
    // Deliberately always 0: this demo reports findings, not a failure.
    ExitCode := 0;
  except
    on E: Exception do
    begin
      Writeln('ABORTED: ', E.ClassName, ': ', E.Message);
      ExitCode := 2;
    end;
  end;
  if ParamCount = 0 then
  begin
    Writeln;
    Writeln('Press Enter ...');
    Readln;
  end;
end.
