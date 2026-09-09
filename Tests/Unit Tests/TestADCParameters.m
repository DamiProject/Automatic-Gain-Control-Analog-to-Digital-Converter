classdef TestADCParameters < matlab.unittest.TestCase
    %% ===================================================
    %% UNIT TEST SUITE FOR THE PARAMETERS CONTAINER CLASS
    %% ===================================================

    methods (Test)

        function testConstructorCreatesParameters(testCase)
            %% Validates Constructor Creates Expected Parameters
            P = ADCParameters();

            testCase.verifyClass(P.getADCMeta("Fs"), "ADCMeta");
            testCase.verifyClass(P.getADCMeta("FData"), "ADCMeta");
            testCase.verifyClass(P.getADCMeta("FrameLength"), "ADCMeta");
        end

        function testGetValueReturnsAssignedValue(testCase)
            %% Validates getValue Returns Stored Parameter Value
            P = ADCParameters();

            P.setValue("Fs", 1e6);

            testCase.verifyEqual(P.getValue("Fs"), 1e6);
        end

        function testSetValueUpdatesValue(testCase)
            %% Validates setValue Updates Existing Parameter Values
            P = ADCParameters();

            P.setValue("Fs", 10);
            P.setValue("Fs", 25);

            testCase.verifyEqual(P.getValue("Fs"), 25);
        end

        function testGetMetaReturnsCorrectMetadata(testCase)
            %% Validates getMeta Returns Correct Metadata
            P = ADCParameters();

            FsMeta = P.getADCMeta("Fs");

            testCase.verifyEqual(FsMeta.Name, "Oversampling Frequency");
            testCase.verifyEqual(FsMeta.Unit, "Hz");
        end

        function testFrameLengthStoresPositiveIntegerSamples(testCase)
            %% Validates The Frame Length Nf Can Be Configured Centrally
            P = ADCParameters();

            P.setValue("FrameLength", 1024);
            FrameLengthMeta = P.getADCMeta("FrameLength");

            testCase.verifyEqual(P.getValue("FrameLength"), 1024);
            testCase.verifyEqual(FrameLengthMeta.Name, "Frame Length");
            testCase.verifyEqual(FrameLengthMeta.Unit, "Samples");
        end

        function testFrameLengthRejectsInvalidValues(testCase)
            %% Validates Nf Must Be A Finite Positive Integer
            InvalidFrameLengths = {0, -1, 2.5, Inf};

            for k = 1:numel(InvalidFrameLengths)
                P = ADCParameters();
                InvalidFrameLength = InvalidFrameLengths{k};

                testCase.verifyError( ...
                    @() P.setValue( ...
                        "FrameLength", InvalidFrameLength), ...
                    'ADCMeta:ValidationFailed');
            end
        end

        function testUnknownKeyThrowsOnGetValue(testCase)
            %% Validates getValue Rejects Unknown Keys
            P = ADCParameters();

            fh = @() P.getValue("WrongKey");

            testCase.verifyError(fh, 'Parameters:UnknownKey');
        end

        function testUnknownKeyThrowsOnSetValue(testCase)
            %% Validates setValue Rejects Unknown Keys
            P = ADCParameters();

            fh = @() P.setValue("WrongKey", 10);

            testCase.verifyError(fh, 'Parameters:UnknownKey');
        end

        function testUnknownKeyThrowsOnGetMeta(testCase)
            %% Validates getMeta Rejects Unknown Keys
            P = ADCParameters();

            fh = @() P.getADCMeta("WrongKey");

            testCase.verifyError(fh, 'Parameters:UnknownKey');
        end

        function testSetValueUsesMetaValidation(testCase)
            %% Validates Parameter Validation Is Enforced
            P = ADCParameters();

            fh = @() P.setValue("Fs", -1);

            testCase.verifyError(fh, 'ADCMeta:ValidationFailed');
        end

        function testDefaultValueIsNaN(testCase)
            %% Validates Parameters Start Unassigned
            P = ADCParameters();

            testCase.verifyTrue(isnan(P.getValue("Fs")));
        end
    end
end
