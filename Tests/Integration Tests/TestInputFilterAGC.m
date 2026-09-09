classdef TestInputFilterAGC < matlab.unittest.TestCase
    %% =======================================
    %% INTEGRATED TEST SUITE FOR THE AGC CLASS
    %% =======================================

    methods (Test)
         function testSignalGeneratorToFiltersToAGCFrameIntegration(testCase)
            %% Validates Signal Generator -> HPF -> LPF -> AGC Chain

            P = testCase.createSignalChainParameters();

            OldRngState = rng;
            CleanupObj = onCleanup(@() rng(OldRngState)); 
            rng(21, "twister");

            SG = SignalGenerator(P);
            FrameFilter = ADCFilter(P);
            FrameAGC = AGC(P);

            CompleteInput = zeros(0, 1);
            CompleteLPFOutput = zeros(0, 1);
            CompleteAGCOutput = zeros(0, 1);
            CompleteTime = zeros(0, 1);
            CompleteHistory = testCase.createEmptyHistory();

            while ~SG.IsDone()
                InputFrame = SG.GenNoisySignal();
                HPFOutputFrame = ...
                    FrameFilter.ProcessHPFFrame(InputFrame);
                LPFOutputFrame = ...
                    FrameFilter.ProcessLPFFrame(HPFOutputFrame);
                [AGCOutputFrame, TimeFrame, HistoryFrame] = ...
                    FrameAGC.GainControl(LPFOutputFrame);

                CompleteInput = ...
                    [CompleteInput; InputFrame]; %#ok<AGROW>
                CompleteLPFOutput = ...
                    [CompleteLPFOutput; LPFOutputFrame]; %#ok<AGROW>
                CompleteAGCOutput = ...
                    [CompleteAGCOutput; AGCOutputFrame]; %#ok<AGROW>
                CompleteTime = ...
                    [CompleteTime; TimeFrame]; %#ok<AGROW>
                CompleteHistory = testCase.appendHistory( ...
                    CompleteHistory, HistoryFrame);
            end

            ReferenceFilter = ADCFilter(P);
            [sosHPF, gHPF] = ReferenceFilter.DCRemoval();
            [sosLPF, gLPF] = ReferenceFilter.AAF();

            ExpectedHPFOutput = ...
                sosfilt(sosHPF, gHPF * CompleteInput);
            ExpectedLPFOutput = ...
                sosfilt(sosLPF, gLPF * ExpectedHPFOutput);

            ReferenceAGC = AGC(P);
            [ExpectedAGCOutput, ExpectedTime, ExpectedHistory] = ...
                ReferenceAGC.GainControl(ExpectedLPFOutput);

            testCase.verifyEqual( ...
                CompleteLPFOutput, ExpectedLPFOutput, ...
                "AbsTol", 1e-12);
            testCase.verifyEqual( ...
                CompleteAGCOutput, ExpectedAGCOutput, ...
                "AbsTol", 1e-12);
            testCase.verifyEqual( ...
                CompleteTime, ExpectedTime, "AbsTol", 1e-12);
            testCase.verifyHistoryEqual( ...
                CompleteHistory, ExpectedHistory);
            testCase.verifyEqual(FrameAGC.SamplesProcessed, 100);
            testCase.verifyEqual(FrameAGC.FramesProcessed, 4);
            testCase.verifyTrue(SG.IsDone());
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
