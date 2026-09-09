classdef TestSignalGenerator < matlab.unittest.TestCase
    %% =====================================================
    %% UNIT TEST SUITE FOR THE FRAME-BASED SIGNAL GENERATOR
    %% =====================================================

    methods (Test)
        function testConstructorStoresParametersAndInitialState(testCase)
            %% Validates constructor storage and initial frame state.
            P = testCase.createDefaultParameters();
            SG = SignalGenerator(P);

            testCase.verifySameHandle(SG.ADCParameters, P);
            testCase.verifyEqual(SG.NextSampleIndex, 0);
            testCase.verifyEqual(SG.FramesGenerated, 0);
            testCase.verifyFalse(SG.IsDone());
        end

        function testFirstFrameHasRequestedLengthAndGlobalAxes(testCase)
            %% Validates Nf samples and zero-based global sample indexing.
            P = testCase.createDefaultParameters();
            SG = SignalGenerator(P);
            FrameLength = 6;

            [SignalFrame, tFrame, Components, FrameInfo] = ...
                SG.GenNoisySignal();

            Fs = P.getValue("Fs");
            ExpectedSampleIndex = (0:FrameLength - 1)';

            testCase.verifySize(SignalFrame, [FrameLength, 1]);
            testCase.verifyEqual( ...
                tFrame, ExpectedSampleIndex / Fs, "AbsTol", 1e-12);
            testCase.verifyEqual( ...
                FrameInfo.SampleIndex, ExpectedSampleIndex);
            testCase.verifyEqual(FrameInfo.StartSampleIndex, 0);
            testCase.verifyEqual(FrameInfo.EndSampleIndex, 5);
            testCase.verifyEqual(FrameInfo.NumValidSamples, FrameLength);
            testCase.verifyEqual(FrameInfo.FrameNumber, 1);
            testCase.verifyFalse(FrameInfo.IsLastFrame);

            ComponentNames = fieldnames(Components);
            for k = 1:numel(ComponentNames)
                testCase.verifySize( ...
                    Components.(ComponentNames{k}), [FrameLength, 1]);
            end

            testCase.verifyEqual(SG.NextSampleIndex, FrameLength);
            testCase.verifyEqual(SG.FramesGenerated, 1);
        end

        function testSuccessiveFramesUseContinuousGlobalTime(testCase)
            %% Validates that each frame continues where the prior frame ended.
            P = testCase.createDefaultParameters();
            SG = SignalGenerator(P);

            [~, ~, ~, FirstInfo] = ...
                SG.GenNoisySignal();
            [~, SecondTime, ~, SecondInfo] = ...
                SG.GenNoisySignal();

            Fs = P.getValue("Fs");
            ExpectedSecondIndices = (6:11)';

            testCase.verifyEqual( ...
                FirstInfo.SampleIndex, (0:5)');
            testCase.verifyEqual( ...
                SecondInfo.SampleIndex, ExpectedSecondIndices);
            testCase.verifyEqual( ...
                SecondTime, ExpectedSecondIndices / Fs, ...
                "AbsTol", 1e-12);
            testCase.verifyEqual(SecondInfo.FrameNumber, 2);
            testCase.verifyEqual(SG.NextSampleIndex, 12);
        end

        function testFinalPartialFrameAndEndOfStream(testCase)
            %% N=20 and Nf=6 must produce frame lengths [6 6 6 2].
            P = testCase.createDefaultParameters();
            SG = SignalGenerator(P);

            [Signal, Time, ~, FrameInfo] = ...
                testCase.collectAllFrames(SG);

            testCase.verifySize(Signal, [20, 1]);
            testCase.verifySize(Time, [20, 1]);
            testCase.verifyEqual( ...
                [FrameInfo.NumValidSamples], [6, 6, 6, 2]);
            testCase.verifyEqual( ...
                [FrameInfo.FrameNumber], [1, 2, 3, 4]);
            testCase.verifyEqual( ...
                [FrameInfo.IsLastFrame], ...
                [false, false, false, true]);
            testCase.verifyTrue(SG.IsDone());
            testCase.verifyEqual(SG.NextSampleIndex, 20);

            [EmptySignal, EmptyTime, EmptyComponents, EmptyInfo] = ...
                SG.GenNoisySignal();

            testCase.verifySize(EmptySignal, [0, 1]);
            testCase.verifySize(EmptyTime, [0, 1]);
            testCase.verifySize(EmptyComponents.Envelope, [0, 1]);
            testCase.verifyEqual(EmptyInfo.NumValidSamples, 0);
            testCase.verifyTrue(EmptyInfo.IsLastFrame);
            testCase.verifyEqual(SG.FramesGenerated, 4);
        end

        function testConcatenatedFramesMatchSignalFormula(testCase)
            %% Validates frame boundaries do not change deterministic output.
            P = testCase.createDefaultParameters();
            P.setValue("Anf", 0);
            P.setValue("FrameLength", 7);

            SG = SignalGenerator(P);

            [ActualSignal, ActualTime, ActualComponents] = ...
                testCase.collectAllFrames(SG);

            Fs = P.getValue("Fs");
            TotalSamples = P.getValue("Fs") * P.getValue("Dur");
            ExpectedTime = (0:TotalSamples - 1)' / Fs;
            [ExpectedSignal, ExpectedComponents] = ...
                testCase.computeExpectedSignal(P, ExpectedTime);

            testCase.verifyEqual( ...
                ActualTime, ExpectedTime, "AbsTol", 1e-12);
            testCase.verifyEqual( ...
                ActualSignal, ExpectedSignal, "AbsTol", 1e-12);
            testCase.verifyEqual( ...
                ActualComponents.Envelope, ...
                ExpectedComponents.Envelope, "AbsTol", 1e-12);
            testCase.verifyEqual( ...
                ActualComponents.DataSignal, ...
                ExpectedComponents.DataSignal, "AbsTol", 1e-12);
            testCase.verifyEqual( ...
                ActualComponents.InterferenceSignal, ...
                ExpectedComponents.NoiseSignal, "AbsTol", 1e-12);
            testCase.verifyEqual( ...
                ActualComponents.DC, ...
                ExpectedComponents.DC, "AbsTol", 1e-12);
        end

        function testTwoDataSignalMethodAddsSecondTone(testCase)
            %% Validates the second tone and preserves one-frame advancement.
            P = testCase.createDefaultParameters();
            P.setValue("Anf", 0);

            SingleGenerator = SignalGenerator(P);
            TwoSignalGenerator = SignalGenerator(P);

            [SingleSignal, SingleTime, SingleComponents, SingleInfo] = ...
                SingleGenerator.GenNoisySignal();

            [TwoSignal, TwoTime, TwoComponents, TwoInfo] = ...
                TwoSignalGenerator.GenNoisyTwoDataSignals();

            ExpectedSecondSignal = ...
                P.getValue("Ad2") * sin( ...
                2 * pi * P.getValue("FData2") * TwoTime);

            testCase.verifyEqual( ...
                TwoTime, SingleTime, "AbsTol", 1e-12);
            testCase.verifyEqual( ...
                TwoInfo.SampleIndex, SingleInfo.SampleIndex);

            testCase.verifyEqual( ...
                TwoComponents.DataSignal1, ...
                SingleComponents.DataSignal, "AbsTol", 1e-12);
            testCase.verifyEqual( ...
                TwoComponents.DataSignal2, ...
                ExpectedSecondSignal, "AbsTol", 1e-12);
            testCase.verifyEqual( ...
                TwoComponents.DataSignal, ...
                SingleComponents.DataSignal + ExpectedSecondSignal, ...
                "AbsTol", 1e-12);

            testCase.verifyEqual( ...
                TwoSignal, SingleSignal + ExpectedSecondSignal, ...
                "AbsTol", 1e-12);

            testCase.verifyEqual( ...
                TwoSignalGenerator.NextSampleIndex, ...
                P.getValue("FrameLength"));
            testCase.verifyEqual( ...
                TwoSignalGenerator.FramesGenerated, 1);
        end

        function testAWGNSequenceContinuesAcrossFrames(testCase)
            %% Validates that the random sequence is not restarted per frame.
            P = testCase.createDefaultParameters();
            P.setValue("Anf", 0.02);

            Fs = P.getValue("Fs");
            TotalSamples = Fs * P.getValue("Dur");
            ExpectedTime = (0:TotalSamples - 1)' / Fs;

            OldRngState = rng;
            CleanupObj = onCleanup(@() rng(OldRngState)); 

            rng(7, "twister");
            ExpectedNoiseFloor = ...
                P.getValue("Anf") * randn(TotalSamples, 1);
            [ExpectedSignal, ~] = testCase.computeExpectedSignal( ...
                P, ExpectedTime, ExpectedNoiseFloor);

            rng(7, "twister");
            SG = SignalGenerator(P);
            [ActualSignal, ~, ActualComponents] = ...
                testCase.collectAllFrames(SG);

            testCase.verifyEqual( ...
                ActualComponents.NoiseFloor, ...
                ExpectedNoiseFloor, "AbsTol", 1e-12);
            testCase.verifyEqual( ...
                ActualSignal, ExpectedSignal, "AbsTol", 1e-12);
        end

        function testResetRestartsFrameAndSamplePosition(testCase)
            %% Validates deterministic replay after position reset.
            P = testCase.createDefaultParameters();
            P.setValue("Anf", 0);

            SG = SignalGenerator(P);

            [FirstSignal, FirstTime, ~, FirstInfo] = ...
                SG.GenNoisySignal();
            SG.GenNoisySignal();

            SG.Reset();

            testCase.verifyEqual(SG.NextSampleIndex, 0);
            testCase.verifyEqual(SG.FramesGenerated, 0);

            [ResetSignal, ResetTime, ~, ResetInfo] = ...
                SG.GenNoisySignal();

            testCase.verifyEqual(ResetSignal, FirstSignal, ...
                "AbsTol", 1e-12);
            testCase.verifyEqual(ResetTime, FirstTime, ...
                "AbsTol", 1e-12);
            testCase.verifyEqual(ResetInfo.SampleIndex, ...
                FirstInfo.SampleIndex);
            testCase.verifyEqual(ResetInfo.FrameNumber, 1);
        end

        function testFrameLengthGreaterThanSignalReturnsOneLastFrame(testCase)
            %% Validates a requested Nf larger than the remaining sample count.
            P = testCase.createDefaultParameters();
            P.setValue("FrameLength", 64);
            SG = SignalGenerator(P);

            [SignalFrame, TimeFrame, ~, FrameInfo] = ...
                SG.GenNoisySignal();

            testCase.verifySize(SignalFrame, [20, 1]);
            testCase.verifySize(TimeFrame, [20, 1]);
            testCase.verifyEqual(FrameInfo.NumValidSamples, 20);
            testCase.verifyTrue(FrameInfo.IsLastFrame);
            testCase.verifyTrue(SG.IsDone());
        end

        function testUnassignedFrameLengthIsRejected(testCase)
            %% Validates that Nf must be assigned before generation starts.
            P = ADCParameters();
            SG = SignalGenerator(P);

            testCase.verifyError( ...
                @() SG.GenNoisySignal(), ...
                'SignalGenerator:InvalidFrameLength');

            testCase.verifyEqual(SG.NextSampleIndex, 0);
            testCase.verifyEqual(SG.FramesGenerated, 0);
        end

        function testNonIntegerTotalSampleCountIsRejected(testCase)
            %% Prevents an ambiguous final sample when Fs*Dur is noninteger.
            P = testCase.createDefaultParameters();
            P.setValue("Dur", 0.0205);
            SG = SignalGenerator(P);

            testCase.verifyError( ...
                @() SG.GenNoisySignal(), ...
                'SignalGenerator:NonIntegerTotalSamples');
        end
    end

    methods (Access = private)
        function P = createDefaultParameters(~)
            %% Creates a fresh, isolated parameter object instance.
            P = ADCParameters();

            P.setValue("Fs", 1000);       % Oversampling frequency, Hz
            P.setValue("Dur", 0.02);      % Duration, seconds (N = 20)
            P.setValue("FrameLength", 6); % Samples processed per frame
            P.setValue("Aburst", 0.5);    % Gaussian burst amplitude
            P.setValue("mu", 0.006);      % Gaussian burst peak location
            P.setValue("Sigma", 0.002);   % Gaussian burst width
            P.setValue("Ad", 1.0);        % Base envelope amplitude
            P.setValue("Ad2", 0.4);       % Second data-signal amplitude
            P.setValue("Lambda", 30);     % Decay constant
            P.setValue("EST", 0.012);     % Exponential fade start time
            P.setValue("FData", 50);      % Data frequency, Hz
            P.setValue("FData2", 120);    % Second data frequency, Hz
            P.setValue("An", 0.1);        % Out-of-band noise amplitude
            P.setValue("Fnoise", 300);    % Out-of-band noise frequency, Hz
            P.setValue("Anf", 0);         % AWGN floor amplitude
            P.setValue("DC", 0.25);       % DC offset
        end

        function [Signal, Time, Components, FrameInfo] = ...
                collectAllFrames(~, SG)
            %% Runs the finite frame source and concatenates valid outputs.
            Signal = zeros(0, 1);
            Time = zeros(0, 1);

            Components.Envelope = zeros(0, 1);
            Components.DataSignal = zeros(0, 1);
            Components.InterferenceSignal = zeros(0, 1);
            Components.NoiseFloor = zeros(0, 1);
            Components.DC = zeros(0, 1);

            FrameInfo = struct([]);

            while ~SG.IsDone()
                [SignalFrame, TimeFrame, ComponentFrame, Info] = ...
                    SG.GenNoisySignal();

                Signal = [Signal; SignalFrame]; %#ok<AGROW>
                Time = [Time; TimeFrame]; %#ok<AGROW>

                Components.Envelope = [Components.Envelope; ...
                    ComponentFrame.Envelope]; 
                Components.DataSignal = [Components.DataSignal; ...
                    ComponentFrame.DataSignal]; 
                Components.InterferenceSignal = [Components.InterferenceSignal; ...
                    ComponentFrame.InterferenceSignal]; 
                Components.NoiseFloor = [Components.NoiseFloor; ...
                    ComponentFrame.NoiseFloor]; 
                Components.DC = [Components.DC; ...
                    ComponentFrame.DC]; 

                if isempty(FrameInfo)
                    FrameInfo = Info;
                else
                    FrameInfo(end + 1) = Info; %#ok<AGROW>
                end
            end
        end

        function [ExpectedSignal, Components] = ...
                computeExpectedSignal(~, P, t, NoiseFloor)
            %% Independent full-vector reference for regression checking.
            if nargin < 4
                NoiseFloor = zeros(size(t));
            end

            Aburst = P.getValue("Aburst");
            mu = P.getValue("mu");
            Sigma = P.getValue("Sigma");
            Ad = P.getValue("Ad");

            BurstEnvelope = Aburst * ...
                exp(-((t - mu).^2) / (2 * Sigma^2));
            Envelope = Ad + BurstEnvelope;

            Lambda = P.getValue("Lambda");
            EST = P.getValue("EST");

            FadeIndex = t >= EST;
            if any(FadeIndex)
                FirstFadeIndex = find(FadeIndex, 1);
                FadeStartValue = Envelope(FirstFadeIndex);
                FadeEnvelope = exp( ...
                    -Lambda * (t(FadeIndex) - EST));
                Envelope(FadeIndex) = ...
                    FadeStartValue * FadeEnvelope;
            end

            FData = P.getValue("FData");
            DataSignal = sin(2 * pi * FData * t) .* Envelope;

            An = P.getValue("An");
            Fnoise = P.getValue("Fnoise");
            InterferenceSignal = An * sin(2 * pi * Fnoise * t);

            DC = P.getValue("DC") * ones(size(t));

            ExpectedSignal = ...
                DC + DataSignal + InterferenceSignal + NoiseFloor;

            Components.Envelope = Envelope;
            Components.DataSignal = DataSignal;
            Components.NoiseSignal = InterferenceSignal;
            Components.NoiseFloor = NoiseFloor;
            Components.DC = DC;
        end
    end
end
