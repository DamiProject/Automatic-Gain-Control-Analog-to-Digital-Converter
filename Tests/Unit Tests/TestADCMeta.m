classdef TestADCMeta < matlab.unittest.TestCase
  %% ===================================================================
  %% UNIT TEST SUITE FOR THE ANALOG-TO-DIGITAL-CONVERTER (ADC) METADATA
  %% ===================================================================
    
    properties (TestParameter)
        %% Acceptable Datatypes Under Validation Loop
        AllowedDataType = {'double', 'single', ...
                           'int8', 'int16', 'int32', 'int64', ...
                           'uint8', 'uint16', 'uint32', 'uint64', ...
                           'fi', 'embedded.fi'};
    end

    methods (Test)
        %% ===============================
        %% CORE METADATA FUNCTIONAL TESTS
        %% ===============================

        function testConstructorRejectsInvalidName(testCase)
            %% Validates Name Must Be String Or Character Vector
            fh = @() ADCMeta(123, @mustBeNumeric, "double", "V");

            testCase.verifyError(fh, 'ADCMeta:BadName');
        end

        function testUnknownDataTypeThrows(testCase)
            %% Validates Unsupported Datatypes Are Rejected
            fh = @() ADCMeta("Gain", @mustBeNumeric, ...
                "complex128", "V");

            testCase.verifyError(fh, 'ADCMeta:UnknownDataType');
        end

        function testValueInitiallyNaN(testCase)
           %% Validates Initial Value Is NaN
            mParam = ADCMeta("Gain", @mustBeNumeric, "double", "V");
            testCase.verifyTrue(isnan(mParam.Value));
        end

        function testTypeFailureDoesNotCorrupt(testCase)
        %% Validates Failed Type Conversion Leaves Existing Value Untouched
            mParam = ADCMeta("Gain", @mustBeNumeric, "double", "V");

            %% Assign Initial Valid Value
            testCase.assignValue(mParam, 25);

            %% Attempt Invalid Assignment
            fh = @() testCase.assignValue(mParam, "abc");

            testCase.verifyError(fh, 'ADCMeta:BadType');

            %% Verify Original Value Is Preserved
            testCase.verifyEqual(mParam.Value, 25);
        end

        function testZeroRejectedByPositiveValidator(testCase)
            %% Validates mustBePositive Rejects Zero
            mPos = ADCMeta("Scale", @mustBePositive, "double", "V");

            fh = @() testCase.assignValue(mPos, 0);

            testCase.verifyError(fh, 'ADCMeta:ValidationFailed');
        end

        function testValidAssignment(testCase)
            %% Validates Successful Storage of Valid Numeric Value
            validatorRange = @(x) (mustBeNumeric(x));
            mGain = ADCMeta("Gain", validatorRange, "double", "V");
            testCase.assignValue(mGain, 1e5);
            testCase.verifyEqual(mGain.Value, 1e5);
        end

        function testNaNSemantics(testCase)
            %% Validates NaN as a valid Default Value
            validatorRange = @(x) (mustBeNumeric(x));
            mGain = ADCMeta("Gain", validatorRange, "double", "V");
            testCase.assignValue(mGain, NaN);
            testCase.verifyTrue(isnan(mGain.Value));
        end

        function testTypeMismatchThrows(testCase)
            %% Validates Accepted Datatype Are Numeric and not Words
            mOffset = ADCMeta("Offset", @mustBeNumeric, "double", "V");
            fhText = @() testCase.assignValue(mOffset, "Number");
            testCase.verifyError(fhText, 'ADCMeta:BadType');
         %% Validates Accepted Datatype Are Numeric and not Logical Values
            fhLogical = @() testCase.assignValue(mOffset, true);
            testCase.verifyError(fhLogical, 'ADCMeta:BadType');
        end
         
        %% Checks if the Class Can Convert Values To Any Allowed Data Types
        function testAllowedTypesAcceptDoubleInputs ...
            (testCase, AllowedDataType)
           %% Skip Test If the Fixed-Point Toolbox Is Not Installed
            if (strcmp(AllowedDataType, 'fi') ...
                    || strcmp(AllowedDataType, 'embedded.fi')) && ...
                    ~digitalsignalsinstalled()
                return; 
            end

            mParam = ADCMeta ...
            ("TestParam", @mustBeNumeric, AllowedDataType, "V");
            testCase.assignValue(mParam, 42);
            
            checkType = AllowedDataType;
            if strcmp(checkType, 'fi')
                checkType = 'embedded.fi';
            end
            %% Validates Stored Value Is In The Correct Data Type Format
            testCase.verifyTrue(isa(mParam.Value, checkType));

            %% Validate Intended Value Is Stored Correctly
            testCase.verifyEqual(double(mParam.Value), 42);
        end
        %% Validates Acceptance Of Fixed-Point Data
        function testDirectFixedPointStorage(testCase)
            %% Skip Test If the Fixed-Point Toolbox Is Not Installed
            if ~digitalsignalsinstalled()
                return; 
            end

            mParam = ADCMeta("CustomFi", @mustBeNumeric, "embedded.fi", "V");

            %% Create a specific fixed-point object -
            %% (e.g., 16-bit word length, 12-bit fraction length)
            customFiValue = fi(3.1415, 1, 16, 12);
            testCase.assignValue(mParam, customFiValue);

            %% Verify it stored the object exactly as-is without  -
            %% losing the custom word length
            testCase.verifyEqual(mParam.Value, customFiValue);
            testCase.verifyEqual(mParam.Value.WordLength, 16);
        end

        %% Validates Metadata Validator Is Always A Function Handle
        function testConstructorRejectsInvalidValidator(testCase)
            fh = @() ADCMeta("X", 123, "double", "V");
            testCase.verifyError(fh, 'ADCMeta:BadValidator');
        end
       
        %% Validates Metadata Validator Rules Is Followed
        function testMustBePositiveValidator(testCase)
            mPos = ADCMeta("Scale", @mustBePositive, "double", "V");
            testCase.assignValue(mPos, 5);
            testCase.verifyEqual(mPos.Value, 5);
            fh = @() testCase.assignValue(mPos, -1);
            testCase.verifyError(fh, 'ADCMeta:ValidationFailed');
        end

    %% Verify that a failed validation does NOT corrupt the existing value
        function testFailedAssignmentDoesNotCorrupt(testCase)
            mParam = ADCMeta("Limit", @mustBePositive, "double", "V");
            %% Set initial valid value
            testCase.assignValue(mParam, 50); 
            
            %% Attempt An Invalid Assignment That Throws An Error
            fh = @() testCase.assignValue(mParam, -10);
            testCase.verifyError(fh, 'ADCMeta:ValidationFailed');
            
            %% Validates Stored Value Was Safely Untouched
            testCase.verifyEqual(mParam.Value, 50);
        end

        %% Test Behavior When Integers Saturate/Overflow
        function testOverflowBehavior(testCase)
            mInt = ADCMeta("Threshold", @mustBeNumeric, "int8", "V");
            %% 300 Exceeds int8 Maximum Capacity (127)
            testCase.assignValue(mInt, 300);
            
         %% Confirm It Successfully Saturated To 127 Instead of Blowing Up
            testCase.verifyEqual(mInt.Value, int8(127));
        end

        %% Validates Test Array/Vector Parameters Not Allowed 
        function testVectorSupport(testCase)
            mScalar = ADCMeta("CalMatrix", @mustBeNumeric, "double", "V");
           fh = @() testCase.assignValue(mScalar, [10, 20, 30]);
            testCase.verifyError(fh, 'ADCMeta:BadType');
        end
        function testOmittedUnitSemantics(testCase)
            %% Validates Unit Argument Can Be Safely Omitted Entirely
            testCase.verifyWarningFree(@() ...
                ADCMeta("Voltage", @mustBeNumeric, "double"));

            mOmitted = ADCMeta("Voltage", @mustBeNumeric, "double");
            %% Confirm The Omitted Value Correctly Defaults To Missing
            testCase.verifyTrue(ismissing(mOmitted.Unit));
        end

        function testExplicitEmptyStringUnitThrows(testCase)
           %% Validates Passing An Explicit Empty String "" Throws An Error
            fhEmptyString = @() ...
            ADCMeta("Voltage", @mustBeNumeric, "double", "");
            testCase.verifyError(fhEmptyString, 'ADCMeta:EmptyUnit');
        end

        function testExplicitEmptyArrayUnitThrows(testCase)
          %% Validates Passing An Explicit Empty Matrix [] Throws An Error
            fhEmptyArray = @()...
                ADCMeta("Voltage", @mustBeNumeric, "double", []);
            testCase.verifyError(fhEmptyArray, 'ADCMeta:EmptyUnit');
        end
    end


    methods (Access = private)
        %% Allows For Safe changes of the Parameter Value During Tests
        function assignValue(~, metaObj, val)
            metaObj.Value = val;
        end
    end
end

%% Checks if the Fixed-Point Toolbox is installed on this computer
function tf = digitalsignalsinstalled()
    tf = ~isempty(ver('fixedpoint'));
end
