classdef ADCMeta < handle
    %% ===================================================================
    %% METADATA OF THE PARAMETERS FOR THE ANALOG-TO-DIGITAL-CONVERTER (ADC)
    %% ===================================================================

    properties (SetAccess = immutable)
        Name (1,1) string 
        Unit (1,1) string = string(missing) 
    end

    properties (SetAccess = private)
        Validator
        DataType (1,1) string 
        StoredValue = NaN
    end
    
    properties (Dependent)
        Value 
    end

    methods
        function obj = ADCMeta(Name, Validator, DataType, Unit)
            %% Support zero-argument constructor for preallocation
            if nargin == 0
                return;
            end
            
            %% Datatype Check For the Name Of the Parameter
            if ~(isstring(Name) || ischar(Name))
                error('ADCMeta:BadName', ...
                    'Name must be a string or char vector.');
            end
            
            %% Validator Must Be a Function Handle 
            if ~isa(Validator, 'function_handle')
                error('ADCMeta:BadValidator', ...
                    'Validator must be a function handle.');
            end

            obj.Name = string(Name);
            obj.Validator = Validator;
            obj.DataType = string(DataType);

            %% Handle Optional Unit Argument
            if nargin >= 4
                if isempty(Unit) || (isstring(Unit) ...
                        && ismissing(Unit)) || Unit == ""
                    error('ADCMeta:EmptyUnit', ...
                        'Unit cannot be empty. Pass a valid unit or omit');
                end

                if ~(isstring(Unit) || ischar(Unit))
                    error('ADCMeta:BadUnit', ...
                        'Unit must be a string');
                end
                obj.Unit = string(Unit);
            end
            
            %% Acceptable Datatypes List For ADC Parameters 
            AllowedType = {'double', 'single', 'int8', 'int16', ...
                           'int32','int64', 'uint8', 'uint16', 'uint32', ... 
                           'uint64', 'embedded.fi', 'fi'};
                       
            %% Verify if requested DataType is supported
            if ~ismember(obj.DataType, AllowedType)
                error('ADCMeta:UnknownDataType', ...
                    'DataType "%s" is not supported.', obj.DataType);
            end
        end
     
        %% Getter for the value of the parameter
        function GetStoredValue = get.Value(obj)
             GetStoredValue = obj.StoredValue;
        end
         
        %% Setter for the value of the parameter
        function set.Value(obj, newValue)
            if isscalar(newValue) && isnumeric(newValue) && isnan(newValue)
                obj.StoredValue = newValue;
                return;
            end
            
            CastedValue = obj.ValidateDataType(newValue); 
            obj.validateInput(CastedValue);  
            obj.StoredValue = CastedValue;
        end
    end

    methods (Access = private)
        %% Custom User-Defined Property Validator
        function validateInput(obj, val)
            try
                obj.Validator(val);
            catch ME
                newME = MException('ADCMeta:ValidationFailed', ...
                    'Validation failed for parameter "%s": %s', ...
                    obj.Name, ME.message);
                throwAsCaller(newME);
            end
        end

        %% DataType Typecasting and Enforcement
        function ValidatedData = ValidateDataType(obj, data)
           if islogical(data) || ischar(data) || isstring(data)
               error('ADCMeta:BadType', ...
                   "%s cannot accept logical or text types.", obj.Name);
           end
           
           if ~isscalar(data)
               error('ADCMeta:BadType', ...
                   '"%s" must be a scalar value.', obj.Name);
           end

           %% Automatic Conversion to Fixed-Point Data
           if obj.DataType == "fi" || obj.DataType == "embedded.fi"
               try
                   if isa(data, 'embedded.fi')
                       ValidatedData = data;
                   else
                        ValidatedData = fi(data);
                   end
                   return; 
               catch ME
                   error('ADCMeta:BadType', ...
                       "%s conversion to fixed-point 'fi' failed: %s", ...
                       obj.Name, ME.message);
               end
           end
           
           %% Automatic Conversion to Floating-Point or Integers
           try
                ValidatedData = cast(data, char(obj.DataType));
           catch ME
               error('ADCMeta:BadType', ...
                   "%s cannot be converted to type %s: %s", ...
                   obj.Name, obj.DataType, ME.message);
           end
        end
    end
end
