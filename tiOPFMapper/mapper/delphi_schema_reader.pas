unit delphi_schema_reader;

interface

uses
  Classes, SysUtils, Variants, tiUtils, mapper, OmniXML, OmniXMLUtils;

type

  // -----------------------------------------------------------------
  //  Class Objects
  // -----------------------------------------------------------------

  {: OmniXML version of TMapSchemaReader. }
  TOmniXMLSchemaReader = class(TMapSchemaReader)
  private
    FProject: TMapProject;
    FXML: IXMLDocument;
    function FindFirstCData(ANode: IXMLNode): IXMLText;
    function CreateSQLSelectList(AClassDef: TMapClassDef): string;
    function ExtractBaseClassName(const AName: string): string;
    procedure LoadXMLDoc(const AFile: string);
    procedure ReadProjectInfo;
    procedure ReadProjectUnits(AUnitList: IXMLNodeList);
    procedure ReadUnitClasses(AUnit: TMapUnitDef; ANode: IXMLNode);
    procedure ReadUnitEnums(AUnit: TMapUnitDef; ANode: IXMLNode);
    procedure ReadClassProps(AClass: TMapClassDef; ANode: IXMLNodeList);
    procedure ReadClassMapping(AClass: TMapClassDef; ANode: IXMLNodeList);
    procedure ReadClassSelects(AClass: TMapClassDef; ANode: IXMLNode);
    procedure ReadClassValidators(AClass: TMapClassDef; ANode: IXMLNode);
  public
    procedure ReadSchema(AProject: TMapProject; const AFileName: string = ''); overload; override;
    constructor Create; override;
    destructor Destroy; override;
  end;

  TProjectWriter = class(TBaseMapObject)
  protected
    FDirectory: string;
    FWriterProject: TMapProject;
    FDoc: IXMLDocument;
    procedure WriteProjectUnits(AProject: TMapProject; ADocElem: IXMLElement);
    procedure WriteUnit(AUnitDef: TMapUnitDef; AUnitNode: IXMLElement);
    procedure WriteUnitEnums(AUnitDef: TMapUnitDef; AUnitNode: IXMLElement);
    procedure WriteUnitClasses(AUnitDef: TMapUnitDef; AClassesNode: IXMLElement);
    procedure WriteSingleUnitClass(AClassDef: TMapClassDef; AClassesNode: IXMLElement);
    procedure WriteClassProps(AClassDef: TMapClassDef; AClassNode: IXMLElement);
    procedure WriteClassValidators(AClassDef: TMapClassDef; AClassNode: IXMLElement);
    procedure WriteClassMappings(AClassDef: TMapClassDef; AClassNode: IXMLElement);
    procedure WriteClassSelections(AClassDef: TMapClassDef; AClassNode: IXMLElement);
  public
    procedure WriteProject(AProject: TMapProject; const ADirectory: string; const AFileName: string); overload; virtual;
    procedure WriteProject(AProject: TMapProject; const AFilePath: string); overload; virtual;
    destructor Destroy; override;
  end;

implementation

uses
  AppModel;


{ TOmniXMLSchemaReader }

constructor TOmniXMLSchemaReader.Create;
begin
  inherited Create;
end;

function TOmniXMLSchemaReader.CreateSQLSelectList(AClassDef: TMapClassDef): string;
var
  lCtr: integer;
  lPropMap: TPropMapping;
begin
  result := AClassDef.ClassMapping.TableName + '.OID ';

  for lCtr := 0 to AClassDef.ClassMapping.PropMappings.Count - 1 do
  begin
    lPropMap := AClassDef.ClassMapping.PropMappings.Items[lCtr];
    result := result + ', ' + AClassDef.ClassMapping.TableName + '.' + lPropMap.FieldName;
  end;

  result := UpperCase(result);
end;

destructor TOmniXMLSchemaReader.Destroy;
begin
  FXML := nil;
  inherited Destroy;
end;

function TOmniXMLSchemaReader.ExtractBaseClassName(const AName: string): string;
begin
  if AnsiPos('T', AName) > 0 then
    result := Copy(AName, 2, Length(AName) - 1)
  else
    result := AName;
end;

function TOmniXMLSchemaReader.FindFirstCData(ANode: IXMLNode): IXMLText;
var
  lCtr: Integer;
  lNode: IXMLNode;
begin
  result := nil;

  for lCtr := 0 to ANode.ChildNodes.Length - 1 do
  begin
    lNode := ANode.ChildNodes.Item[lCtr];
    if lNode.NodeType = CDATA_SECTION_NODE then
    begin
      Result := IXMLText(lNode);
      exit;
    end;
  end;
end;

procedure TOmniXMLSchemaReader.LoadXMLDoc(const AFile: string);
begin
  FXML := nil;
  FXML := CreateXMLDoc;
  XMLLoadFromFile(FXML, AFile);
end;

procedure TOmniXMLSchemaReader.ReadClassMapping(AClass: TMapClassDef; ANode: IXMLNodeList);
var
  lCtr: integer;
  lNode: IXMLNode;
  lMapNode: IXMLNode;
  lMapPropNode: IXMLNode;
  lNewMapProp: TPropMapping;
  lLastGood: string;
  lAbstractValue: Boolean;
  s: string;
