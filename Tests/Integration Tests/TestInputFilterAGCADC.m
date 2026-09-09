classdef TestInputFilterAGCADC < matlab.unittest.TestCase
    %% =======================================
    %% INTEGRATED TEST SUITE FOR THE ADC CLASS
    %% =======================================

    methods (Test)
        function testSignalChainThroughSamplerFrameIntegration(testCase)
            %% Validates Generator -> HPF -> LPF -> AGC -> Sampler

            P = testCase.createSignalChainParameters();
            DF = P.getValue("DF");

            OldRngState = rng;
            CleanupObj = onCleanup(@() rng(OldRngState)); 
            rng(29, "twister");

            SG = SignalGenerator(P);
            FrameFilter = ADCFilter(P);
            FrameAGC = AGC(P);
            FrameADC = ADC(P);

            CompleteInput = zeros(0, 1);
            CompleteAGCOutput = zeros(0, 1);
            CompleteSampledOutput = zeros(0, 1);
            CompleteSampleIndex = zeros(0, 1);
            ADCSamplingFrequency = NaN;

            while ~SG.IsDone()
                InputFrame = SG.GenNoisySignal();
                HPFOutputFrame = ...
                    FrameFilter.ProcessHPFFrame(InputFrame);
                LPFOutputFrame = ...
                    FrameFilter.ProcessLPFFrame(HPFOutputFrame);
                AGCOutputFrame = ...
                    FrameAGC.GainControl(LPFOutputFrame);
                [SampledOutputFrame, SampleIndexFrame, FrameFrequency] = ...
                    FrameADC.Sampler(AGCOutputFrame);

                CompleteInput = ...
                    [CompleteInput; InputFrame]; %#ok<AGROW>
                CompleteAGCOutput = ...
                    [CompleteAGCOutput; AGCOutputFrame]; %#ok<AGROW>
                CompleteSampledOutput = ...
                    [CompleteSampledOutput; SampledOutputFrame]; %#ok<AGROW>
                CompleteSampleIndex = ...
                    [CompleteSampleIndex; SampleIndexFrame]; %#ok<AGROW>

                if isnan(ADCSamplingFrequency)
                    ADCSamplingFrequency = FrameFrequency;
                else
                    testCase.verifyEqual( ...
                        FrameFrequency, ADCSamplingFrequency);
                end
            end

            ReferenceFilter = ADCFilter(P);
            [sosHPF, gHPF] = ReferenceFilter.DCRemoval();
            [sosLPF, gLPF] = ReferenceFilter.AAF();
            ExpectedHPFOutput = ...
                sosfilt(sosHPF, gHPF * CompleteInput);
            ExpectedLPFOutput = ...
                sosfilt(sosLPF, gLPF * ExpectedHPFOutput);

            ReferenceAGC = AGC(P);
            ExpectedAGCOutput = ...
                ReferenceAGC.GainControl(ExpectedLPFOutput);

            ExpectedSampleIndex = ...
                (0:DF:numel(ExpectedAGCOutput)-1)';
            ExpectedSampledOutput = ...
                ExpectedAGCOutput(ExpectedSampleIndex + 1);

            testCase.verifyEqual( ...
                CompleteAGCOutput, ExpectedAGCOutput, ...
                "AbsTol", 1e-12);
            testCase.verifyEqual( ...
                CompleteSampledOutput, ExpectedSampledOutput, ...
                "AbsTol", 1e-12);
            testCase.verifyEqual( ...
                CompleteSampleIndex, ExpectedSampleIndex);
            testCase.verifyEqual( ...
                ADCSamplingFrequency, P.getValue("Fs") / DF);
            testCase.verifyEqual(FrameADC.InputSamplesProcessed, 100);
            testCase.verifyEqual(FrameADC.OutputSamplesProduced, 25);
            testCase.verifyEqual(FrameADC.FramesProcessed, 4);
            testCase.verifyTrue(SG.IsDone());
        end

        function testSignalChainThroughMidtreadFrameIntegration(testCase)
        %% Validates Generator -> HPF -> LPF -> AGC -> Sampler -> Midtread

            testCase.verifySignalChainThroughQuantizer("Midtread");
        end

        function testSignalChainThroughMidriseFrameIntegration(testCase)
          %% Validates Generator -> HPF -> LPF -> AGC -> Sampler -> Midrise

            testCase.verifySignalChainThroughQuantizer("Midrise");
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

        function verifySignalChainThroughQuantizer( ...
        testCase, QuantizerType) 

            %% Verifies Complete Frame Chain Against Whole-Vector Processing

            P = testCase.createSignalChainParameters();
            DF = P.getValue("DF");
            NumBits = P.getValue("NumBits");

            OldRngState = rng;
            CleanupObj = onCleanup(@() rng(OldRngState)); 
            rng(41, "twister");

            %% Frame-Based Signal Chain

            SG = SignalGenerator(P);
            FrameFilter = ADCFilter(P);
            FrameAGC = AGC(P);
            FrameADC = ADC(P);

            CompleteInput = zeros(0, 1);
            CompleteHPFOutput = zeros(0, 1);
            CompleteLPFOutput = zeros(0, 1);
            CompleteAGCOutput = zeros(0, 1);
            CompleteSampledOutput = zeros(0, 1);
            CompleteSampleIndex = zeros(0, 1);
            CompleteQuantizedOutput = zeros(0, 1);
            CompleteQuantizerIndices = zeros(0, 1);
            CompleteQuantizationError = zeros(0, 1);

            ADCSamplingFrequency = NaN;
            NumberFrames = 0;

            while ~SG.IsDone()
                InputFrame = SG.GenNoisySignal();

                HPFOutputFrame = ...
                    FrameFilter.ProcessHPFFrame(InputFrame);

                LPFOutputFrame = ...
                    FrameFilter.ProcessLPFFrame(HPFOutputFrame);

                AGCOutputFrame = ...
                    FrameAGC.GainControl(LPFOutputFrame);

                [SampledOutputFrame, SampleIndexFrame, FrameFrequency] = ...
                    FrameADC.Sampler(AGCOutputFrame);

                switch lower(QuantizerType)
                    case "midtread"
                        [QuantizedOutputFrame, QuantizerIndexFrame, ...
                            QuantizationErrorFrame] = ...
                            FrameADC.Midtread(SampledOutputFrame);

                    case "midrise"
                        [QuantizedOutputFrame, QuantizerIndexFrame, ...
                            QuantizationErrorFrame] = ...
                            FrameADC.Midrise(SampledOutputFrame);

                    otherwise
                        error( ...
                            'TestADC:UnknownQuantizer', ...
                            'QuantizerType must be Midtread or Midrise.');
                end

                CompleteInput = ...
                    [CompleteInput; InputFrame]; %#ok<AGROW>

                CompleteHPFOutput = ...
                    [CompleteHPFOutput; HPFOutputFrame]; %#ok<AGROW>

                CompleteLPFOutput = ...
                    [CompleteLPFOutput; LPFOutputFrame]; %#ok<AGROW>

                CompleteAGCOutput = ...
                    [CompleteAGCOutput; AGCOutputFrame]; %#ok<AGROW>

                CompleteSampledOutput = ...
                    [CompleteSampledOutput; SampledOutputFrame]; %#ok<AGROW>

                CompleteSampleIndex = ...
                    [CompleteSampleIndex; SampleIndexFrame]; %#ok<AGROW>

                CompleteQuantizedOutput = ...
                    [CompleteQuantizedOutput; ...
                    QuantizedOutputFrame]; %#ok<AGROW>

                CompleteQuantizerIndices = ...
                    [CompleteQuantizerIndices; ...
                    QuantizerIndexFrame]; %#ok<AGROW>

                CompleteQuantizationError = ...
                    [CompleteQuantizationError; ...
                    QuantizationErrorFrame]; %#ok<AGROW>

                if isnan(ADCSamplingFrequency)
                    ADCSamplingFrequency = FrameFrequency;
                else
                    testCase.verifyEqual( ...
                        FrameFrequency, ADCSamplingFrequency);
                end

                NumberFrames = NumberFrames + 1;
            end

            %% Whole-Vector Reference

            ReferenceFilter = ADCFilter(P);

            [sosHPF, gHPF] = ReferenceFilter.DCRemoval();
            [sosLPF, gLPF] = ReferenceFilter.AAF();

            ExpectedHPFOutput = ...
                sosfilt(sosHPF, gHPF * CompleteInput);

            ExpectedLPFOutput = ...
                sosfilt(sosLPF, gLPF * ExpectedHPFOutput);

            ReferenceAGC = AGC(P);

            ExpectedAGCOutput = ...
                ReferenceAGC.GainControl(ExpectedLPFOutput);

            ExpectedSampleIndex = ...
                (0:DF:numel(ExpectedAGCOutput)-1)';

            ExpectedSampledOutput = ...
                ExpectedAGCOutput(ExpectedSampleIndex + 1);

            ReferenceADC = ADC(P);

            switch lower(QuantizerType)
                case "midtread"
                    [ExpectedQuantizedOutput, ...
                        ExpectedQuantizerIndices, ...
                        ExpectedQuantizationError] = ...
                        ReferenceADC.Midtread(ExpectedSampledOutput);

                case "midrise"
                    [ExpectedQuantizedOutput, ...
                        ExpectedQuantizerIndices, ...
                        ExpectedQuantizationError] = ...
                        ReferenceADC.Midrise(ExpectedSampledOutput);
            end

            %% Verify Every Signal-Chain Hand-off

            testCase.verifyEqual( ...
                CompleteHPFOutput, ExpectedHPFOutput, ...
                "AbsTol", 1e-12);

            testCase.verifyEqual( ...
                CompleteLPFOutput, ExpectedLPFOutput, ...
                "AbsTol", 1e-12);

            testCase.verifyEqual( ...
                CompleteAGCOutput, ExpectedAGCOutput, ...
                "AbsTol", 1e-12);

            testCase.verifyEqual( ...
                CompleteSampledOutput, ExpectedSampledOutput, ...
                "AbsTol", 1e-12);

            testCase.verifyEqual( ...
                CompleteSampleIndex, ExpectedSampleIndex);

            testCase.verifyEqual( ...
                CompleteQuantizedOutput, ExpectedQuantizedOutput, ...
                "AbsTol", 1e-12);

            testCase.verifyEqual( ...
                CompleteQuantizerIndices, ExpectedQuantizerIndices);

            testCase.verifyEqual( ...
                CompleteQuantizationError, ExpectedQuantizationError, ...
                "AbsTol", 1e-12);

            % Independently confirms the definition of quantization error.
            testCase.verifyEqual( ...
                CompleteQuantizationError, ...
                CompleteQuantizedOutput - CompleteSampledOutput, ...
                "AbsTol", 1e-12);

            %% Verify Code Range and Streaming State

            testCase.verifyGreaterThanOrEqual( ...
                CompleteQuantizerIndices, ...
                zeros(size(CompleteQuantizerIndices)));

            testCase.verifyLessThanOrEqual( ...
                CompleteQuantizerIndices, ...
                (2^NumBits - 1) * ...
                ones(size(CompleteQuantizerIndices)));

            testCase.verifyEqual( ...
                ADCSamplingFrequency, P.getValue("Fs") / DF);

            testCase.verifyEqual( ...
                FrameAGC.SamplesProcessed, numel(CompleteInput));

            testCase.verifyEqual( ...
                FrameAGC.FramesProcessed, NumberFrames);

            testCase.verifyEqual( ...
                FrameADC.InputSamplesProcessed, numel(CompleteInput));

            testCase.verifyEqual( ...
                FrameADC.OutputSamplesProduced, ...
                numel(ExpectedSampledOutput));

            testCase.verifyEqual( ...
                FrameADC.FramesProcessed, NumberFrames);

            testCase.verifyTrue(SG.IsDone());
        end    
    end
end
