classdef TestADC < matlab.unittest.TestCase
    %% ==================================
    %% UNIT TEST SUITE FOR THE ADC CLASS
    %% ==================================

    methods (Test)

        function testConstructorStoresParametersObject(testCase)
            %% Validates Constructor Stores Parameters Handle

            P = testCase.createDefaultParameters();
            A = ADC(P);

            testCase.verifySameHandle(A.ADCParameters, P);
        end

        function testSamplerDownsamplesToADCRate(testCase)
            %% Validates ADC Sampling Selects Samples at Fs/DF
            P = testCase.createDefaultParameters();
            A = ADC(P);

            Fs = P.getValue("Fs");  % High-rate simulation frequency
            DF = P.getValue("DF");  % ADC sampling factor

            N = 13;

            % Row-vector input also validates column-vector conversion.
            x = 10 * (1:N);

            [y, SampleIndex, ADCSamplingFrequency] = A.Sampler(x);

            expectedLocalIndex = (1:DF:N)';
            expectedIndex = (0:DF:N-1)';

            expectedOutput = x(expectedLocalIndex);
            expectedOutput = expectedOutput(:);

            expectedADCSamplingFrequency = Fs / DF;

            testCase.verifySize(y, [numel(expectedIndex), 1]);
            testCase.verifySize( ...
            SampleIndex, [numel(expectedIndex), 1]);

            testCase.verifyEqual(y, expectedOutput);
            testCase.verifyEqual(SampleIndex, expectedIndex);

            testCase.verifyEqual( ...
            ADCSamplingFrequency, ...
            expectedADCSamplingFrequency);
            testCase.verifyEqual(A.InputSamplesProcessed, N);
            testCase.verifyEqual( ...
                A.OutputSamplesProduced, numel(expectedIndex));
            testCase.verifyEqual(A.FramesProcessed, 1);
        end

        function testSamplerPhasePersistsAcrossFrameBoundaries(testCase)
            %% Validates a New Frame Does Not Restart ADC Sample Phase

            P = testCase.createDefaultParameters();
            A = ADC(P);

            [FirstOutput, FirstIndex] = ...
                A.Sampler((10:14)');
            [SecondOutput, SecondIndex] = ...
                A.Sampler((15:18)');

            % Frame one contains global indices 0:4. Frame two starts at
            % global index 5, so its first ADC sample is global index 8.
            testCase.verifyEqual(FirstOutput, [10; 14]);
            testCase.verifyEqual(FirstIndex, [0; 4]);
            testCase.verifyEqual(SecondOutput, 18);
            testCase.verifyEqual(SecondIndex, 8);

            testCase.verifyEqual(A.InputSamplesProcessed, 9);
            testCase.verifyEqual(A.OutputSamplesProduced, 3);
            testCase.verifyEqual(A.FramesProcessed, 2);
        end

        function testSamplerFramesMatchWholeVectorReference(testCase)
            %% Validates Downsampling Is Independent of Frame Partitioning

            P = testCase.createDefaultParameters();
            DF = P.getValue("DF");
            N = 53;
            InputSignal = ...
                sin(0.13 * (0:N-1)') + 0.01 * (0:N-1)';

            WholeVectorADC = ADC(P);
            [ExpectedOutput, ExpectedIndex, ExpectedFrequency] = ...
                WholeVectorADC.Sampler(InputSignal);

            FrameADC = ADC(P);
            FrameLengths = [5, 11, 2, 17, 18];
            [ActualOutput, ActualIndex, ActualFrequency] = ...
                testCase.processSamplerInFrames( ...
                    FrameADC, InputSignal, FrameLengths);

            ExplicitIndex = (0:DF:N-1)';
            ExplicitOutput = InputSignal(ExplicitIndex + 1);

            testCase.verifyEqual(ExpectedOutput, ExplicitOutput, ...
                "AbsTol", 1e-12);
            testCase.verifyEqual(ExpectedIndex, ExplicitIndex);
            testCase.verifyEqual(ActualOutput, ExpectedOutput, ...
                "AbsTol", 1e-12);
            testCase.verifyEqual(ActualIndex, ExpectedIndex);
            testCase.verifyEqual( ...
                ActualFrequency, ExpectedFrequency);

            testCase.verifyEqual(FrameADC.InputSamplesProcessed, N);
            testCase.verifyEqual( ...
                FrameADC.OutputSamplesProduced, numel(ExplicitIndex));
            testCase.verifyEqual( ...
                FrameADC.FramesProcessed, numel(FrameLengths));
        end

        function testSamplerFrameWithNoOutputStillAdvancesPhase(testCase)
            %% Validates Short Frames Without a Sample Still Consume Input

            P = testCase.createDefaultParameters();
            A = ADC(P);

            [FirstOutput, FirstIndex] = A.Sampler(1);
            [EmptyOutput, EmptyIndex] = A.Sampler([2; 3]);

            testCase.verifyEqual(FirstOutput, 1);
            testCase.verifyEqual(FirstIndex, 0);
            testCase.verifySize(EmptyOutput, [0, 1]);
            testCase.verifySize(EmptyIndex, [0, 1]);
            testCase.verifyEqual(A.InputSamplesProcessed, 3);
            testCase.verifyEqual(A.OutputSamplesProduced, 1);
            testCase.verifyEqual(A.FramesProcessed, 2);

            [NextOutput, NextIndex] = A.Sampler([4; 5]);

            testCase.verifyEqual(NextOutput, 5);
            testCase.verifyEqual(NextIndex, 4);
        end

        function testResetSamplerRestoresInitialPhase(testCase)
            %% Validates Reset Restarts Sampling at Global Index Zero

            P = testCase.createDefaultParameters();
            ResetADC = ADC(P);
            FreshADC = ADC(P);

            ResetADC.Sampler((1:7)');
            ResetADC.ResetSampler();

            testCase.verifyEqual(ResetADC.InputSamplesProcessed, 0);
            testCase.verifyEqual(ResetADC.OutputSamplesProduced, 0);
            testCase.verifyEqual(ResetADC.FramesProcessed, 0);

            InputFrame = (101:115)';
            [ResetOutput, ResetIndex, ResetFrequency] = ...
                ResetADC.Sampler(InputFrame);
            [FreshOutput, FreshIndex, FreshFrequency] = ...
                FreshADC.Sampler(InputFrame);

            testCase.verifyEqual(ResetOutput, FreshOutput);
            testCase.verifyEqual(ResetIndex, FreshIndex);
            testCase.verifyEqual(ResetFrequency, FreshFrequency);
        end

        function testEmptySamplerFrameDoesNotChangeState(testCase)
            %% Validates an Empty End-of-Stream Frame Is State-Neutral

            P = testCase.createDefaultParameters();
            A = ADC(P);
            A.Sampler((1:6)');

            StateBeforeEmptyFrame = [ ...
                A.InputSamplesProcessed, ...
                A.OutputSamplesProduced, ...
                A.FramesProcessed];

            [OutputFrame, SampleIndex, ADCSamplingFrequency] = ...
                A.Sampler(zeros(0, 1));

            StateAfterEmptyFrame = [ ...
                A.InputSamplesProcessed, ...
                A.OutputSamplesProduced, ...
                A.FramesProcessed];

            testCase.verifySize(OutputFrame, [0, 1]);
            testCase.verifySize(SampleIndex, [0, 1]);
            testCase.verifyEqual( ...
                ADCSamplingFrequency, ...
                P.getValue("Fs") / P.getValue("DF"));
            testCase.verifyEqual( ...
                StateAfterEmptyFrame, StateBeforeEmptyFrame);
        end

        function testInvalidSamplerFrameInputIsRejected(testCase)
            %% Validates Sampler Input Must Be a Finite Real Vector

            P = testCase.createDefaultParameters();
            A = ADC(P);
            InvalidFrames = { ...
                ones(2, 2), [1; NaN], [1; Inf], [1; 1i]};

            for k = 1:numel(InvalidFrames)
                InvalidFrame = InvalidFrames{k};
                testCase.verifyError( ...
                    @() A.Sampler(InvalidFrame), ...
                    'ADC:InvalidSamplerFrame');
            end

            testCase.verifyEqual(A.InputSamplesProcessed, 0);
            testCase.verifyEqual(A.OutputSamplesProduced, 0);
            testCase.verifyEqual(A.FramesProcessed, 0);
        end

        function testSamplerRejectsUnassignedDownsamplingFactor(testCase)
            %% Validates Sampler Cannot Run Until DF Is Assigned

            P = ADCParameters();
            P.setValue("Fs", 48000);
            A = ADC(P);

            testCase.verifyError( ...
                @() A.Sampler(1), ...
                'ADC:InvalidDownsamplingFactor');

            testCase.verifyEqual(A.InputSamplesProcessed, 0);
            testCase.verifyEqual(A.OutputSamplesProduced, 0);
            testCase.verifyEqual(A.FramesProcessed, 0);
        end

        function testMidtreadUsesCompleteCodebook(testCase)
            %% Validates Midtread Reconstruction Levels and Indices

            P = testCase.createDefaultParameters();
            A = ADC(P);

            Vfs = P.getValue("Vfs");
            NumBits = P.getValue("NumBits");

            Delta = Vfs / 2^NumBits;

            expectedIndices = (0:2^NumBits-1)';
            expectedLevels = ...
                -(Vfs/2) + expectedIndices * Delta;

            % Row-vector input also validates column-vector conversion.
            x = expectedLevels';

            [y, Indices, Error] = A.Midtread(x);

            testCase.verifySize(y, [2^NumBits 1]);
            testCase.verifySize(Indices, [2^NumBits 1]);
            testCase.verifySize(Error, [2^NumBits 1]);

            testCase.verifyEqual(y, expectedLevels, ...
                "AbsTol", 1e-12);

            testCase.verifyEqual(Indices, expectedIndices);

            testCase.verifyEqual(Error, zeros(size(expectedLevels)), ...
                "AbsTol", 1e-12);

            % Confirms every available N-bit code is represented.
            testCase.verifyEqual(numel(unique(Indices)), 2^NumBits);

            % Midtread must contain a zero reconstruction level.
            testCase.verifyTrue(any(abs(y) < 1e-12));
        end

        function testMidtreadHasAsymmetricEndpointLevels(testCase)
            %% Validates Asymmetric Midtread Endpoints for N-Bit Coding

            P = testCase.createDefaultParameters();
            A = ADC(P);

            Vfs = P.getValue("Vfs");
            NumBits = P.getValue("NumBits");

            Delta = Vfs / 2^NumBits;
            expectedLevels = ...
                -(Vfs/2) + (0:2^NumBits-1)' * Delta;

            [y, ~, ~] = A.Midtread(expectedLevels);

            % Full negative endpoint is represented.
            testCase.verifyEqual(y(1), -(Vfs/2), ...
                "AbsTol", 1e-12);

            % Positive endpoint is one LSB below positive full scale.
            testCase.verifyEqual(y(end), (Vfs/2)-Delta, ...
                "AbsTol", 1e-12);
        end

        function testMidtreadClipsOutOfRangeInputs(testCase)
            %% Validates Midtread Saturation at Minimum and Maximum Codes

            P = testCase.createDefaultParameters();
            A = ADC(P);

            x = [
                -10
                -4
                -3.6
                 0
                 3.4
                 4
                10
            ];

            [y, Indices, Error] = A.Midtread(x);

            expectedOutput = [
                -4
                -4
                -4
                 0
                 3
                 3
                 3
            ];

            expectedIndices = [
                0
                0
                0
                4
                7
                7
                7
            ];

            testCase.verifyEqual(y, expectedOutput, ...
                "AbsTol", 1e-12);

            testCase.verifyEqual(Indices, expectedIndices);

            testCase.verifyEqual(Error, y-x, ...
                "AbsTol", 1e-12);
        end

        function testMidtreadGranularErrorDoesNotExceedHalfLSB(testCase)
            %% Validates Midtread Error Inside Non-Overload Region

            P = testCase.createDefaultParameters();
            A = ADC(P);

            Vfs = P.getValue("Vfs");
            NumBits = P.getValue("NumBits");

            Delta = Vfs / 2^NumBits;

            % Excludes the upper overload region above the final threshold.
            x = linspace(-(Vfs/2), (Vfs/2)-(Delta/2), 1001)';

            [~, ~, Error] = A.Midtread(x);

            testCase.verifyLessThanOrEqual ...
            (max(abs(Error)), (Delta/2)+1e-12);
        end

        function testMidriseUsesCompleteCodebook(testCase)
            %% Validates Midrise Half-LSB Levels and Indices

            P = testCase.createDefaultParameters();
            A = ADC(P);

            Vfs = P.getValue("Vfs");
            NumBits = P.getValue("NumBits");

            Delta = Vfs / 2^NumBits;

            expectedIndices = (0:2^NumBits-1)';
            expectedLevels = ...
                -(Vfs/2) + (expectedIndices+0.5) * Delta;

            [y, Indices, Error] = A.Midrise(expectedLevels);

            testCase.verifySize(y, [2^NumBits 1]);
            testCase.verifySize(Indices, [2^NumBits 1]);
            testCase.verifySize(Error, [2^NumBits 1]);

            testCase.verifyEqual(y, expectedLevels, ...
                "AbsTol", 1e-12);

            testCase.verifyEqual(Indices, expectedIndices);

            testCase.verifyEqual(Error, zeros(size(expectedLevels)), ...
                "AbsTol", 1e-12);

            % Midrise has no zero reconstruction level.
            testCase.verifyFalse(any(abs(y) < 1e-12));

            testCase.verifyEqual(numel(unique(Indices)), 2^NumBits);
        end

        function testMidriseClipsOutOfRangeInputs(testCase)
            %% Validates Midrise Saturation at Endpoint Levels

            P = testCase.createDefaultParameters();
            A = ADC(P);

            x = [
                -10
                -4
                -3.5
                 0
                 3.5
                 4
                10
            ];

            [y, Indices, Error] = A.Midrise(x);

            expectedOutput = [
                -3.5
                -3.5
                -3.5
                 0.5
                 3.5
                 3.5
                 3.5
            ];

            expectedIndices = [
                0
                0
                0
                4
                7
                7
                7
            ];

            testCase.verifyEqual(y, expectedOutput, ...
                "AbsTol", 1e-12);

            testCase.verifyEqual(Indices, expectedIndices);

            testCase.verifyEqual(Error, y-x, ...
                "AbsTol", 1e-12);
        end

        function testMidriseGranularErrorDoesNotExceedHalfLSB(testCase)
            %% Validates Midrise Error Across Nominal Input Range

            P = testCase.createDefaultParameters();
            A = ADC(P);

            Vfs = P.getValue("Vfs");
            NumBits = P.getValue("NumBits");

            Delta = Vfs / 2^NumBits;

            x = linspace(-(Vfs/2), Vfs/2, 1001)';

            [~, ~, Error] = A.Midrise(x);

            testCase.verifyLessThanOrEqual ...
            (max(abs(Error)), (Delta/2)+1e-12);
        end
    end

    methods (Access = private)

        function P = createDefaultParameters(testCase)
            %% Creates Default Parameters Object For ADC Unit Tests

            P = ADCParameters();

            P.setValue("Fs", 48000);
            P.setValue("Vfs", 8.0);
            P.setValue("NumBits", 3);
            P.setValue("DF", 4);

            % Confirm required parameters are valid and readable.
            testCase.verifyEqual(P.getValue("Fs"), 48000);
            testCase.verifyEqual(P.getValue("Vfs"), 8.0);
            testCase.verifyEqual(P.getValue("NumBits"), 3);
            testCase.verifyEqual(P.getValue("DF"), 4);
        end

        function [Output, SampleIndex, ADCSamplingFrequency] = ...
                processSamplerInFrames( ...
                    testCase, A, InputSignal, FrameLengths)
            %% Processes a Complete Signal Using One Frame Partition

            if sum(FrameLengths) ~= numel(InputSignal)
                error('TestADC:FrameLengthMismatch', ...
                    ['The frame lengths must contain every input ', ...
                     'sample exactly once.']);
            end

            Output = zeros(0, 1);
            SampleIndex = zeros(0, 1);
            ADCSamplingFrequency = NaN;
            StartIndex = 1;

            for k = 1:numel(FrameLengths)
                EndIndex = StartIndex + FrameLengths(k) - 1;
                InputFrame = InputSignal(StartIndex:EndIndex);

                [OutputFrame, IndexFrame, FrameFrequency] = ...
                    A.Sampler(InputFrame);

                Output = [Output; OutputFrame]; %#ok<AGROW>
                SampleIndex = ...
                    [SampleIndex; IndexFrame]; %#ok<AGROW>

                if isnan(ADCSamplingFrequency)
                    ADCSamplingFrequency = FrameFrequency;
                else
                    testCase.verifyEqual( ...
                        FrameFrequency, ADCSamplingFrequency);
                end

                StartIndex = EndIndex + 1;
            end
        end

        function P = createSignalChainParameters(testCase)
            %% Creates Parameters for the Chain Through ADC Downsampling

            P = testCase.createDefaultParameters();

            % A 31-sample frame is intentionally not divisible by DF = 4.
            P.setValue("Fs", 20000);
            P.setValue("FrameLength", 31);
            P.setValue("Dur", 0.005);
            P.setValue("DF", 4);

            % Signal-generator parameters.
            P.setValue("Aburst", 0.5);
            P.setValue("mu", 0.0015);
            P.setValue("Sigma", 0.0005);
            P.setValue("Ad", 1.0);
            P.setValue("Lambda", 300);
            P.setValue("EST", 0.003);
            P.setValue("FData", 500);
            P.setValue("An", 0.1);
            P.setValue("Fnoise", 7000);
            P.setValue("Anf", 1e-3);
            P.setValue("DC", 0.25);

            % Shared ADCFilter HPF and LPF parameters.
            P.setValue("FcHigh", 20);
            % ADC rate is 5 kHz, so the anti-alias cutoff stays below its
            % 2.5 kHz Nyquist frequency.
            P.setValue("FcLow", 2000);
            P.setValue("nHpf", 4);
            P.setValue("nLpf", 6);

            % AGC and quantizer full-scale parameters.
            P.setValue("Vfs", 1.0);
            P.setValue("EnvAttack", 0.005);
            P.setValue("EnvRelease", 0.020);
            P.setValue("GainAttack", 0.005);
            P.setValue("GainRelease", 0.020);
            P.setValue("GateAttack", 0.005);
            P.setValue("GateRelease", 0.020);
        end
    end
end