begin
  for lCtr := 0 to ANode.Length - 1 do
  begin
    lNode := ANode.Item[lCtr];
    if lNode.NodeType = ELEMENT_NODE then
    begin
      lMapPropNode := lNode.Attributes.GetNamedItem('field');
      if lMapPropNode = nil then
      begin
              //WriteLn('Error Node Type: ' + IntToStr(lNode.NodeType));
        raise Exception.Create(ClassName + '.ReadClassMapping: Mapping node Attribute "field" not found ' + 'reading schema for ' + AClass.BaseClassName);
      end;

      lNewMapProp := TPropMapping.create;
      lNewMapProp.FieldName := lNode.Attributes.GetNamedItem('field').NodeValue;
      lNewMapProp.PropName := lNode.Attributes.GetNamedItem('prop').NodeValue;
      lMapPropNode := lNode.Attributes.GetNamedItem('getter');
      if Assigned(lMapPropNode) then
        lNewMapProp.PropertyGetter := lMapPropNode.NodeValue;
      lMapPropNode := lNode.Attributes.GetNamedItem('setter');
      if Assigned(lMapPropNode) then
        lNewMapProp.PropertySetter := lMapPropNode.NodeValue;
      lMapPropNode := lNode.Attributes.GetNamedItem('abstract');
      if Assigned(lMapPropNode) then
      begin
        s := LowerCase(lMapPropNode.NodeValue);
        if (s = 'false') or (s = '0') or (s = 'no') then
          lAbstractValue := False
        else
          lAbstractValue := True;
      end
      else
        lAbstractValue := True;
      lNewMapProp.PropertyAccessorsAreAbstract := lAbstractValue;

      lLastGood := lNewMapProp.PropName;

      lMapNode := lNode.Attributes.GetNamedItem('type');

      if lMapNode = nil then
        lNewMapProp.PropertyType := TAppModel.Instance.CurrentPropertyTypes.FindByTypeName('String')
      else
        lNewMapProp.PropertyType := TAppModel.Instance.CurrentPropertyTypes.FindByTypeName(lMapNode.NodeValue);

      AClass.ClassMapping.PropMappings.Add(lNewMapProp);
    end;
  end;
end;

procedure TOmniXMLSchemaReader.ReadClassProps(AClass: TMapClassDef; ANode: IXMLNodeList);
var
  lCtr: Integer;
  lPropNode: IXMLNode;
  lPropAttr: IXMLNode;
  lNewProp: TMapClassProp;
begin
  for lCtr := 0 to ANode.Length - 1 do
  begin
    lPropNode := ANode.Item[lCtr];
    if lPropNode.NodeType = ELEMENT_NODE then
    begin
      lNewProp := TMapClassProp.create;

      lNewProp.Name := lPropNode.Attributes.GetNamedItem('name').NodeValue;

      // Read only?
      lPropAttr := lPropNode.Attributes.GetNamedItem('read-only');
      if lPropAttr <> nil then
        lNewProp.IsReadOnly := StrToBool(lPropAttr.NodeValue)
      else
        lNewProp.IsReadOnly := false;

      // virtual getter?
      lPropAttr := lPropNode.Attributes.GetNamedItem('virtual');

      if lPropAttr <> nil then
        lNewProp.VirtualGetter := StrToBool(lPropAttr.NodeValue)
      else
        lNewProp.VirtualGetter := false;

      // Property type?
      lPropAttr := lPropNode.Attributes.GetNamedItem('type');

      if lPropAttr <> nil then
      begin
        if lPropAttr.NodeValue <> '' then
        begin
          lNewProp.PropertyType := TAppModel.Instance.CurrentPropertyTypes.FindByTypeName(lPropAttr.NodeValue);
        end
        else
        begin
          lNewProp.PropertyType := TAppModel.Instance.CurrentPropertyTypes.FindByTypeName('String');
        end;
      end
      else
      begin
        lNewProp.PropertyType := TAppModel.Instance.CurrentPropertyTypes.FindByTypeName('String');
      end;

      AClass.ClassProps.Add(lNewProp);
    end;
  end;
end;

procedure TOmniXMLSchemaReader.ReadClassSelects(AClass: TMapClassDef; ANode: IXMLNode);
//var
//  lSelectList: IXMLNodeList;
begin
//  lSelectList := ANode.FindNode('enums').ChildNodes;
end;

procedure TOmniXMLSchemaReader.ReadClassValidators(AClass: TMapClassDef; ANode: IXMLNode);
var
  lCtr: Integer;
  lVal: TMapValidator;
  lValNode: IXMLNode;
  lValueNode: IXMLNode;
  lTypeNode: IXMLNode;
  lProp: TMapClassProp;
  lValStr: string;
  lTempStr: string;
  lType: TMapPropType;
