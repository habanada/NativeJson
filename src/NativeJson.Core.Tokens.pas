{
  SPDX-FileCopyrightText: 2026 Selahattin Erkoc
  SPDX-License-Identifier: MIT

  This file is part of NativeJson.
  See LICENSE and THIRD-PARTY-NOTICES.md in the repository root.
}
unit NativeJson.Core.Tokens;

interface

{$I NativeJson.inc}

{$SCOPEDENUMS ON}

type
  TJsonToken = (None, StartObject, EndObject, StartArray, EndArray, PropertyName, Str, Integer, Float, Boolean, Null, Undefined, Date, Bytes, Comma, Colon, Comment);
  TJsonTokenSet = set of TJsonToken;

const
  TokenValues: TJsonTokenSet = [TJsonToken.Str, TJsonToken.Integer, TJsonToken.Float, TJsonToken.Boolean, TJsonToken.Null, TJsonToken.Undefined, TJsonToken.Date, TJsonToken.Bytes];
  TokenContainers: TJsonTokenSet = [TJsonToken.StartObject, TJsonToken.StartArray];

implementation

end.
