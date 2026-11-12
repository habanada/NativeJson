{
  SPDX-FileCopyrightText: 2026 Selahattin Erkoc
  SPDX-License-Identifier: MIT

  This file is part of NativeJson.
  See LICENSE and THIRD-PARTY-NOTICES.md in the repository root.
}
unit NativeJson.Schema.Validation;

interface

{$I NativeJson.inc}

uses
  {$IFDEF FPC}
  SysUtils;
  {$ELSE}
  System.SysUtils;
  {$ENDIF}

type
  TJsonSchemaDialect = (Auto, Draft07, Draft2019_09, Draft2020_12);

  EJsonSchemaException = class(Exception)
  private
    FSchemaPath: string;
    FKeyword: string;
  public
    constructor Create(const ASchemaPath, AKeyword, AMessage: string);
    property SchemaPath: string read FSchemaPath;
    property Keyword: string read FKeyword;
  end;

  TJsonSchemaValidationError = record
  public
    InstancePath: string;
    SchemaPath: string;
    SchemaUri: string;
    Keyword: string;
    Message: string;
    constructor Create(const AInstancePath, ASchemaPath, ASchemaUri, AKeyword, AMessage: string);
    function ToString: string;
  end;

  TJsonSchemaValidationResult = record
  public
    IsValid: Boolean;
    Errors: TArray<TJsonSchemaValidationError>;
    function ErrorCount: Integer;
    function ToString: string;
  end;

  TJsonSchemaValidationOptions = class
  private
    FDialect: TJsonSchemaDialect;
    FBaseUri: string;
    FStopOnFirstError: Boolean;
    FMaxErrors: Integer;
    FMaxDepth: Integer;
    FAssertFormats: Boolean;
    FStrictSchema: Boolean;
  public
    constructor Create;
    function Clone: TJsonSchemaValidationOptions;
    property Dialect: TJsonSchemaDialect read FDialect write FDialect;
    property BaseUri: string read FBaseUri write FBaseUri;
    property StopOnFirstError: Boolean read FStopOnFirstError write FStopOnFirstError;
    property MaxErrors: Integer read FMaxErrors write FMaxErrors;
    property MaxDepth: Integer read FMaxDepth write FMaxDepth;
    property AssertFormats: Boolean read FAssertFormats write FAssertFormats;
    property StrictSchema: Boolean read FStrictSchema write FStrictSchema;
  end;

function JsonPointerEscape(const Value: string): string;
function JsonPointerUnescape(const Value: string): string;

implementation

uses
  {$IFDEF FPC}
  Classes,
  {$ELSE}
  System.Classes,
  {$ENDIF}
  NativeJson.Compat;

constructor EJsonSchemaException.Create(const ASchemaPath, AKeyword, AMessage: string);
begin
  inherited Create(AMessage);
  FSchemaPath := ASchemaPath;
  FKeyword := AKeyword;
end;

constructor TJsonSchemaValidationError.Create(const AInstancePath, ASchemaPath, ASchemaUri, AKeyword, AMessage: string);
begin
  InstancePath := AInstancePath;
  SchemaPath := ASchemaPath;
  SchemaUri := ASchemaUri;
  Keyword := AKeyword;
  Message := AMessage;
end;

function TJsonSchemaValidationError.ToString: string;
begin
  if InstancePath <> '' then Result := InstancePath + ': ' + Message else Result := Message;
  if Keyword <> '' then Result := Result + ' [' + Keyword + ']';
  if SchemaUri <> '' then Result := Result + ' ' + SchemaUri + SchemaPath else if SchemaPath <> '' then Result := Result + ' ' + SchemaPath;
end;

function TJsonSchemaValidationResult.ErrorCount: Integer;
begin
  Result := Length(Errors);
end;

function TJsonSchemaValidationResult.ToString: string;
var
  Builder: TJsonStringBuilder;
  Error: TJsonSchemaValidationError;
begin
  Builder := TJsonStringBuilder.Create;
  try
    for Error in Errors do
    begin
      if Builder.Length > 0 then Builder.AppendLine;
      Builder.Append(Error.ToString);
    end;
    Result := Builder.ToString;
  finally
    Builder.Free;
  end;
end;

constructor TJsonSchemaValidationOptions.Create;
begin
  inherited Create;
  FDialect := TJsonSchemaDialect.Auto;
  FBaseUri := '';
  FStopOnFirstError := False;
  FMaxErrors := 0;
  FMaxDepth := 256;
  FAssertFormats := False;
  FStrictSchema := True;
end;

function TJsonSchemaValidationOptions.Clone: TJsonSchemaValidationOptions;
begin
  Result := TJsonSchemaValidationOptions.Create;
  Result.FDialect := FDialect;
  Result.FBaseUri := FBaseUri;
  Result.FStopOnFirstError := FStopOnFirstError;
  Result.FMaxErrors := FMaxErrors;
  Result.FMaxDepth := FMaxDepth;
  Result.FAssertFormats := FAssertFormats;
  Result.FStrictSchema := FStrictSchema;
end;

function JsonPointerEscape(const Value: string): string;
begin
  Result := StringReplace(Value, '~', '~0', [rfReplaceAll]);
  Result := StringReplace(Result, '/', '~1', [rfReplaceAll]);
end;

function JsonPointerUnescape(const Value: string): string;
begin
  Result := StringReplace(Value, '~1', '/', [rfReplaceAll]);
  Result := StringReplace(Result, '~0', '~', [rfReplaceAll]);
end;

end.