begin
  if not ANode.HasChildNodes then
    exit;

  for lCtr := 0 to ANode.ChildNodes.Length - 1 do
  begin
    lValNode := ANode.ChildNodes.Item[lCtr];
    if lValNode.NodeType = ELEMENT_NODE then
    begin
      lVal := TMapValidator.Create;
          // Get validator type.  "required" is the default.
      lTypeNode := lValNode.Attributes.GetNamedItem('type');
      if lTypeNode <> nil then
        lVal.ValidatorType := gStrToValType(lTypeNode.NodeValue)
      else
        lVal.ValidatorType := vtRequired;

      lVal.ClassProp := TMapClassProp(AClass.ClassProps.FindByName(lValNode.Attributes.GetNamedItem('prop').NodeValue));

      if lVal.ValidatorType <> vtRequired then
      begin
        if lVal.ClassProp = nil then
          raise Exception.Create('No registered property in class "' + AClass.BaseClassName + '" found with name "' + lValNode.Attributes.GetNamedItem('prop').NodeValue + '"');

        lProp := lVal.ClassProp;
        lType := lProp.PropertyType.BaseType;

        lValueNode := lValNode.SelectSingleNode('value');

        if lValueNode <> nil then
        begin
          lValStr := lValueNode.Text;
          case lProp.PropertyType.BaseType of
            ptAnsiString, ptString:
              lVal.Value := lValStr;
            ptBoolean:
              lVal.Value := StrtoBool(lValStr);
            ptInt64, ptInteger:
              lVal.Value := StrToInt(lValStr);
            ptDateTime:
              lVal.Value := tiIntlDateStorAsDateTime(lValStr);
            ptEnum:
              ;
            ptDouble, ptCurrency, ptSingle:
              lVal.Value := StrToFloat(lValStr);
          end;
        end;
      end;
      AClass.Validators.Add(lVal);
    end;
  end;
end;

procedure TOmniXMLSchemaReader.ReadProjectInfo;
begin

end;

procedure TOmniXMLSchemaReader.ReadProjectUnits(AUnitList: IXMLNodeList);
var
  lUnitsList: IXMLNodeList;
  lCtr: Integer;
  lUnit: TMapUnitDef;
  lRefNodeList, lRefNode: IXMLNode;
  lRefCtr: integer;
  lUnitNode: IXMLNode;
  lName: string;
begin
  if AUnitList = nil then
    exit;

  for lCtr := 0 to AUnitList.Length - 1 do
  begin
    lUnitNode := AUnitList.Item[lCtr];

    if lUnitNode.NodeType = ELEMENT_NODE then
    begin
      lName := lUnitNode.Attributes.GetNamedItem('name').NodeValue;
      lUnit := TMapUnitDef(FProject.Units.FindByProps(['Name'], [lName]));

      if lUnit = nil then
      begin
        lUnit := TMapUnitDef.Create;
        lUnit.Name := lName;
        FProject.Units.Add(lUnit);
      end;

      ReadUnitEnums(lUnit, lUnitNode.SelectSingleNode('enums'));
      ReadUnitClasses(lUnit, lUnitNode.SelectSingleNode('classes'));

      // Reference (uses)
      lRefNodeList := lUnitNode.SelectSingleNode('references');

      if (lRefNodeList <> nil) and (lRefNodeList.HasChildNodes) then
      begin
        for lRefCtr := 0 to lRefNodeList.ChildNodes.Length - 1 do
        begin
          lRefNode := lRefNodeList.ChildNodes.Item[lRefCtr];

          if lRefNode.NodeType = ELEMENT_NODE then
            lUnit.References.Add(lRefNode.Attributes.GetNamedItem('name').NodeValue);
        end;
      end;
    end;
  end;
end;

procedure TOmniXMLSchemaReader.ReadSchema(AProject: TMapProject; const AFileName: string);
var
  lNode: IXMLNode;
  lNodeList: IXMLNodeList;
  lAttr: IXMLNode;
  lIncNode: IXMLNode;
  lCtr: Integer;
  lEnumTypeStr: string;
  lUnitList: IXMLNodeList;
  lIncProjDoc: IXMLDocument;
  lIncPath: string;
  lDirNode: IXMLNode;
  lPath: string;
