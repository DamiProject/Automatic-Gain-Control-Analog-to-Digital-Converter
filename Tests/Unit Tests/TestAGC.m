classdef TestAGC < matlab.unittest.TestCase
    %% ==================================
    %% UNIT TEST SUITE FOR THE AGC CLASS
    %% ==================================

    methods (Test)

        function testConstructorStoresParametersObject(testCase)
            %% Validates Constructor Stores Parameters Handle

            P = testCase.createDefaultParameters();
            A = AGC(P);

            testCase.verifySameHandle(A.ADCParameters, P);
        end

        function testOutputTimeAndHistoryHaveCorrectSize(testCase)
            %% Validates Output, Time Vector, and History Signal Sizes

            P = testCase.createDefaultParameters();
            A = AGC(P);

            Fs = P.getValue("Fs");
            N = 1000;
            tExpected = (0:N-1)' / Fs;

            x = 0.2 * sin(2*pi*20*tExpected);

            [y, t, History] = A.GainControl(x);

            testCase.verifySize(y, [N 1]);
            testCase.verifySize(t, [N 1]);
            testCase.verifyEqual(t, tExpected, "AbsTol", 1e-12);

            testCase.verifySize(History.Gain, [N 1]);
            testCase.verifySize(History.GateGain, [N 1]);
            testCase.verifySize(History.EffectiveGain, [N 1]);
            testCase.verifySize(History.Envelope, [N 1]);
            testCase.verifySize(History.ProjectedEnvelope, [N 1]);
            testCase.verifySize(History.AGCSignal, [N 1]);
            testCase.verifySize(History.SampleIndex, [N 1]);
            testCase.verifyEqual(History.SampleIndex, (0:N-1)');

            testCase.verifyTrue(all(isfinite(y)));
            testCase.verifyTrue(all(isfinite(History.Gain)));
            testCase.verifyTrue(all(isfinite(History.GateGain)));
            testCase.verifyTrue(all(isfinite(History.EffectiveGain)));
            testCase.verifyTrue(all(isfinite(History.Envelope)));
            testCase.verifyTrue(all(isfinite(History.ProjectedEnvelope)));
            testCase.verifyTrue(all(isfinite(History.AGCSignal)));
            testCase.verifyEqual(A.SamplesProcessed, N);
            testCase.verifyEqual(A.FramesProcessed, 1);
        end

        function testSilentInputClosesNoiseGate(testCase)
            %% Validates Noise Gate Decays Toward Closed
            %% State During Silence

            P = testCase.createDefaultParameters();
            A = AGC(P);

            N = 1000;
            x = zeros(N, 1);

            [y, ~, History] = A.GainControl(x);

            testCase.verifyEqual(y, zeros(N, 1), "AbsTol", 1e-12);

            % Gate should decay from its initial open value toward zero.
            testCase.verifyLessThan ...
            (History.GateGain(end), History.GateGain(1));

            % Gate gain must remain inside valid gate range.
            testCase.verifyGreaterThanOrEqual(min(History.GateGain), 0);
            testCase.verifyLessThanOrEqual(max(History.GateGain), 1);
        end

        function testLargeActiveSignalReducesAGCGain(testCase)
            %% Validates AGC Reduces Gain When Projected
            %% Envelope Is Too High

            P = testCase.createDefaultParameters();
            A = AGC(P);

            N = 1500;

            % Large active signal should exceed upper AGC limit.
            x = 2.0 * ones(N, 1);

            [~, ~, History] = A.GainControl(x);

            % Gain should reduce below initial gain of 1.0.
            testCase.verifyLessThan(History.Gain(end), 1.0);

            % Gain must remain inside AGC gain bounds.
            testCase.verifyGreaterThanOrEqual(min(History.Gain), 0.1);
            testCase.verifyLessThanOrEqual(max(History.Gain), 10.0);
        end

        function testSmallActiveSignalIncreasesAGCGain(testCase)
            %% Validates AGC Increases Gain When
            %% Projected Envelope Is Too Low

            P = testCase.createDefaultParameters();
            A = AGC(P);

            N = 1500;

            % Small but active signal: above noise threshold, below
            % lower AGC limit.
            x = 0.02 * ones(N, 1);

            [~, ~, History] = A.GainControl(x);

            % Gain should increase above initial gain of 1.0.
            testCase.verifyGreaterThan(History.Gain(end), 1.0);

            % Gain must remain inside AGC gain bounds.
            testCase.verifyGreaterThanOrEqual(min(History.Gain), 0.1);
            testCase.verifyLessThanOrEqual(max(History.Gain), 10.0);
        end

        function testOutputEqualsInputTimesEffectiveGain(testCase)
            %% Validates Final Output, Uses Combined AGC Gain and Gate Gain

            P = testCase.createDefaultParameters();
            A = AGC(P);

            Fs = P.getValue("Fs");
            N = 1000;
            t = (0:N-1)' / Fs;

            x = 0.5 * sin(2*pi*30*t);

            [y, ~, History] = A.GainControl(x);

            expectedOutput = x .* History.EffectiveGain;

            testCase.verifyEqual(y, expectedOutput, "AbsTol", 1e-12);
        end

        function testEffectiveGainEqualsGainTimesGateGain(testCase)
            %% Validates Effective Gain Is AGC Gain Multiplied By Gate Gain

            P = testCase.createDefaultParameters();
            A = AGC(P);

            Fs = P.getValue("Fs");
            N = 1000;
            t = (0:N-1)' / Fs;

            x = 0.3 * sin(2*pi*50*t);

            [~, ~, History] = A.GainControl(x);

            expectedEffectiveGain = History.Gain .* History.GateGain;

            testCase.verifyEqual ...
            (History.EffectiveGain, expectedEffectiveGain, ...
                "AbsTol", 1e-12);
        end

        function testAGCSignalEqualsInputTimesGain(testCase)
            %% Validates AGCSignal Stores Signal Before Noise Gate

            P = testCase.createDefaultParameters();
            A = AGC(P);

            Fs = P.getValue("Fs");
            N = 1000;
            t = (0:N-1)' / Fs;

            x = 0.4 * sin(2*pi*25*t);

            [~, ~, History] = A.GainControl(x);

            expectedAGCSignal = x .* History.Gain;

            testCase.verifyEqual(History.AGCSignal, expectedAGCSignal, ...
                "AbsTol", 1e-12);
        end

        function testResetRestoresInitialAGCState(testCase)
            %% Validates Reset Restores AGC Internal State

            P = testCase.createDefaultParameters();

            A1 = AGC(P);
            A2 = AGC(P);

            N = 1000;

            % First disturb A1 state using a large signal.
            disturbance = 2.0 * ones(N, 1);
            A1.GainControl(disturbance);

            % Reset A1.
            A1.reset();

            testCase.verifyEqual(A1.Envelope, 0.0);
            testCase.verifyEqual(A1.Gain, 1.0);
            testCase.verifyEqual(A1.GateGain, 1.0);
            testCase.verifyEqual(A1.SamplesProcessed, 0);
            testCase.verifyEqual(A1.FramesProcessed, 0);

            % Compare reset object against a fresh AGC object.
            x = 0.2 * ones(N, 1);

            [y1, t1, H1] = A1.GainControl(x);
            [y2, t2, H2] = A2.GainControl(x);

            testCase.verifyEqual(y1, y2, "AbsTol", 1e-12);
            testCase.verifyEqual(t1, t2, "AbsTol", 1e-12);

            testCase.verifyEqual(H1.Gain, H2.Gain, "AbsTol", 1e-12);
            testCase.verifyEqual ...
            (H1.GateGain, H2.GateGain, "AbsTol", 1e-12);
            testCase.verifyEqual ...
            (H1.EffectiveGain, H2.EffectiveGain, "AbsTol", 1e-12);
            testCase.verifyEqual ...
            (H1.Envelope, H2.Envelope, "AbsTol", 1e-12);
            testCase.verifyEqual ...
            (H1.ProjectedEnvelope, H2.ProjectedEnvelope, "AbsTol", 1e-12);
            testCase.verifyEqual ...
            (H1.AGCSignal, H2.AGCSignal, "AbsTol", 1e-12);
        end

        function testSuccessiveFramesUseContinuousGlobalTime(testCase)
            %% Validates Global Sample and Time Axes Continue Across Frames

            P = testCase.createDefaultParameters();
            A = AGC(P);
            Fs = P.getValue("Fs");

            [~, FirstTime, FirstHistory] = ...
                A.GainControl(0.2 * ones(7, 1));
            [~, SecondTime, SecondHistory] = ...
                A.GainControl(0.2 * ones(5, 1));

            testCase.verifyEqual( ...
                FirstHistory.SampleIndex, (0:6)');
            testCase.verifyEqual( ...
                SecondHistory.SampleIndex, (7:11)');
            testCase.verifyEqual( ...
                FirstTime, (0:6)' / Fs, "AbsTol", 1e-12);
            testCase.verifyEqual( ...
                SecondTime, (7:11)' / Fs, "AbsTol", 1e-12);
            testCase.verifyEqual(A.SamplesProcessed, 12);
            testCase.verifyEqual(A.FramesProcessed, 2);
        end

        function testFramedProcessingMatchesWholeVectorReference(testCase)
            %% Validates Frame Partitioning Does Not Change AGC Behavior

            P = testCase.createDefaultParameters();
            Fs = P.getValue("Fs");
            N = 257;
            SampleIndex = (0:N-1)';

            InputSignal = zeros(N, 1);
            InputSignal(65:128) = 0.02;
            InputSignal(129:192) = 1.2 * sin( ...
                2 * pi * 40 * SampleIndex(129:192) / Fs);
            InputSignal(193:end) = 0.1 * sin( ...
                2 * pi * 15 * SampleIndex(193:end) / Fs);

            WholeVectorAGC = AGC(P);
            [ExpectedOutput, ExpectedTime, ExpectedHistory] = ...
                WholeVectorAGC.GainControl(InputSignal);

            FrameAGC = AGC(P);
            FrameLengths = [31, 17, 64, 9, 80, 56];
            [ActualOutput, ActualTime, ActualHistory] = ...
                testCase.processInFrames( ...
                    FrameAGC, InputSignal, FrameLengths);

            testCase.verifyEqual( ...
                ActualOutput, ExpectedOutput, "AbsTol", 1e-12);
            testCase.verifyEqual( ...
                ActualTime, ExpectedTime, "AbsTol", 1e-12);
            testCase.verifyHistoryEqual( ...
                ActualHistory, ExpectedHistory);

            testCase.verifyEqual( ...
                FrameAGC.Envelope, WholeVectorAGC.Envelope, ...
                "AbsTol", 1e-12);
            testCase.verifyEqual( ...
                FrameAGC.Gain, WholeVectorAGC.Gain, ...
                "AbsTol", 1e-12);
            testCase.verifyEqual( ...
                FrameAGC.GateGain, WholeVectorAGC.GateGain, ...
                "AbsTol", 1e-12);
            testCase.verifyEqual(FrameAGC.SamplesProcessed, N);
            testCase.verifyEqual( ...
                FrameAGC.FramesProcessed, numel(FrameLengths));
        end

        function testStepAtFrameBoundaryMatchesWholeVectorReference(testCase)
            %% Validates a boundary-aligned level step adds no frame artifact

            P = testCase.createDefaultParameters();
            N = 240;
            BoundarySample = 80;

            % Silence closes the gate before a large active level begins at
            % the first sample of frame two. The AGC transient is expected;
            % only an additional frame-boundary discontinuity is forbidden.
            InputSignal = zeros(N, 1);
            InputSignal(BoundarySample + 1:end) = 0.8;

            WholeVectorAGC = AGC(P);
            [ExpectedOutput, ExpectedTime, ExpectedHistory] = ...
                WholeVectorAGC.GainControl(InputSignal);

            FrameAGC = AGC(P);
            FrameLengths = [80, 13, 47, 100];
            [ActualOutput, ActualTime, ActualHistory] = ...
                testCase.processInFrames( ...
                FrameAGC, InputSignal, FrameLengths);

            testCase.verifyEqual( ...
                ActualOutput, ExpectedOutput, "AbsTol", 1e-12);
            testCase.verifyEqual( ...
                ActualTime, ExpectedTime, "AbsTol", 1e-12);
            testCase.verifyHistoryEqual( ...
                ActualHistory, ExpectedHistory);

            % Explicitly inspect the samples around the boundary as well as
            % the complete vector comparison above.
            BoundaryRegion = BoundarySample - 1:BoundarySample + 2;
            testCase.verifyEqual( ...
                ActualOutput(BoundaryRegion), ...
                ExpectedOutput(BoundaryRegion), "AbsTol", 1e-12);

            testCase.verifyEqual( ...
                FrameAGC.Envelope, WholeVectorAGC.Envelope, ...
                "AbsTol", 1e-12);
            testCase.verifyEqual( ...
                FrameAGC.Gain, WholeVectorAGC.Gain, ...
                "AbsTol", 1e-12);
            testCase.verifyEqual( ...
                FrameAGC.GateGain, WholeVectorAGC.GateGain, ...
                "AbsTol", 1e-12);
            testCase.verifyEqual(FrameAGC.SamplesProcessed, N);
            testCase.verifyEqual( ...
                FrameAGC.FramesProcessed, numel(FrameLengths));
        end

        function testStatePropertiesMatchLastHistorySample(testCase)
            %% Validates Persisted State Equals the Last Processed Sample

            P = testCase.createDefaultParameters();
            A = AGC(P);

            [~, ~, History] = ...
                A.GainControl(0.3 * ones(40, 1));

            testCase.verifyEqual( ...
                A.Envelope, History.Envelope(end), ...
                "AbsTol", 1e-12);
            testCase.verifyEqual( ...
                A.Gain, History.Gain(end), "AbsTol", 1e-12);
            testCase.verifyEqual( ...
                A.GateGain, History.GateGain(end), ...
                "AbsTol", 1e-12);
        end

        function testEmptyFrameDoesNotChangeAGCState(testCase)
            %% Validates Empty End-of-Stream Frames Are State-Neutral

            P = testCase.createDefaultParameters();
            A = AGC(P);

            A.GainControl(0.2 * ones(20, 1));

            StateBeforeEmptyFrame = [ ...
                A.Envelope, A.Gain, A.GateGain, ...
                A.SamplesProcessed, A.FramesProcessed];

            [OutputFrame, TimeFrame, History] = ...
                A.GainControl(zeros(0, 1));

            StateAfterEmptyFrame = [ ...
                A.Envelope, A.Gain, A.GateGain, ...
                A.SamplesProcessed, A.FramesProcessed];

            testCase.verifySize(OutputFrame, [0, 1]);
            testCase.verifySize(TimeFrame, [0, 1]);
            testCase.verifySize(History.Gain, [0, 1]);
            testCase.verifySize(History.SampleIndex, [0, 1]);
            testCase.verifyEqual( ...
                StateAfterEmptyFrame, StateBeforeEmptyFrame);
        end

        function testInvalidAGCFrameInputIsRejected(testCase)
            %% Validates AGC Frame Input Must Be a Finite Real Vector

            P = testCase.createDefaultParameters();
            A = AGC(P);

            InvalidFrames = { ...
                ones(2, 2), ...
                [1; NaN], ...
                [1; Inf], ...
                [1; 1i] ...
                };

            for k = 1:numel(InvalidFrames)
                InvalidFrame = InvalidFrames{k};

                testCase.verifyError( ...
                    @() A.GainControl(InvalidFrame), ...
                    'AGC:InvalidInputFrame');
            end

            testCase.verifyEqual(A.Envelope, 0.0);
            testCase.verifyEqual(A.Gain, 1.0);
            testCase.verifyEqual(A.GateGain, 1.0);
            testCase.verifyEqual(A.SamplesProcessed, 0);
            testCase.verifyEqual(A.FramesProcessed, 0);
        end
    end

    methods (Access = private)

        function P = createDefaultParameters(testCase)
            %% Creates Default Parameters Object For AGC Unit Tests

            P = ADCParameters();

            P.setValue("Fs", 1000);
            P.setValue("Anf", 1e-3);
            P.setValue("Vfs", 1.0);

            P.setValue("EnvAttack", 0.005);
            P.setValue("EnvRelease", 0.020);

            P.setValue("GainAttack", 0.005);
            P.setValue("GainRelease", 0.020);

            P.setValue("GateAttack", 0.005);
            P.setValue("GateRelease", 0.020);

            % Confirm required parameters are valid and readable.
            testCase.verifyEqual(P.getValue("Fs"), 1000);
            testCase.verifyEqual(P.getValue("Anf"), 1e-3);
            testCase.verifyEqual(P.getValue("Vfs"), 1.0);
        end

        function [Output, Time, History] = ...
                processInFrames(testCase, A, InputSignal, FrameLengths)
            %% Processes One Signal Using an Explicit Frame Partition

            if sum(FrameLengths) ~= numel(InputSignal)
                error('TestAGC:FrameLengthMismatch', ...
                    ['The frame lengths must contain every input ', ...
                     'sample exactly once.']);
            end

            Output = zeros(0, 1);
            Time = zeros(0, 1);
            History = testCase.createEmptyHistory();
            StartIndex = 1;

            for k = 1:numel(FrameLengths)
                EndIndex = StartIndex + FrameLengths(k) - 1;
                InputFrame = InputSignal(StartIndex:EndIndex);

                [OutputFrame, TimeFrame, HistoryFrame] = ...
                    A.GainControl(InputFrame);

                Output = [Output; OutputFrame]; %#ok<AGROW>
                Time = [Time; TimeFrame]; %#ok<AGROW>
                History = testCase.appendHistory( ...
                    History, HistoryFrame);

                StartIndex = EndIndex + 1;
            end
        end

        function History = createEmptyHistory(~)
            %% Creates an Empty History Structure in AGC Field Order

            History.Gain = zeros(0, 1);
            History.EffectiveGain = zeros(0, 1);
            History.Envelope = zeros(0, 1);
            History.ProjectedEnvelope = zeros(0, 1);
            History.AGCSignal = zeros(0, 1);
            History.GateGain = zeros(0, 1);
            History.SampleIndex = zeros(0, 1);
        end

        function CombinedHistory = appendHistory( ...
                ~, CombinedHistory, FrameHistory)
            %% Appends Every History Field From One Processed Frame

            FieldNames = fieldnames(CombinedHistory);

            for k = 1:numel(FieldNames)
                FieldName = FieldNames{k};
                CombinedHistory.(FieldName) = [ ...
                    CombinedHistory.(FieldName); ...
                    FrameHistory.(FieldName)];
            end
        end

        function verifyHistoryEqual(testCase, Actual, Expected)
            %% Compares Complete AGC History Structures Field by Field

            ActualFieldNames = fieldnames(Actual);
            ExpectedFieldNames = fieldnames(Expected);
            testCase.verifyEqual( ...
                ActualFieldNames, ExpectedFieldNames);

            for k = 1:numel(ExpectedFieldNames)
                FieldName = ExpectedFieldNames{k};
                testCase.verifyEqual( ...
                    Actual.(FieldName), Expected.(FieldName), ...
                    "AbsTol", 1e-12);
            end
        end

        function P = createSignalChainParameters(testCase)
            %% Creates Parameters for Generator -> HPF -> LPF -> AGC

            P = testCase.createDefaultParameters();

            % Shared streaming axes: 100 samples in 32-sample frames.
            P.setValue("Fs", 20000);
            P.setValue("FrameLength", 32);
            P.setValue("Dur", 0.005);

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

            % HPF and LPF parameters used by the shared ADCFilter class.
            P.setValue("FcHigh", 20);
            P.setValue("FcLow", 5000);
            P.setValue("nHpf", 4);
            P.setValue("nLpf", 6);
        end
    end
end
