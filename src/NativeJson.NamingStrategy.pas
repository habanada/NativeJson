{
  SPDX-FileCopyrightText: 2026 Selahattin Erkoc
  SPDX-License-Identifier: MIT

  This file is part of NativeJson.
  See LICENSE and THIRD-PARTY-NOTICES.md in the repository root.
}
unit NativeJson.NamingStrategy;

interface

{$I NativeJson.inc}

uses
  {$IFDEF FPC}
  SysUtils,
  Character,
  StrUtils,
  {$ELSE}
  System.SysUtils,
  System.Character,
  System.StrUtils,
  {$ENDIF}
  NativeJson.Compat;

type
  /// <summary>
  ///   Defines the casing of the JSON properties.
  /// </summary>
  TJsonCaseStyle = (
    jcUnchanged,      // PropertyName -> PropertyName
    jcLower,          // PropertyName -> propertyname
    jcUpper,          // PropertyName -> PROPERTYNAME
    jcPascal,         // propertyName -> PropertyName
    jcCamel,          // PropertyName -> propertyName
    jcSnake,          // PropertyName -> property_name
    jcKebab,          // PropertyName -> property-name
    jcScreamingSnake, // PropertyName -> PROPERTY_NAME
    jcCustom          // Custom strategy (via class)
  );

  /// <summary>
  ///   Base class for naming strategies.
  /// </summary>
  TJsonNamingStrategy = class abstract
  public
    class function ResolvePropertyName(const Name: string): string; virtual; abstract;
  end;

  TJsonNamingStrategyClass = class of TJsonNamingStrategy;

  // ===========================================================================
  // CORE LOGIC
  // ===========================================================================

  TJsonCaseNamingStrategy = class
  public
    class function ApplyCase(const Name: string; Style: TJsonCaseStyle): string;
  end;

  // ===========================================================================
  // CONCRETE STRATEGIES (mapping for the enum)
  // ===========================================================================

  TDefaultNamingStrategy = class(TJsonNamingStrategy)
  public
    class function ResolvePropertyName(const Name: string): string; override;
  end;

  TLowerCaseNamingStrategy = class(TJsonNamingStrategy)
  public
    class function ResolvePropertyName(const Name: string): string; override;
  end;

  TUpperCaseNamingStrategy = class(TJsonNamingStrategy)
  public
    class function ResolvePropertyName(const Name: string): string; override;
  end;

  TPascalCaseNamingStrategy = class(TJsonNamingStrategy)
  public
    class function ResolvePropertyName(const Name: string): string; override;
  end;

  TCamelCaseNamingStrategy = class(TJsonNamingStrategy)
  public
    class function ResolvePropertyName(const Name: string): string; override;
  end;

  TSnakeCaseNamingStrategy = class(TJsonNamingStrategy)
  public
    class function ResolvePropertyName(const Name: string): string; override;
  end;

  TKebabCaseNamingStrategy = class(TJsonNamingStrategy)
  public
    class function ResolvePropertyName(const Name: string): string; override;
  end;

  TScreamingSnakeCaseNamingStrategy = class(TJsonNamingStrategy)
  public
    class function ResolvePropertyName(const Name: string): string; override;
  end;

implementation

{ TJsonCaseNamingStrategy }

class function TJsonCaseNamingStrategy.ApplyCase(const Name: string; Style: TJsonCaseStyle): string;
var
  SB: TJsonStringBuilder;
  I: Integer;
  C: Char;
  IsFirst: Boolean;
begin
  if Name.IsEmpty then Exit('');

  case Style of
    jcUnchanged: Exit(Name);
    jcLower:     Exit(LowerCase(Name));
    jcUpper:     Exit(UpperCase(Name));
    jcPascal:
      begin
        Result := Name;
        if (Length(Result) > 0) and IsLower(Result[1]) then
          Result[1] := ToUpper(Result[1]);
        Exit;
      end;
    jcCamel:
      begin
        Result := Name;
        if (Length(Result) > 0) and Result[1].IsUpper then
          Result[1] := ToLower(Result[1]);
        Exit;
      end;
  end;

  // Complex Transformations (Snake, Kebab, Screaming)
  SB := TJsonStringBuilder.Create(Length(Name) * 2);
  try
    IsFirst := True;
    for I := 1 to Length(Name) do
    begin
      C := Name[I];
      if C.IsUpper then
      begin
        if not IsFirst then
        begin
          if Style in [jcSnake, jcScreamingSnake] then
            SB.Append('_')
          else if Style = jcKebab then
            SB.Append('-');
        end;

        if Style = jcScreamingSnake then
          SB.Append(C)
        else
          SB.Append(ToLower(C));
      end
      else
      begin
        if Style = jcScreamingSnake then
          SB.Append(ToUpper(C))
        else
          SB.Append(C);
      end;
      IsFirst := False;
    end;
    Result := SB.ToString;
  finally
    SB.Free;
  end;
end;

{ Wrapper Classes }

class function TDefaultNamingStrategy.ResolvePropertyName(const Name: string): string;
begin
  Result := Name;
end;

class function TLowerCaseNamingStrategy.ResolvePropertyName(const Name: string): string;
begin
  Result := LowerCase(Name);
end;

class function TUpperCaseNamingStrategy.ResolvePropertyName(const Name: string): string;
begin
  Result := UpperCase(Name);
end;

class function TPascalCaseNamingStrategy.ResolvePropertyName(const Name: string): string;
begin
  Result := TJsonCaseNamingStrategy.ApplyCase(Name, jcPascal);
end;

class function TCamelCaseNamingStrategy.ResolvePropertyName(const Name: string): string;
begin
  Result := TJsonCaseNamingStrategy.ApplyCase(Name, jcCamel);
end;

class function TSnakeCaseNamingStrategy.ResolvePropertyName(const Name: string): string;
begin
  Result := TJsonCaseNamingStrategy.ApplyCase(Name, jcSnake);
end;

class function TKebabCaseNamingStrategy.ResolvePropertyName(const Name: string): string;
begin
  Result := TJsonCaseNamingStrategy.ApplyCase(Name, jcKebab);
end;

class function TScreamingSnakeCaseNamingStrategy.ResolvePropertyName(const Name: string): string;
begin
  Result := TJsonCaseNamingStrategy.ApplyCase(Name, jcScreamingSnake);
end;

end.