begin
  FProject := AProject;
  FProject.ClearAll;

  LoadXMLDoc(AFileName);

  lNode := FXML.DocumentElement;

  if lNode.Attributes.GetNamedItem('project-name') = nil then
    raise Exception.Create(ClassName + '.ReadSchema: Missing <project-name> attribute.');

  FProject.Generaloptions.ProjectName := lNode.Attributes.GetNamedItem('project-name').NodeValue;

  // Establish the base directory
  lDirNode := lNode.Attributes.GetNamedItem('base-directory');

  if lDirNode <> nil then
  begin
    if lDirNode.NodeValue <> '' then
      FProject.GeneralOptions.BaseDirectory := lNode.Attributes.GetNamedItem('base-directory').NodeValue
    else
    begin
      lPath := ExtractFileDir(AFileName);

      if lPath = '' then  // means only the filename was passed in, without any path details
        lPath := GetCurrentDir;
      FProject.GeneralOptions.BaseDirectory := lPath;
    end;
  end
  else
  begin
    lPath := ExtractFileDir(AFileName);

    if lPath = '' then  // means only the filename was passed in, without any path details
      lPath := GetCurrentDir;
    FProject.GeneralOptions.BaseDirectory := lPath;
  end;

  lDirNode := lNode.Attributes.GetNamedItem('outputdir');

  if lDirNode = nil then
    FProject.GeneralOptions.OrigOutDirectory := FProject.GeneralOptions.BaseDirectory
  else
    FProject.GeneralOptions.OrigOutDirectory := lDirNode.NodeValue;

  lAttr := lNode.Attributes.GetNamedItem('tab-spaces');

  if lAttr <> nil then
    FProject.CodeGenerationOptions.TabSpaces := StrToInt(lAttr.NodeValue)
  else
    FProject.CodeGenerationOptions.TabSpaces := 2;

  lAttr := lNode.Attributes.GetNamedItem('begin-end-tabs');

  if lAttr <> nil then
    FProject.CodeGenerationOptions.BeginEndTabs := StrtoInt(lAttr.NodeValue)
  else
    FProject.CodeGenerationOptions.BeginEndTabs := 1;

  lAttr := lNode.Attributes.GetNamedItem('visibility-tabs');

  if lAttr <> nil then
    FProject.CodeGenerationOptions.VisibilityTabs := StrtoInt(lAttr.NodeValue)
  else
    FProject.CodeGenerationOptions.VisibilityTabs := 1;

  lAttr := lNode.Attributes.GetNamedItem('enum-type');

  if lAttr <> nil then
  begin
    lEnumTypeStr := lAttr.NodeValue;

    if lowercase(lEnumTypeStr) = 'string' then
      FProject.DatabaseOptions.EnumerationType := etString
    else
      FProject.DatabaseOptions.EnumerationType := etInt;
  end
  else
  begin
    FProject.DatabaseOptions.EnumerationType := etInt;
  end;

  lAttr := lNode.Attributes.GetNamedItem('double-quote-db-field-names');

  if lAttr <> nil then
    FProject.DatabaseOptions.DoubleQuoteDBFieldNames := StrToBool(lAttr.NodeValue)
  else
    FProject.DatabaseOptions.DoubleQuoteDBFieldNames := false;

  // Process Includes
  if lNode.SelectSingleNode('includes') <> nil then
    lNodeList := lNode.SelectSingleNode('includes').ChildNodes
  else
    lNodeList := nil;

  if lNodeList <> nil then
  begin
    for lCtr := 0 to lNodeList.Length - 1 do
    begin
      lIncNode := lNodeList.Item[lCtr];

      if lIncNode.NodeType = ELEMENT_NODE then
      begin
        lIncPath := lIncNode.Attributes.GetNamedItem('file-name').NodeValue;
        FProject.Includes.Add(lIncPath);
        lIncProjDoc := CreateXMLDoc;
        XMLLoadFromFile(lIncProjDoc, FProject.GeneralOptions.BaseDirectory + PathDelim + lIncPath);

        try
          lUnitList := lIncProjDoc.DocumentElement.SelectSingleNode('project-units').ChildNodes;
        finally
          ReadProjectUnits(lUnitList);

          if lIncProjDoc <> nil then
            lIncProjDoc := nil;
        end;
      end;
    end;
  end;

  lUnitList := FXML.DocumentElement.SelectSingleNode('project-units').ChildNodes;
  ReadProjectUnits(lUnitList);
end;

procedure TOmniXMLSchemaReader.ReadUnitClasses(AUnit: TMapUnitDef; ANode: IXMLNode);
var
  lCtr, lSelectCtr, lParamsCtr: integer;
  lClassNode: IXMLNode;
  lClassListNodes: IXMLNodeList;
  lClassMappings: IXMLNodeList;
  lClassMapNode: IXMLNode;
  lClassProps: IXMLNodeList;
  lClassSelects: IXMLNodeList;
  lNewClass: TMapClassDef;
  lClassAttr: IXMLNode;
  lSelListNode: IXMLNode;
  lSelectNode: IXMLNode;
  lParamListNode: IXMLNode;
  lParam: IXMLNode;
  lNewParam: TSelectParam;
  lCData: IXMLText;
  lNewSelect: TClassMappingSelect;
  lTemp: string;
  lValNode: IXMLNode;
  lCDataCtr: Integer;
begin
  lClassListNodes := ANode.ChildNodes;

  for lCtr := 0 to lClassListNodes.Length - 1 do
  begin
    lClassNode := lClassListNodes.Item[lCtr];

    if lClassNode <> nil then
    begin
      if lClassNode.NodeType = ELEMENT_NODE then
      begin
        lNewClass := TMapClassDef.Create;

        lClassAttr := lClassNode.Attributes.GetNamedItem('def-type');
        if lClassAttr <> nil then
          lNewClass.DefType := gStrToClassDefType(lClassAttr.NodeValue)
        else
          lNewClass.DefType := dtReference;

        lClassAttr := lClassNode.Attributes.GetNamedItem('base-unit');
        if lClassAttr <> nil then
          lNewClass.BaseUnitName := lClassAttr.NodeValue;

        lClassAttr := lClassNode.Attributes.GetNamedItem('base-class');
        if lClassAttr <> nil then
          lNewClass.BaseClassName := lClassAttr.NodeValue
        else
          lNewClass.BaseClassName := 'TtiObject';

        lClassAttr := lClassNode.Attributes.GetNamedItem('base-class-parent');
        if lClassAttr <> nil then
          lNewClass.BaseClassParent := lClassAttr.NodeValue
        else
          lNewClass.BaseClassParent := 'TtiObject';

        lClassAttr := lClassNode.Attributes.GetNamedItem('base-listclass-parent');
        if lClassAttr <> nil then
          lNewClass.BaseListClassParent := lClassAttr.NodeValue
        else
          lNewClass.BaseListClassParent := 'TtiMappedFilteredObjectList';

        lClassAttr := lClassNode.Attributes.GetNamedItem('auto-map');
        if lClassAttr <> nil then
          lNewClass.AutoMap := StrToBool(lClassAttr.NodeValue);

        lClassAttr := lClassNode.Attributes.GetNamedItem('auto-create-base');
        if lClassAttr <> nil then
          lNewClass.AutoCreateBase := StrToBool(lClassAttr.NodeValue);

        lClassAttr := lClassNode.Attributes.GetNamedItem('crud');
        if lClassAttr <> nil then
          lNewClass.Crud := lClassAttr.NodeValue
        else
          lNewClass.Crud := 'all';

        lClassAttr := lClassNode.Attributes.GetNamedItem('auto-create-list');
        if lClassAttr <> nil then
          lNewClass.AutoCreateListClass := StrToBool(lClassAttr.NodeValue)
        else
          lNewClass.AutoCreateListClass := true;

        lClassAttr := lClassNode.Attributes.GetNamedItem('list-saves-database-name');
        if lClassAttr <> nil then
          lNewClass.ListSavesDatabaseName := StrToBool(lClassAttr.NodeValue)
        else
          lNewClass.ListSavesDatabaseName := true;

        lClassAttr := lClassNode.Attributes.GetNamedItem('notify-observers');
        if lClassAttr <> nil then
          lNewClass.NotifyObserversOfPropertyChanges := StrToBool(lClassAttr.NodeValue);

        if lClassNode.SelectSingleNode('class-props') = nil then
          raise Exception.Create(ClassName + '.ReadUnitClasses: "class-props" node is not present.');

        lClassProps := lClassNode.SelectSingleNode('class-props').ChildNodes;
        if lClassProps <> nil then
          ReadClassProps(lNewClass, lClassProps);

        lClassMapNode := lClassNode.SelectSingleNode('mapping');
        if lClassMapNode <> nil then
        begin
          lNewClass.ClassMapping.PKName := lClassMapNode.Attributes.GetNamedItem('pk').NodeValue;
          lNewClass.ClassMapping.TableName := lClassMapNode.Attributes.GetNamedItem('table').NodeValue;
          lNewClass.ClassMapping.PKField := lClassMapNode.Attributes.GetNamedItem('pk-field').NodeValue;
          lNewClass.ClassMapping.OIDType := gStrToOIDType(lClassMapNode.Attributes.GetNamedItem('oid-type').NodeValue);
          lClassMappings := lClassMapNode.ChildNodes;

          if lClassMappings <> nil then
            ReadClassMapping(lNewClass, lClassMappings);
        end;

        lValNode := lClassNode.SelectSingleNode('validators');

        if lValNode <> nil then
          ReadClassValidators(lNewClass, lValNode);

        // Read in any selections
        lSelListNode := lClassNode.SelectSingleNode('selections');

        if lSelListNode <> nil then
        begin
          if lSelListNode.HasChildNodes then
          begin
            for lSelectCtr := 0 to lSelListNode.ChildNodes.Length - 1 do
            begin
              lSelectNode := lSelListNode.ChildNodes.Item[lSelectCtr];

              if lSelectNode.NodeType = ELEMENT_NODE then
              begin

                lNewSelect := TClassMappingSelect.Create;

                lCData := FindFirstCData(lSelectNode.SelectSingleNode('sql'));

                if lCData.HasChildNodes then
                  raise exception.Create('has children');

                lTemp := lCData.Text;

                lTemp := GetCDataChild(lSelectNode.SelectSingleNode('sql')).NodeValue;
//                                lTemp := StringReplace(lCData.Data, #13, '', [rfReplaceAll]);
//                                lTemp := StringReplace(lTemp, #10, '', [rfReplaceAll]);
                            // Change variable ${field_list} into list of field names in sql format
//                            if POS('${field_list}', lTemp) > 0 then
//                              lTemp := StringReplace(lTemp, '${field_list}', CreateSQLSelectList(lNewClass), [rfReplaceAll]);
                lNewSelect.SQL := lTemp;

                lNewSelect.Name := lSelectNode.Attributes.GetNamedItem('name').NodeValue;
                lParamListNode := lSelectNode.SelectSingleNode('params');
                if (lParamListNode <> nil) and (lParamListNode.HasChildNodes) then
                begin
                  for lParamsCtr := 0 to lParamListNode.ChildNodes.Length - 1 do
                  begin
                    lParam := lParamListNode.ChildNodes.Item[lParamsCtr];
                    if lParam.NodeType = ELEMENT_NODE then
                    begin
                      lNewParam := TSelectParam.Create;
                      lNewParam.ParamName := lParam.Attributes.GetNamedItem('name').NodeValue;
//                      lNewParam.ParamType := gStrToPropType(lParam.Attributes.GetNamedItem('type').NodeValue);
                      lNewParam.ParamType := TAppModel.Instance.CurrentPropertyTypes.FindByTypeName(lParam.Attributes.GetNamedItem('type').NodeValue);

//                      if lNewParam.ParamType = ptEnum then
//                        lNewParam.ParamTypeName := lParam.Attributes.GetNamedItem('type-name').NodeValue
//                      else
//                        lNewParam.ParamTypeName := lNewParam.TypeName;
                      lNewParam.PassBy := lParam.Attributes.GetNamedItem('pass-by').NodeValue;
                      lNewParam.SQLParamName := lParam.Attributes.GetNamedItem('sql-param').NodeValue;
                      lNewSelect.Params.Add(lNewParam);
                    end;
                  end;
                end;

                // finally, add to list.
                lNewClass.Selections.Add(lNewSelect);
              end;
            end;
          end;
        end;

        // Add to unit classes
        AUnit.UnitClasses.Add(lNewClass);
        // Addreference to ProjectClasses
        FProject.ProjectClasses.Add(lNewClass);
      end;
    end;
  end;
end;

procedure TOmniXMLSchemaReader.ReadUnitEnums(AUnit: TMapUnitDef; ANode: IXMLNode);
var
  lEnumList: IXMLNodeList;
  lEnumValuesList: IXMLNodeList;
  lEnumValueNode: IXMLNode;
  lEnum: IXMLNode;
  lAttr: IXMLNode;
  lCtr: Integer;
  lValueCtr: integer;
  lNewEnum: TMapEnum;
  lNewEnumValue: TMapEnumValue;
  lValuesNode: IXMLNode;
begin
  if (ANode = nil) or (not ANode.HasChildNodes) then
    exit;

  lEnumList := ANode.ChildNodes;

  for lCtr := 0 to lEnumList.Length - 1 do
  begin
    lEnum := lEnumList.Item[lCtr];
    if lEnum.NodeType = ELEMENT_NODE then
    begin
      // Create the Enum Class Def.
      lNewEnum := TMapEnum.Create;
      lNewEnum.TypeName := lEnum.Attributes.GetNamedItem('name').NodeValue;

      if lEnum.Attributes.GetNamedItem('set') <> nil then
      begin
        lNewEnum.EnumerationSet := StrToBool(lEnum.Attributes.GetNamedItem('set').NodeValue);

        if lEnum.Attributes.GetNamedItem('set-name') <> nil then
          lNewEnum.EnumerationSetName := lEnum.Attributes.GetNamedItem('set-name').NodeValue;
      end;

      // Retrieve its values
      lValuesNode := lEnum.SelectSingleNode('values');
      if lValuesNode <> nil then
        lEnumValuesList := lValuesNode.ChildNodes;

      if lEnumValuesList <> nil then
      begin
        for lValueCtr := 0 to lEnumValuesList.Length - 1 do
        begin
          lEnumValueNode := lEnumValuesList.Item[lValueCtr];
          if lEnumValueNode.NodeType = ELEMENT_NODE then
          begin
            lNewEnumValue := TMapEnumValue.Create;
            lNewEnumValue.EnumValueName := lEnumValueNode.Attributes.GetNamedItem('name').NodeValue;

            lAttr := lEnumValueNode.Attributes.GetNamedItem('value');
            if lAttr <> nil then
              lNewEnumValue.EnumValue := StrtoInt(lAttr.NodeValue);

            lNewEnum.Values.Add(lNewEnumValue);
          end;
        end;
      end;

      // Add it to the unit def.
      AUnit.UnitEnums.Add(lNewEnum);
      // Add reference to ProjectEnums
      FProject.ProjectEnums.Add(lNewEnum);
      // Add reference to Application Property Types
      TAppModel.Instance.CurrentPropertyTypes.Add(lNewEnum);
    end;
  end;

end;

{ TProjectWriter }

destructor TProjectWriter.Destroy;
begin

  inherited;
end;

procedure TProjectWriter.WriteClassMappings(AClassDef: TMapClassDef; AClassNode: IXMLElement);
var
  lCtr: integer;
  lMapProp: TPropMapping;
  lNewMapNode: IXMLElement;
  lNewMapPropNode: IXMLElement;
begin
  lNewMapNode := FDoc.CreateElement('mapping');
  AClassNode.AppendChild(lNewMapNode);

  lNewMapNode.SetAttribute('table', AClassDef.ClassMapping.TableName);
  lNewMapNode.SetAttribute('pk', AClassDef.ClassMapping.PKName);
  lNewMapNode.SetAttribute('pk-field', AClassDef.ClassMapping.PKField);

  case AClassDef.ClassMapping.OIDType of
    otString:
      lNewMapNode.SetAttribute('oid-type', 'string');
    otInt:
      lNewMapNode.SetAttribute('oid-type', 'int');
  end;

  for lCtr := 0 to AClassDef.ClassMapping.PropMappings.Count - 1 do
  begin
    lMapProp := AClassDef.ClassMapping.PropMappings.Items[lCtr];
    lNewMapPropNode := FDoc.CreateElement('prop-map');
    lNewMapPropNode.SetAttribute('prop', lMapProp.PropName);
    lNewMapPropNode.SetAttribute('field', lMapProp.FieldName);
    lNewMapPropNode.SetAttribute('type', lMapProp.PropertyType.TypeName);
    lNewMapNode.AppendChild(lNewMapPropNode);
  end;
end;

procedure TProjectWriter.WriteClassProps(AClassDef: TMapClassDef; AClassNode: IXMLElement);
var
  lNewPropNode: IXMLElement;
  lClassPropsNode: IXMLElement;
  lCtr: integer;
  lProp: TMapClassProp;
begin
  lClassPropsNode := FDoc.CreateElement('class-props');
  AClassNode.AppendChild(lClassPropsNode);

  for lCtr := 0 to AClassDef.ClassProps.Count - 1 do
  begin
    lProp := AClassDef.ClassProps.Items[lCtr];
    lNewPropNode := FDoc.CreateElement('prop');
    lNewPropNode.SetAttribute('name', lProp.Name);
    lNewPropNode.SetAttribute('type', lProp.PropertyType.TypeName);
    lClassPropsNode.AppendChild(lNewPropNode);
  end;
end;

procedure TProjectWriter.WriteClassSelections(AClassDef: TMapClassDef; AClassNode: IXMLElement);
var
  lCtr, lParamCtr: integer;
  lSelect: TClassMappingSelect;
  lParam: TSelectParam;
  lNewSelNode: IXMLElement;
  lNewSelectionsNode: IXMLElement;
  lNewParamsNode: IXMLElement;
  lNewParam: IXMLElement;
  lNewCDATA: IXMLCDATASection;
  lNewSQLNode: IXMLElement;
begin
  lNewSelectionsNode := FDoc.CreateElement('selections');
  AClassNode.AppendChild(lNewSelectionsNode);

  for lCtr := 0 to AClassDef.Selections.Count - 1 do
  begin
    lSelect := AClassDef.Selections.Items[lCtr];
    lNewSelNode := FDoc.CreateElement('select');
    lNewSelNode.SetAttribute('name', lSelect.Name);
      // SQL
    lNewSQLNode := FDoc.CreateElement('sql');
    lNewCDATA := FDoc.CreateCDATASection(WrapText(lSelect.SQL, 40));
    lNewSQLNode.AppendChild(lNewCDATA);
    lNewSelNode.AppendChild(lNewSQLNode);

      // Params Node
    lNewParamsNode := FDoc.CreateElement('params');
    lNewSelNode.AppendChild(lNewParamsNode);

      // Add params to Params node
    for lParamCtr := 0 to lSelect.Params.Count - 1 do
    begin
      lParam := lSelect.Params.Items[lParamCtr];
      lNewParam := FDoc.CreateElement('param');
      lNewParam.SetAttribute('name', lParam.ParamName);
      lNewParam.SetAttribute('pass-by', lParam.PassBy);
      lNewParam.SetAttribute('sql-param', lParam.SQLParamName);
      lNewParam.SetAttribute('type', lParam.ParamType.TypeName);
      lNewParamsNode.AppendChild(lNewParam);
    end;
      // finally add the selection node to the <selections> node.
    lNewSelectionsNode.AppendChild(lNewSelNode);
  end;
end;

procedure TProjectWriter.WriteClassValidators(AClassDef: TMapClassDef; AClassNode: IXMLElement);
var
  lVal: TMapValidator;
  lNewValidatorsNode: IXMLElement;
  lNewValNode: IXMLElement;
  lNewValItemNode: IXMLElement;
  lNewValueNode: IXMLElement;
  lCtr, lItemCtr: integer;
begin
  lNewValidatorsNode := FDoc.CreateElement('validators');
  AClassNode.AppendChild(lNewValidatorsNode);

  for lCtr := 0 to AClassDef.Validators.Count - 1 do
  begin
    lVal := AClassDef.Validators.Items[lCtr];
    lNewValNode := FDoc.CreateElement('item');
    lNewValNode.SetAttribute('prop', lVal.ClassProp.Name);
    lNewValNode.SetAttribute('type', gValTypeToStr(lVal.ValidatorType));
    if not VarIsNull(lVal.Value) then
    begin
      lNewValueNode := FDoc.CreateElement('value');
      lNewValueNode.Text := lVal.Value;
      lNewValNode.AppendChild(lNewValueNode);
    end;
    lNewValidatorsNode.AppendChild(lNewValNode);
  end;
end;

procedure TProjectWriter.WriteProject(Aproject: TMapProject; const AFilePath: string);
var
  lDocElem: IXMLElement;
  lNewElem: IXMLElement;
  lDir: string;
begin
  if FDoc <> nil then
  begin
    FDoc := nil;
  end;

  FWriterProject := Aproject;

  FDoc := TXMLDocument.Create;

  // Setup the <project> root node
  lDocElem := FDoc.CreateElement('project');
  lDocElem.SetAttribute('tab-spaces', IntToStr(FWriterProject.CodeGenerationOptions.TabSpaces));
  lDocElem.SetAttribute('begin-end-tabs', IntToStr(FWriterProject.CodeGenerationOptions.BeginEndTabs));
  lDocElem.SetAttribute('visibility-tabs', IntToStr(FWriterProject.CodeGenerationOptions.VisibilityTabs));
  lDocElem.SetAttribute('project-name', FWriterProject.GeneralOptions.ProjectName);
  lDocElem.SetAttribute('outputdir', FWriterProject.GeneralOptions.OrigOutDirectory);

  case FWriterProject.DatabaseOptions.EnumerationType of
    etInt:
      lDocElem.SetAttribute('enum-type', 'int');
    etString:
      lDocElem.SetAttribute('enum-type', 'string');
  end;

  lDocElem.SetAttribute('double-quote-db-field-names', LowerCase(BoolToStr(FWriterProject.DatabaseOptions.DoubleQuoteDBFieldNames, true)));

  FDoc.AppendChild(lDocElem);

  WriteProjectUnits(FWriterProject, lDocElem);

  XMLSaveToFile(FDoc, AFilePath, ofIndent);
end;

procedure TProjectWriter.WriteProject(AProject: TMapProject; const ADirectory, AFileName: string);
begin
  if FDoc <> nil then
  begin
    FreeAndNil(FDoc);
  end;

  FWriterProject := AProject;

  FDoc := CreateXMLDoc;

  FDirectory := ExcludeTrailingPathDelimiter(ADirectory);

  FDirectory := ExcludeTrailingPathDelimiter(ExtractFileDir(AFileName));

  if AFileName <> '' then
    WriteProject(AProject, FDirectory + PathDelim + AFileName)
  else
    WriteProject(AProject, FDirectory + PathDelim + FWriterProject.GeneralOptions.ProjectName + '.xml');
end;

procedure TProjectWriter.WriteProjectUnits(AProject: TMapProject; ADocElem: IXMLElement);
var
  lCtr: integer;
  lUnit: TMapUnitDef;
  lUnitsElem: IXMLElement;
  lNewUnitNode: IXMLElement;
begin
  lUnitsElem := FDoc.CreateElement('project-units');
  FDoc.DocumentElement.AppendChild(lUnitsElem);

  for lCtr := 0 to FWriterProject.Units.Count - 1 do
  begin
    lUnit := FWriterProject.Units.Items[lCtr];
    lNewUnitNode := FDoc.CreateElement('unit');
    lNewUnitNode.SetAttribute('name', lUnit.Name);
    WriteUnit(lUnit, lNewUnitNode);
    lUnitsElem.AppendChild(lNewUnitNode);
  end;
end;

procedure TProjectWriter.WriteSingleUnitClass(AClassDef: TMapClassDef; AClassesNode: IXMLElement);
var
  lNewClassNode: IXMLElement;
begin
  lNewClassNode := FDoc.CreateElement('class');
  AClassesNode.AppendChild(lNewClassNode);

  lNewClassNode.SetAttribute('base-class', AClassDef.BaseClassName);
  lNewClassNode.SetAttribute('base-class-parent', AClassDef.BaseClassParent);
  lNewClassNode.SetAttribute('auto-map', LowerCase(BoolToStr(AClassDef.AutoMap, true)));
  lNewClassNode.SetAttribute('auto-create-list', LowerCase(BoolToStr(AClassDef.AutoCreateListClass, true)));
  lNewClassNode.SetAttribute('list-saves-database-name', LowerCase(BoolToStr(AClassDef.ListSavesDatabaseName, true)));
  lNewClassNode.SetAttribute('notify-observers', LowerCase(BoolToStr(AClassDef.NotifyObserversOfPropertyChanges, true)));

  WriteClassProps(AClassDef, lNewClassNode);
  WriteClassValidators(AClassDef, lNewClassNode);
  WriteClassMappings(AClassDef, lNewClassNode);
  WriteClassSelections(AClassDef, lNewClassNode);
end;

procedure TProjectWriter.WriteUnit(AUnitDef: TMapUnitDef; AUnitNode: IXMLElement);
var
  lCtr: integer;
  lEnumNode: IXMLElement;
  lClassesNode: IXMLElement;
  lEnum: TMapEnum;
  lClass: TMapClassDef;
begin
  lEnumNode := FDoc.CreateElement('enums');
  AUnitNode.AppendChild(lEnumNode);

  lClassesNode := FDoc.CreateElement('classes');
  AUnitNode.AppendChild(lClassesNode);

  WriteUnitEnums(AUnitDef, AUnitNode);

  WriteUnitClasses(AUnitDef, lClassesNode);
end;

procedure TProjectWriter.WriteUnitClasses(AUnitDef: TMapUnitDef; AClassesNode: IXMLElement);
var
  lCtr: integer;
  lClassDef: TMapClassDef;
  lClassesNode: IXMLNode;
begin
  for lCtr := 0 to AUnitDef.UnitClasses.Count - 1 do
  begin
    lClassDef := AUnitDef.UnitClasses.Items[lCtr];
    WriteSingleUnitClass(lClassDef, AClassesNode);
  end;
end;

procedure TProjectWriter.WriteUnitEnums(AUnitDef: TMapUnitDef; AUnitNode: IXMLElement);
var
  lEnumsNode: IXMLNode;
  lEnumEl: IXMLElement;
  lValuesEl: IXMLElement;
  lSingleValNode: IXMLElement;
  lItemEl: IXMLElement;
  lCtr: integer;
  lItemCtr: integer;
  lEnum: TMapEnum;
  lEnumVal: TMapEnumValue;
begin
  lEnumsNode := AUnitNode.SelectSingleNode('enums');
  for lCtr := 0 to AUnitDef.UnitEnums.Count - 1 do
  begin
    lEnum := AUnitDef.UnitEnums.Items[lCtr];
    lEnumEl := FDoc.CreateElement('enum');
    lValuesEl := FDoc.CreateElement('values');
    lEnumEl.AppendChild(lValuesEl);
    lEnumEl.SetAttribute('name', lEnum.TypeName);

    if lEnum.EnumerationSet and (lEnum.EnumerationSetName <> EmptyStr) then
    begin
      lEnumEl.SetAttribute('set', LowerCase(BoolToStr(lEnum.EnumerationSet, true)));
      lEnumEl.SetAttribute('set-name', lEnum.EnumerationSetName);
    end;

    // items of enum
    for lItemCtr := 0 to lEnum.Values.Count - 1 do
    begin
      lEnumVal := lEnum.Values.Items[lItemCtr];
      lSingleValNode := FDoc.CreateElement('item');
      lSingleValNode.SetAttribute('name', lEnumVal.EnumValueName);
      if lEnumVal.EnumValue >= 0 then
        lSingleValNode.SetAttribute('value', IntToStr(lEnumVal.EnumValue));
          // Append to <values> node
      lValuesEl.AppendChild(lSingleValNode);
    end;

    lEnumsNode.AppendChild(lEnumEl);
  end;
end;

initialization
  gSetSchemaReaderClass(TOmniXMLSchemaReader);

end.

